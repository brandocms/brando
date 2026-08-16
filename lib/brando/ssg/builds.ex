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

  @doc "Queues a versioned build for one named environment."
  @spec request_build(Site.t(), Environment.t(), keyword()) ::
          {:ok, Build.t()} | {:error, Ecto.Changeset.t() | term()}
  def request_build(%Site{} = site, %Environment{} = environment, opts \\ []) do
    asset_set = Keyword.get_lazy(opts, :asset_set, fn -> SiteAssets.active_set(asset_scope(site)) end)
    opts = Keyword.put(opts, :asset_set, asset_set)

    with :ok <- validate_build_request(site, environment, opts) do
      Lock.with("ssg-build:#{site.id}", fn -> insert_build_and_job(site, environment, opts) end)
    end
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

  @doc "Returns a previewable build by its unguessable token."
  @spec get_preview(String.t()) :: Build.t() | nil
  def get_preview(token) when is_binary(token) do
    now = DateTime.utc_now()

    from(build in Build,
      where:
        build.preview_token == ^token and build.preview_expires_at > ^now and
          build.status in [:ready, :deployed, :archived],
      preload: [:site, :environment]
    )
    |> Repo.one(@public_opts)
  end

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
      auto_deploy: Keyword.get(opts, :auto_deploy, deploy_config["auto_deploy"] || false),
      deploy_config: deploy_config,
      preview_token: preview_token(),
      preview_expires_at: DateTime.add(DateTime.utc_now(), @preview_lifetime_days, :day),
      scheduled_at: scheduled_at
    }

    Repo.transaction(fn ->
      with {:ok, build} <- %Build{} |> Build.changeset(attrs) |> Repo.insert(@public_opts),
           {:ok, _job} <- enqueue(build, scheduled_at) do
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

  defp enqueue(build, nil) do
    build.id
    |> then(&SSGBuild.new(%{"build_id" => &1}, tags: ["ssg-build", "site:#{build.site_id}"]))
    |> Oban.insert()
  end

  defp enqueue(build, %DateTime{} = scheduled_at) do
    build.id
    |> then(
      &SSGBuild.new(%{"build_id" => &1},
        scheduled_at: scheduled_at,
        tags: ["ssg-build", "site:#{build.site_id}"]
      )
    )
    |> Oban.insert()
  end

  defp enqueue(_build, scheduled_at), do: {:error, {:invalid_scheduled_at, scheduled_at}}

  defp next_build_number(site_id) do
    from(build in Build, where: build.site_id == ^site_id, select: max(build.build_number))
    |> Repo.one(@public_opts)
    |> Kernel.||(0)
    |> Kernel.+(1)
  end

  defp deploy_config(%Site{deploy_config: %DeployConfig{} = config}) do
    config
    |> Map.from_struct()
    |> Map.drop([:__meta__])
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
