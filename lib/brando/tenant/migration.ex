defmodule Brando.Tenant.Migration do
  @moduledoc """
  Migrates an existing installation into a new site: this installation's
  `public` schema (`migrate_public/3`), or a restored copy of another
  installation's (`import_schema/3`).
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Environments
  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Tenant.PublicMediaMigrator
  alias Brando.Tenant.Registry
  alias Brando.Tenant.SchemaImport
  alias Brando.Tenant.Setup
  alias Brando.Users.User

  @production %{name: "Production", key: "production", live: true}
  @staging %{name: "Staging", key: "staging", live: false}

  @spec migrate_public(map(), User.t(), keyword()) :: {:ok, Site.t()} | {:error, term()}
  def migrate_public(attrs, %User{} = creator, opts \\ []) do
    migrator = Keyword.get(opts, :public_data_migrator, configured_migrator())
    media_migrator = Keyword.get(opts, :public_media_migrator, configured_media_migrator())

    copy = fn site, prefix ->
      with :ok <- migrator.migrate("public", prefix),
           :ok <- media_migrator.migrate(site) do
        {:ok, nil}
      end
    end

    with {:ok, site, _result} <- migrate(attrs, creator, copy, "Initial public-schema migration") do
      {:ok, site}
    end
  end

  @doc """
  Creates a site from `source_schema`, a schema in this database holding a
  restored copy of another installation's `public` schema, and
  `source_media`, a copy of its media tree. Both are only read.

  The source is checked before the site is created (`SchemaImport.compare/1`).
  Its rows are copied into Production with their user references remapped
  by `:user_mapping` (`SchemaImport.user_mapping/2`, computed when not given),
  its media into `media/{site_key}`, and the stored page breadcrumbs are
  computed again for this installation before Staging is created as a copy.
  A failure removes the new site.

  Returns `{:ok, site, report}`, the report being `SchemaImport.copy/4`'s.
  """
  @spec import_schema(map(), User.t(), keyword()) :: {:ok, Site.t(), SchemaImport.report()} | {:error, term()}
  def import_schema(attrs, %User{} = creator, opts) do
    source = Keyword.fetch!(opts, :source_schema)
    source_media = Keyword.fetch!(opts, :source_media)

    with :ok <- SchemaImport.validate_source(source),
         :ok <- SchemaImport.compare(source),
         {:ok, mapping} <- mapping(opts, source, creator) do
      copy = &import_into(&1, &2, source, source_media, mapping, creator)
      migrate(attrs, creator, copy, "Initial import from schema #{source}")
    end
  end

  defp import_into(site, prefix, source, source_media, mapping, creator) do
    with {:ok, report} <- SchemaImport.copy(source, prefix, mapping, creator.id),
         :ok <- PublicMediaMigrator.copy_tree(site, source_media),
         :ok <- update_breadcrumbs(prefix) do
      {:ok, report}
    end
  end

  defp mapping(opts, source, creator) do
    case Keyword.fetch(opts, :user_mapping) do
      {:ok, mapping} -> {:ok, mapping}
      :error -> SchemaImport.user_mapping(source, creator)
    end
  end

  # The home entry of a stored trail is the installation's `app_name` on a
  # standalone installation and the identity's name here (`Brando.Sites.site_name/1`)
  defp update_breadcrumbs(prefix) do
    Tenant.with_prefix(prefix, fn ->
      Brando.Cache.Identity.set()

      from(p in Brando.Pages.Page, distinct: true, select: p.language)
      |> Brando.Repo.all()
      |> Enum.each(&Brando.Pages.update_breadcrumbs_for_language/1)
    end)
  end

  defp migrate(attrs, creator, copy, note) do
    setup_opts = [environments: [@production], seed: false]

    with {:ok, site} <- Setup.create_site(attrs, creator, setup_opts) do
      case copy_and_create_staging(site, creator, copy, note) do
        {:ok, migrated_site, result} ->
          {:ok, migrated_site, result}

        {:error, reason} ->
          cleanup = cleanup_failed_site(site)
          {:error, {:public_migration_failed, reason, cleanup}}
      end
    end
  end

  defp copy_and_create_staging(site, creator, copy, note) do
    production = Registry.get_environment_by_key(site, "production")
    prefix = Tenant.prefix(site, production)

    with {:ok, result} <- copy.(site, prefix),
         {:ok, staging} <-
           Environments.create_environment(site, @staging, creator: creator, clone_structure: false),
         {:ok, _copy} <-
           Environments.copy_environment(production, staging,
             creator: creator,
             keep_archives: 0,
             note: note
           ) do
      {:ok, Registry.get_site(site.id), result}
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
