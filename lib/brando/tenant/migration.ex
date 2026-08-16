defmodule Brando.Tenant.Migration do
  @moduledoc "Migrates an existing public-schema installation into a new site."

  alias Brando.Environments
  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Tenant.Registry
  alias Brando.Tenant.Setup
  alias Brando.Users.User

  @production %{name: "Production", key: "production", live: true}
  @staging %{name: "Staging", key: "staging", live: false}

  @spec migrate_public(map(), User.t(), keyword()) :: {:ok, Site.t()} | {:error, term()}
  def migrate_public(attrs, %User{} = creator, opts \\ []) do
    setup_opts = [environments: [@production], seed: false]

    with {:ok, site} <- Setup.create_site(attrs, creator, setup_opts) do
      case migrate_and_create_staging(site, creator, opts) do
        {:ok, migrated_site} ->
          {:ok, migrated_site}

        {:error, reason} ->
          cleanup = cleanup_failed_site(site)
          {:error, {:public_migration_failed, reason, cleanup}}
      end
    end
  end

  defp migrate_and_create_staging(site, creator, opts) do
    production = Registry.get_environment_by_key(site, "production")
    prefix = Tenant.prefix(site, production)
    migrator = Keyword.get(opts, :public_data_migrator, configured_migrator())
    media_migrator = Keyword.get(opts, :public_media_migrator, configured_media_migrator())

    with :ok <- migrator.migrate("public", prefix),
         :ok <- media_migrator.migrate(site),
         {:ok, staging} <- Environments.create_environment(site, @staging, creator: creator),
         {:ok, _copy} <-
           Environments.copy_environment(production, staging,
             creator: creator,
             keep_archives: 0,
             note: "Initial public-schema migration"
           ) do
      {:ok, Registry.get_site(site.id)}
    end
  end

  defp cleanup_failed_site(site) do
    with {:ok, archived} <- Setup.archive_site(site),
         {:ok, _deleted} <- Setup.delete_site(archived, force: true) do
      :ok
    end
  end

  defp configured_migrator do
    Brando.config(:tenant_public_data_migrator) || Brando.Tenant.PublicDataMigrator
  end

  defp configured_media_migrator do
    Brando.config(:tenant_public_media_migrator) || Brando.Tenant.PublicMediaMigrator
  end
end
