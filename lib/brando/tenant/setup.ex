defmodule Brando.Tenant.Setup do
  @moduledoc """
  Compensated site provisioning and destructive site lifecycle operations.

  A site is not returned until its live and staging environments, tenant
  schemas, initial content, storage directories, and creator assignment all
  exist. Any provisioning failure removes the partial site. A site created
  with `status: :suspended` admits no one, so its environments are
  provisioned as the system once the creator is authorized to create sites.
  Permanent deletion
  is intentionally a second step after archival and a configurable retention
  period.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Environments
  alias Brando.Environments.Schema
  alias Brando.Repo
  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Tenant.Access
  alias Brando.Tenant.Lock
  alias Brando.Tenant.Registry
  alias Brando.Tenant.ScopedRows
  alias Brando.Tenant.Storage
  alias Brando.Users.User

  @default_retention_days 30
  @default_environments [
    %{name: "Production", key: "production", live: true},
    %{name: "Staging", key: "staging", live: false}
  ]

  @spec create_site(map(), User.t(), keyword()) :: {:ok, Site.t()} | {:error, term()}
  def create_site(attrs, %User{} = creator, opts \\ []) do
    scope = Brando.Authorization.Scope.installation(creator)

    with :ok <- Brando.Authorization.Boundary.authorize(scope, :create, :sites),
         :ok <- authorize_hosts(attrs, creator, opts) do
      do_create_site(attrs, creator, opts)
    end
  end

  # A suspended site's environments are created as the system, which may bind
  # hosts, so the creator's own right to is checked here; for an active site
  # the registry checks the creator
  defp authorize_hosts(attrs, creator, opts) do
    as_system? = Map.get(attrs, :status, Map.get(attrs, "status", :active)) not in [:active, "active"]
    binds_host? = opts |> Keyword.get(:environments, @default_environments) |> Enum.any?(&domain?/1)

    if as_system? and binds_host? and not Brando.Authorization.Boundary.superuser?(creator),
      do: {:error, :forbidden},
      else: :ok
  end

  defp domain?(attrs) when is_map(attrs), do: Map.get(attrs, :domain, Map.get(attrs, "domain")) not in [nil, ""]
  defp domain?(_attrs), do: false

  defp do_create_site(attrs, creator, opts) do
    case site_key(attrs) do
      key when is_binary(key) ->
        Lock.with(lifecycle_lock_key(key), fn -> create_under_lock(attrs, creator, opts) end)

      _missing_key ->
        Registry.create_site(attrs)
    end
  end

  @spec suspend_site(Site.t()) :: {:ok, Site.t()} | {:error, term()}
  def suspend_site(%Site{} = site, opts \\ []), do: lifecycle(:update, opts, fn -> update_status(site, :suspended) end)

  @spec activate_site(Site.t()) :: {:ok, Site.t()} | {:error, term()}
  def activate_site(%Site{} = site, opts \\ []), do: lifecycle(:update, opts, fn -> update_status(site, :active) end)

  @spec archive_site(Site.t(), keyword()) :: {:ok, Site.t()} | {:error, term()}
  def archive_site(%Site{} = site, opts \\ []) do
    lifecycle(:delete, opts, fn -> do_archive_site(site, opts) end)
  end

  defp do_archive_site(site, opts) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    Lock.with(lifecycle_lock_key(site.key), fn ->
      case Registry.get_site(site.id) do
        nil -> {:error, :site_not_found}
        %Site{} = current_site -> Registry.update_site(current_site, %{status: :archived, archived_at: now})
      end
    end)
  end

  @spec delete_site(Site.t(), keyword()) :: {:ok, Site.t()} | {:error, term()}
  def delete_site(%Site{} = site, opts \\ []) do
    lifecycle(:delete, opts, fn -> Lock.with(lifecycle_lock_key(site.key), fn -> delete_under_lock(site, opts) end) end)
  end

  @doc """
  Removes what a failed `create_site/3` or migration left of the site `key`
  when its own cleanup failed: the registry row with its environments'
  schemas, the schemas `tenant_<key>_production` and `tenant_<key>_staging`,
  and the site's directories unless `keep_storage: true`.

  The site's lifecycle lock is held throughout, so a site created with the
  key while this runs is not touched. One created before it runs is removed:
  this is for the key of a site that failed.
  """
  @spec remove_leftovers(String.t(), keyword()) :: :ok | {:error, term()}
  def remove_leftovers(key, opts \\ []) when is_binary(key) do
    lifecycle(:delete, opts, fn -> Lock.with(lifecycle_lock_key(key), fn -> remove_under_lock(key, opts) end) end)
  end

  defp remove_under_lock(key, opts) do
    registered =
      case Registry.get_site_by_key(key) do
        nil -> :ok
        site -> with {:ok, _deleted} <- delete_registry_and_schemas(site), do: :ok
      end

    drops = Enum.map(["production", "staging"], &Schema.drop(Tenant.prefix(key, &1)))
    storage = if Keyword.get(opts, :keep_storage, false), do: :ok, else: Storage.delete(%Site{key: key})

    Enum.find([registered | drops] ++ [storage], :ok, &(&1 != :ok))
  end

  defp lifecycle(action, opts, fun) do
    actor = opts[:actor] || Brando.Authorization.Boundary.current_scope()
    with :ok <- Brando.Authorization.Boundary.authorize(actor, action, :sites), do: fun.()
  end

  defp create_under_lock(attrs, creator, opts) do
    with {:ok, site} <- Registry.create_site(attrs) do
      fn -> provision(site, creator, opts) end
      |> rescued()
      |> compensate_failure(site)
    end
  end

  defp compensate_failure({:ok, provisioned_site}, _site), do: {:ok, provisioned_site}

  defp compensate_failure({:error, {:storage_not_created, reason}}, site) do
    compensation = rescued(fn -> compensate(site, delete_storage: false) end)
    {:error, {:site_setup_failed, reason, compensation}}
  end

  defp compensate_failure({:error, reason}, site) do
    compensation = rescued(fn -> compensate(site) end)
    {:error, {:site_setup_failed, reason, compensation}}
  end

  # Once the registry row exists, a raise in provisioning (a structure clone
  # whose executable is missing, say) is compensated like a returned error
  defp rescued(fun) do
    fun.()
  rescue
    exception -> {:error, {:raised, Exception.message(exception)}}
  catch
    kind, reason -> {:error, {:raised, Exception.format_banner(kind, reason)}}
  end

  defp provision(site, creator, opts) do
    environments = Keyword.get(opts, :environments, @default_environments)

    with :ok <- create_storage(site),
         :ok <- validate_environments(environments),
         [live_attrs | remaining_attrs] <- order_live_first(environments),
         {:ok, _assignment} <- assign_creator(creator, site),
         {:ok, live_environment} <- Environments.create_environment(site, live_attrs, actor_opts(site, creator)),
         :ok <- seed(site, live_environment, creator, opts),
         {:ok, _environments} <- create_copies(site, live_environment, remaining_attrs, creator) do
      {:ok, Registry.get_site(site.id)}
    else
      [] -> {:error, :missing_live_environment}
      {:error, _reason} = error -> error
    end
  end

  defp assign_creator(creator, site) do
    if Brando.Authorization.enabled?() do
      scope = Brando.Authorization.Scope.site(creator, site)

      # The installation create check already authorized this new site.
      # Bootstrap its creator before provisioning the first environment.
      Repo.transaction(fn ->
        {:ok, groups} = Brando.Authorization.Migration.seed_scope(scope)
        group = Enum.find(groups, &(&1.preset == :admin))
        Repo.insert!(%Brando.Authorization.Membership{user_id: creator.id, group_id: group.id})

        Repo.insert!(%Brando.Authorization.AuditEvent{
          actor_id: creator.id,
          site_id: site.id,
          group_id: group.id,
          subject_user_id: creator.id,
          action: "membership.provisioned",
          after: %{user_id: creator.id}
        })

        group
      end)
    else
      Access.grant(creator, site, :admin)
    end
  end

  # A site created suspended admits no one, its creator included: its
  # environments are provisioned as the system, which the installation's
  # create check on the creator has already authorized
  defp actor_opts(%Site{status: :active}, creator), do: [creator: creator]
  defp actor_opts(%Site{}, creator), do: [actor: :system, creator_id: creator.id]

  defp create_copies(site, live_environment, environment_attrs, creator) do
    Enum.reduce_while(environment_attrs, {:ok, [live_environment]}, fn attrs, {:ok, environments} ->
      with {:ok, environment} <-
             Environments.create_environment(site, attrs, [clone_structure: false] ++ actor_opts(site, creator)),
           {:ok, _copy} <-
             Environments.copy_environment(
               live_environment,
               environment,
               [keep_archives: 0, note: "Initial site provisioning"] ++ actor_opts(site, creator)
             ) do
        {:cont, {:ok, environments ++ [environment]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp seed(site, environment, creator, opts) do
    if Keyword.get(opts, :seed, true) do
      prefix = Tenant.prefix(site, environment)
      seeder = Brando.config(:tenant_seeder) || Brando.Tenant.Seeder

      # The admin's own scope (an installation scope at `/admin/sites`) does
      # not decide what the seeder may write in the new site
      Brando.Authorization.Boundary.with_scope(nil, fn ->
        Tenant.with_prefix(prefix, fn -> seeder.seed(site, environment, creator) end)
      end)
    else
      :ok
    end
  rescue
    exception -> {:error, {:seeding_failed, exception}}
  end

  defp create_storage(site) do
    case Storage.create(site) do
      :ok -> :ok
      {:error, reason} -> {:error, {:storage_not_created, reason}}
    end
  end

  defp validate_environments(environments) when is_list(environments) do
    if Enum.count(environments, &live?/1) == 1,
      do: :ok,
      else: {:error, :exactly_one_live_environment_required}
  end

  defp validate_environments(_environments), do: {:error, :invalid_environments}

  defp order_live_first(environments) do
    {live, other} = Enum.split_with(environments, &live?/1)
    live ++ other
  end

  defp live?(attrs), do: Map.get(attrs, :live, Map.get(attrs, "live", false)) == true

  defp update_status(site, status) do
    Lock.with(lifecycle_lock_key(site.key), fn ->
      case Registry.get_site(site.id) do
        nil -> {:error, :site_not_found}
        %Site{} = current_site -> Registry.update_site(current_site, %{status: status, archived_at: nil})
      end
    end)
  end

  defp delete_under_lock(site, opts) do
    with %Site{} = current_site <- Registry.get_site(site.id),
         :ok <- deletable?(current_site, opts),
         {:ok, deleted_site} <- delete_registry_and_schemas(current_site),
         :ok <- Storage.delete(current_site) do
      {:ok, deleted_site}
    else
      nil -> {:error, :site_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp deletable?(%Site{status: :archived, archived_at: %DateTime{} = archived_at}, opts) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    retention_days =
      Keyword.get(opts, :retention_days, Brando.config(:site_delete_retention_days) || @default_retention_days)

    if Keyword.get(opts, :force, false) or DateTime.diff(now, archived_at, :day) >= retention_days,
      do: :ok,
      else: {:error, {:retention_period, retention_days}}
  end

  defp deletable?(%Site{}, _opts), do: {:error, :site_must_be_archived}

  defp delete_registry_and_schemas(site) do
    Repo.transaction(fn ->
      prefixes = site_schema_prefixes(site)
      Enum.each(prefixes, &drop_schema!/1)
      ScopedRows.delete(prefixes)
      delete_registry_site!(site)
    end)
  end

  defp drop_schema!(prefix) do
    case Schema.drop(prefix) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback({:schema_drop_failed, prefix, reason})
    end
  end

  defp delete_registry_site!(site) do
    case Registry.delete_site(site) do
      {:ok, deleted_site} -> deleted_site
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # `:ok` only when everything it removes is gone; otherwise the first error
  defp compensate(site, opts \\ []) do
    prefixes = site_schema_prefixes(site)
    cancel_jobs(prefixes)
    drops = Enum.map(prefixes, &Schema.drop/1)
    storage = if Keyword.get(opts, :delete_storage, true), do: Storage.delete(site), else: :ok

    registry =
      case Registry.get_site(site.id) do
        nil -> :ok
        current_site -> with {:ok, _deleted} <- Registry.delete_site(current_site), do: :ok
      end

    Enum.find(drops ++ [storage, registry], :ok, &(&1 != :ok))
  end

  # What provisioning queued in the site's environments (the seeded menu's
  # render cascade, say) would otherwise run against the schemas dropped here;
  # one running now is stopped
  defp cancel_jobs([]), do: :ok

  defp cancel_jobs(prefixes) do
    from(job in Oban.Job, where: fragment("?->>'tenant_prefix'", job.args) in ^prefixes)
    |> Oban.cancel_all_jobs()

    :ok
  end

  defp site_schema_prefixes(site) do
    environment_prefixes =
      site
      |> Registry.list_environments()
      |> Enum.map(&Tenant.prefix(site, &1))

    archive_prefixes = Enum.map(Environments.list_archives(site), & &1.schema)
    Enum.uniq(environment_prefixes ++ archive_prefixes)
  end

  defp site_key(attrs), do: Map.get(attrs, :key, Map.get(attrs, "key"))

  @doc false
  def lifecycle_lock_key(site_key), do: "brando:site-lifecycle:#{site_key}"
end
