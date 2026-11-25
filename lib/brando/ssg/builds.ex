defmodule Brando.SSG.Builds do
  @moduledoc """
  Public lifecycle API for versioned static-site builds.

  Build metadata lives in the public schema while generated output stays in
  persistent per-site storage. Creating a build and enqueueing its Oban job is
  serialized per site so automatically assigned versions remain monotonic.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Assets.SiteAssets
  alias Brando.Assets.SiteAssetSet
  alias Brando.Environments.Environment
  alias Brando.Repo
  alias Brando.Sites.DeployConfig
  alias Brando.Sites.Site
  alias Brando.SSG.Build
  alias Brando.Tenant
  alias Brando.Tenant.Lock
  alias Brando.Tenant.Storage
  alias Brando.Worker.SSGBuild

  @public_opts [prefix: "public"]
  @preview_lifetime_days 7

  @doc """
  Queues a versioned build for one named environment. Its assets are the set
  the environment uses (`Brando.Assets.SiteAssets.effective_set/2`), unless
  `:asset_set` names one. It deploys when it is ready if `:auto_deploy` (by
  default the site's setting) says so and the site has a deployment target
  (`deploy_target?/1`).
  """
  @spec request_build(Site.t(), Environment.t(), keyword()) ::
          {:ok, Build.t()} | {:error, Ecto.Changeset.t() | term()}
  def request_build(%Site{} = site, %Environment{} = environment, opts \\ []) do
    asset_set = Keyword.get_lazy(opts, :asset_set, fn -> SiteAssets.effective_set(asset_scope(site), environment) end)
    opts = Keyword.put(opts, :asset_set, asset_set)

    with :ok <-
           Brando.Authorization.Operations.authorize(
             opts[:creator] || Brando.Authorization.Boundary.current_scope() || %{id: opts[:creator_id]},
             :build,
             :publishing,
             site.id
           ),
         :ok <- authorize_build_options(site, opts),
         :ok <- validate_build_request(site, environment, opts) do
      Lock.with("ssg-build:#{site.id}", fn -> insert_build_and_job(site, environment, opts) end)
    end
  end

  defp authorize_build_options(site, opts) do
    actor = opts[:creator] || Brando.Authorization.Boundary.current_scope() || %{id: opts[:creator_id]}

    actions =
      [:schedule, :deploy]
      |> Enum.filter(fn
        :schedule -> not is_nil(opts[:scheduled_at])
        :deploy -> auto_deploy?(site, opts)
      end)

    Enum.reduce_while(actions, :ok, fn action, :ok ->
      case Brando.Authorization.Operations.authorize(actor, action, :publishing, site.id) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc "Lists builds newest first, optionally limited by `:limit`."
  @spec list_builds(Site.t(), keyword()) :: [Build.t()]
  def list_builds(%Site{id: site_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(build in Build,
      where: build.site_id == ^site_id,
      order_by: [desc: build.build_number],
      limit: ^limit,
      preload: [:environment, :asset_set, :creator]
    )
    |> Repo.all(@public_opts)
  end

  @doc "Returns one build with its public associations preloaded."
  @spec get_build(pos_integer()) :: Build.t() | nil
  def get_build(id) do
    Build
    |> Repo.get(id, @public_opts)
    |> preload()
  end

  @doc """
  Returns a previewable build by its unguessable token, built for `site`.
  Pass `:any` only where tenancy is disabled.
  """
  @spec get_preview(String.t(), Site.t() | :any) :: Build.t() | nil
  def get_preview(token, site) when is_binary(token) do
    now = DateTime.utc_now()

    from(build in Build,
      where:
        build.preview_token == ^token and build.preview_expires_at > ^now and
          build.status in [:ready, :deployed, :archived],
      preload: [:site, :environment]
    )
    |> where_site(site)
    |> Repo.one(@public_opts)
  end

  defp where_site(query, :any), do: query
  defp where_site(query, %Site{id: site_id}), do: from(build in query, where: build.site_id == ^site_id)

  @doc "Records coarse URL progress for the publishing UI."
  @spec update(Build.t(), map()) :: {:ok, Build.t()} | {:error, Ecto.Changeset.t()}
  def update(%Build{} = build, attrs) do
    result = build |> Build.changeset(attrs) |> Repo.update(@public_opts)

    case result do
      {:ok, updated_build} ->
        broadcast(updated_build)
        {:ok, updated_build}

      {:error, _changeset} = error ->
        error
    end
  end

  @doc "Appends a timestamped line to a build log."
  @spec append_log(Build.t(), String.t()) :: {:ok, Build.t()} | {:error, Ecto.Changeset.t()}
  def append_log(%Build{} = build, message) when is_binary(message) do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S UTC")
    update(build, %{build_log: build.build_log <> "[#{timestamp}] #{message}\n"})
  end

  @doc "Records coarse URL progress for the publishing UI."
  @spec record_progress(pos_integer(), non_neg_integer(), non_neg_integer() | nil) :: :ok
  def record_progress(build_id, processed_urls, url_count \\ nil) do
    fields =
      [processed_urls: processed_urls, updated_at: DateTime.utc_now()]
      |> then(fn fields -> if is_integer(url_count), do: Keyword.put(fields, :url_count, url_count), else: fields end)

    from(build in Build, where: build.id == ^build_id)
    |> Repo.update_all([set: fields], @public_opts)

    case get_build(build_id) do
      %Build{} = build -> broadcast(build)
      nil -> :ok
    end
  end

  @doc "Returns the persistent root containing one site's versioned artifacts."
  @spec build_root(Site.t()) :: String.t()
  def build_root(%Site{} = site), do: Path.join([Storage.site_root(site), "ssg", "builds"])

  @doc "Broadcasts a build transition to connected publishing screens."
  @spec broadcast(Build.t()) :: :ok
  def broadcast(%Build{site_id: site_id} = build) do
    Phoenix.PubSub.broadcast(Brando.pubsub(), topic(site_id), {:ssg_build_updated, build})
  end

  @doc "Returns the PubSub topic for a site's build lifecycle."
  @spec topic(Site.t() | pos_integer()) :: String.t()
  def topic(%Site{id: site_id}), do: topic(site_id)
  def topic(site_id), do: "ssg:site:#{site_id}"

  defp validate_build_request(%Site{status: status}, _environment, _opts) when status != :active,
    do: {:error, :inactive_site}

  defp validate_build_request(%Site{delivery_mode: mode}, _environment, _opts) when mode != :static,
    do: {:error, :dynamic_site}

  defp validate_build_request(%Site{id: site_id}, %Environment{site_id: site_id}, opts) do
    expected_site_id = if Tenant.mode() == :multi, do: site_id

    case Keyword.get(opts, :asset_set) do
      nil -> :ok
      %SiteAssetSet{site_id: ^expected_site_id} -> :ok
      %SiteAssetSet{} -> {:error, :asset_set_belongs_to_another_site}
      _invalid -> {:error, :invalid_asset_set}
    end
  end

  defp validate_build_request(%Site{}, %Environment{}, _opts), do: {:error, :environment_belongs_to_another_site}

  defp insert_build_and_job(site, environment, opts) do
    build_number = next_build_number(site.id)
    version = "v#{build_number}"
    asset_set = Keyword.get(opts, :asset_set)
    scheduled_at = Keyword.get(opts, :scheduled_at)
    deploy_config = deploy_config(site)

    attrs = %{
      site_id: site.id,
      environment_id: environment.id,
      environment_name: environment.name,
      environment_key: environment.key,
      asset_set_id: asset_set && asset_set.id,
      creator_id: Keyword.get(opts, :creator_id),
      version: version,
      build_number: build_number,
      status: :queued,
      build_path: Path.join(build_root(site), version),
      note: Keyword.get(opts, :note),
      auto_deploy: auto_deploy?(site, opts),
      deploy_config: deploy_config,
      markdown_context: Keyword.get(opts, :markdown_context, %{}),
      preview_token: preview_token(),
      preview_expires_at: DateTime.add(DateTime.utc_now(), @preview_lifetime_days, :day),
      scheduled_at: scheduled_at
    }

    # Inside a caller's transaction the build may still be rolled back
    in_transaction? = Repo.repo().in_transaction?()

    # Reported before the job, which may run (and report) the moment it is
    # committed; a scheduled build reports when it runs
    report_queued? = not in_transaction? and is_nil(scheduled_at)

    Repo.transaction(fn ->
      with {:ok, build} <- %Build{} |> Build.changeset(attrs) |> Repo.insert(@public_opts),
           :ok <- report_queued(build, report_queued?),
           {:ok, _job} <- enqueue_or_withdraw(build, scheduled_at, report_queued?) do
        build
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, build} ->
        broadcast(build)
        {:ok, build}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp report_queued(build, true), do: SSGBuild.report_queued(build)
  defp report_queued(_build, false), do: :ok

  defp enqueue_or_withdraw(build, scheduled_at, reported?) do
    with {:error, _reason} = error <- enqueue(build, scheduled_at) do
      if reported?, do: SSGBuild.report_failed(build)
      error
    end
  end

  defp enqueue(build, nil) do
    build
    |> job_args()
    |> SSGBuild.new(tags: ["ssg-build", "site:#{build.site_id}"])
    |> SSGBuild.track(build)
    |> Oban.insert()
  end

  defp enqueue(build, %DateTime{} = scheduled_at) do
    build
    |> job_args()
    |> SSGBuild.new(scheduled_at: scheduled_at, tags: ["ssg-build", "site:#{build.site_id}"])
    |> SSGBuild.track(build)
    |> Oban.insert()
  end

  defp enqueue(_build, scheduled_at), do: {:error, {:invalid_scheduled_at, scheduled_at}}

  # The recorded set goes with the job too: deleting a set clears the build's
  # `asset_set_id`, and the job then tells a deleted set from none
  defp job_args(build), do: %{"build_id" => build.id, "asset_set_id" => build.asset_set_id}

  defp next_build_number(site_id) do
    from(build in Build, where: build.site_id == ^site_id, select: max(build.build_number))
    |> Repo.one(@public_opts)
    |> Kernel.||(0)
    |> Kernel.+(1)
  end

  # Only with a target to deploy to: without one a deploy can only fail
  defp auto_deploy?(%Site{} = site, opts) do
    deploy_target?(site) and Keyword.get(opts, :auto_deploy, site_auto_deploy?(site)) == true
  end

  # From the struct: `deploy_config/1` serializes booleans as strings
  defp site_auto_deploy?(%Site{deploy_config: %DeployConfig{auto_deploy: auto_deploy}}), do: auto_deploy == true
  defp site_auto_deploy?(%Site{}), do: false

  @doc """
  Whether `user` may manage `site`'s publishing, as the Publishing screen
  asks before each action: build, deploy or schedule with capabilities on,
  else a site's manager with several sites (`Brando.Tenant.Access`), or an
  admin or superuser.
  """
  @spec can_manage?(term(), Site.t()) :: boolean()
  def can_manage?(%Brando.Users.User{} = user, %Site{} = site) do
    if Brando.Authorization.enabled?() do
      scope = Brando.Authorization.Scope.site(user, site)
      Enum.any?([:build, :deploy, :schedule], &Brando.Authorization.can?(scope, &1, :publishing))
    else
      case Tenant.mode() do
        :multi -> Brando.Tenant.Access.can_manage?(user, site)
        _other -> user.role in [:admin, :superuser]
      end
    end
  end

  def can_manage?(_user, _site), do: false

  @doc """
  Whether a site's deployment settings say where builds deploy to: a strategy
  and a target, or `local`, which the installation serves itself and has no
  target.
  """
  @spec deploy_target?(Site.t() | map()) :: boolean()
  def deploy_target?(%Site{} = site), do: deploy_target?(deploy_config(site))
  def deploy_target?(%{"strategy" => "local"}), do: true
  def deploy_target?(config), do: config["strategy"] not in [nil, ""] and config["target"] not in [nil, ""]

  # What a build deploys with. Anything else is read from the site when the
  # deploy runs: its key and accepted host keys (`Brando.SSG.SSH`).
  @snapshot_fields [:strategy, :target, :port, :cdn_url, :webhook_url, :auto_deploy, :retention_count]

  defp deploy_config(%Site{deploy_config: %DeployConfig{} = config}) do
    config
    |> Map.take(@snapshot_fields)
    |> Map.new(fn {key, value} -> {to_string(key), encode(value)} end)
  end

  defp deploy_config(%Site{}), do: %{}

  defp encode(nil), do: nil
  defp encode(value) when is_atom(value), do: Atom.to_string(value)
  defp encode(value), do: value

  defp asset_scope(site), do: if(Tenant.mode() == :multi, do: site)

  defp preview_token, do: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

  defp preload(nil), do: nil
  defp preload(build), do: Repo.preload(build, [:site, :environment, :asset_set, :creator], @public_opts)
end
