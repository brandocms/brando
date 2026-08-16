defmodule Brando.Environments do
  @moduledoc """
  Lifecycle API for named, schema-backed content environments.

  Registry rows always live in `public`; each environment's content lives in
  `tenant_{site_key}_{environment_key}`. Creation compensates for migration
  failures by removing both the new schema and registry row. Destructive copy,
  archives, rollback, and scheduling are layered on this foundation.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Environments.Environment
  alias Brando.Environments.Schema
  alias Brando.Repo
  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry

  @public_opts [prefix: "public"]

  @doc """
  Creates the public environment record, its PostgreSQL schema, and applies all
  tenant migrations. A failed schema creation or migration is compensated.
  """
  @spec create_environment(Site.t(), map()) ::
          {:ok, Environment.t()} | {:error, Ecto.Changeset.t() | term()}
  def create_environment(%Site{} = site, attrs) do
    with {:ok, environment} <- Registry.create_environment(site, attrs),
         prefix = Tenant.prefix(site, environment),
         :ok <- create_schema_or_compensate(environment, prefix),
         {:ok, _versions} <- migrate_or_compensate(site, environment, prefix) do
      {:ok, environment}
    end
  end

  @doc "Runs tenant migrations on one environment schema."
  @spec migrate(Environment.t()) :: {:ok, [integer()]} | {:error, term()}
  def migrate(%Environment{} = environment) do
    with %Site{} = site <- Registry.get_site(environment.site_id) do
      migrator().migrate(site, environment)
    else
      nil -> {:error, :site_not_found}
    end
  end

  @doc "Runs tenant migrations on every registered environment schema."
  @spec migrate_all() :: {:ok, [{Environment.t(), [integer()]}]} | {:error, term()}
  def migrate_all do
    Registry.list_sites()
    |> Enum.flat_map(& &1.environments)
    |> Enum.sort_by(& &1.id)
    |> migrate_environments()
  end

  @doc "Runs tenant migrations on every environment belonging to one site."
  @spec migrate_site(Site.t()) :: {:ok, [{Environment.t(), [integer()]}]} | {:error, term()}
  def migrate_site(%Site{} = site) do
    site
    |> Registry.list_environments()
    |> Enum.sort_by(& &1.id)
    |> migrate_environments()
  end

  @doc "Deletes a non-live environment and its content schema."
  @spec delete_environment(Environment.t()) :: {:ok, Environment.t()} | {:error, term()}
  def delete_environment(%Environment{} = environment) do
    with %Environment{live: false} = current_environment <-
           Registry.get_environment(environment.id),
         %Site{} = site <- Registry.get_site(current_environment.site_id),
         prefix = Tenant.prefix(site, current_environment),
         :ok <- Schema.drop(prefix),
         {:ok, deleted_environment} <- Registry.delete_environment(current_environment) do
      {:ok, deleted_environment}
    else
      %Environment{live: true} -> {:error, :live_environment}
      nil -> {:error, :site_or_environment_not_found}
      {:error, _reason} = error -> error
    end
  end

  @doc "Atomically marks one environment as the sole live environment for its site."
  @spec set_live(Environment.t()) :: {:ok, Environment.t()} | {:error, term()}
  def set_live(%Environment{} = environment) do
    case Registry.get_environment(environment.id) do
      %Environment{} = current_environment ->
        set_current_environment_live(current_environment)

      nil ->
        {:error, :environment_not_found}
    end
  end

  defp set_current_environment_live(environment) do
    result =
      Repo.transaction(fn ->
        from(candidate in Environment, where: candidate.site_id == ^environment.site_id)
        |> Repo.update_all([set: [live: false]], @public_opts)

        environment
        |> Environment.changeset(%{live: true})
        |> Repo.update(@public_opts)
        |> case do
          {:ok, live_environment} -> live_environment
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, live_environment} ->
        Cache.invalidate()
        {:ok, live_environment}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_schema_or_compensate(environment, prefix) do
    case Schema.create(prefix) do
      :ok ->
        :ok

      {:error, reason} ->
        Registry.delete_environment(environment)
        {:error, {:schema_creation_failed, reason}}
    end
  end

  defp migrate_or_compensate(site, environment, prefix) do
    case migrator().migrate(site, environment) do
      {:ok, versions} ->
        {:ok, versions}

      {:error, reason} ->
        Schema.drop(prefix)
        Registry.delete_environment(environment)
        {:error, {:migration_failed, reason}}
    end
  end

  defp migrate_environments(environments) do
    Enum.reduce_while(environments, {:ok, []}, fn environment, {:ok, migrated} ->
      case migrate(environment) do
        {:ok, versions} -> {:cont, {:ok, [{environment, versions} | migrated]}}
        {:error, reason} -> {:halt, {:error, {environment, reason}}}
      end
    end)
    |> case do
      {:ok, migrated} -> {:ok, Enum.reverse(migrated)}
      error -> error
    end
  end

  defp migrator do
    Brando.config(:tenant_migrator) || Brando.Environments.Migrator
  end
end
