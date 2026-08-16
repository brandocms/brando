defmodule Brando.Tenant.Setup do
  @moduledoc """
  Compensated site provisioning and destructive site lifecycle operations.

  A site is not returned until its live and staging environments, tenant
  schemas, initial content, storage directories, and creator assignment all
  exist. Any provisioning failure removes the partial site. Permanent deletion
  is intentionally a second step after archival and a configurable retention
  period.
  """

  alias Brando.Environments
  alias Brando.Environments.Schema
  alias Brando.Repo
  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Tenant.Access
  alias Brando.Tenant.Lock
  alias Brando.Tenant.Registry
  alias Brando.Tenant.Storage
  alias Brando.Users.User

  @default_retention_days 30
  @default_environments [
    %{name: "Production", key: "production", live: true},
    %{name: "Staging", key: "staging", live: false}
  ]

  @spec create_site(map(), User.t(), keyword()) :: {:ok, Site.t()} | {:error, term()}
  def create_site(attrs, %User{} = creator, opts \\ []) do
    case site_key(attrs) do
      key when is_binary(key) ->
        Lock.with(lifecycle_lock_key(key), fn -> create_under_lock(attrs, creator, opts) end)

      _missing_key ->
        Registry.create_site(attrs)
    end
  end

  @spec suspend_site(Site.t()) :: {:ok, Site.t()} | {:error, term()}
  def suspend_site(%Site{} = site), do: update_status(site, :suspended)

  @spec activate_site(Site.t()) :: {:ok, Site.t()} | {:error, term()}
  def activate_site(%Site{} = site), do: update_status(site, :active)

  @spec archive_site(Site.t(), keyword()) :: {:ok, Site.t()} | {:error, term()}
  def archive_site(%Site{} = site, opts \\ []) do
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
    Lock.with(lifecycle_lock_key(site.key), fn -> delete_under_lock(site, opts) end)
  end

  defp create_under_lock(attrs, creator, opts) do
    with {:ok, site} <- Registry.create_site(attrs) do
      case provision(site, creator, opts) do
        {:ok, provisioned_site} ->
          {:ok, provisioned_site}

        {:error, {:storage_not_created, reason}} ->
          compensation = compensate(site, delete_storage: false)
          {:error, {:site_setup_failed, reason, compensation}}

        {:error, reason} ->
          compensation = compensate(site)
          {:error, {:site_setup_failed, reason, compensation}}
      end
    end
  end

  defp provision(site, creator, opts) do
    environments = Keyword.get(opts, :environments, @default_environments)

    with :ok <- create_storage(site),
         :ok <- validate_environments(environments),
         [live_attrs | remaining_attrs] <- order_live_first(environments),
         {:ok, live_environment} <- Environments.create_environment(site, live_attrs, creator: creator),
         :ok <- seed(site, live_environment, creator, opts),
         {:ok, _environments} <- create_copies(site, live_environment, remaining_attrs, creator),
         {:ok, _assignment} <- Access.grant(creator, site, :admin) do
      {:ok, Registry.get_site(site.id)}
    else
      [] -> {:error, :missing_live_environment}
      {:error, _reason} = error -> error
    end
  end

  defp create_copies(site, live_environment, environment_attrs, creator) do
    Enum.reduce_while(environment_attrs, {:ok, [live_environment]}, fn attrs, {:ok, environments} ->
      with {:ok, environment} <- Environments.create_environment(site, attrs, creator: creator),
           {:ok, _copy} <-
             Environments.copy_environment(live_environment, environment,
               creator: creator,
               keep_archives: 0,
               note: "Initial site provisioning"
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

      Tenant.with_prefix(prefix, fn -> seeder.seed(site, environment, creator) end)
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
      Enum.each(site_schema_prefixes(site), &drop_schema!/1)
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

  defp compensate(site, opts \\ []) do
    Enum.each(site_schema_prefixes(site), &Schema.drop/1)

    if Keyword.get(opts, :delete_storage, true), do: Storage.delete(site)

    case Registry.get_site(site.id) do
      nil -> :ok
      current_site -> Registry.delete_site(current_site)
    end
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
  defp lifecycle_lock_key(site_key), do: "brando:site-lifecycle:#{site_key}"
end
