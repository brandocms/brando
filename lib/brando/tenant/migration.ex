defmodule Brando.Tenant.Migration do
  @moduledoc """
  Migrates an existing installation into a new site: this installation's
  `public` schema (`migrate_public/3`), or a restored copy of another
  installation's (`import_schema/3`).
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Environments
  alias Brando.Environments.StructureCloner.Postgres, as: StructureCloner
  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Tenant.PublicMediaMigrator
  alias Brando.Tenant.Registry
  alias Brando.Tenant.SchemaImport
  alias Brando.Tenant.Setup
  alias Brando.Users.User
  alias Ecto.Adapters.SQL

  @production %{name: "Production", key: "production", live: true}
  @staging %{name: "Staging", key: "staging", live: false}

  @doc """
  Creates a site from this installation's `public` content: the data
  migrator copies (or moves) it into Production, the media migrator copies
  the media into the site's root, and Staging is created as a copy.

  A failure removes the new site, except once a migrator that relocates the
  content (`c:Brando.Tenant.PublicDataMigrator.relocates?/0`) has returned:
  the site's Production schema then holds the only copy, so a later failure
  keeps the site and returns `{:error, {:migration_incomplete, step,
  reason}}`, `step` being `:media`, `:staging` or `:staging_copy`. So does
  such a migrator's own error when the schema holds rows all the same
  (`step` is then `:move`): a move commits at once, and the answer to its
  commit can be lost.
  """
  @spec migrate_public(map(), User.t(), keyword()) :: {:ok, Site.t()} | {:error, term()}
  def migrate_public(attrs, %User{} = creator, opts \\ []) do
    migrator = Keyword.get(opts, :public_data_migrator, configured_migrator())
    media_migrator = Keyword.get(opts, :public_media_migrator, configured_media_migrator())

    copy = fn _site, prefix ->
      with :ok <- migrator.migrate("public", prefix), do: {:ok, nil}
    end

    migrate_opts = [after_copy: &media_migrator.migrate/1, relocates: relocates?(migrator)]

    with {:ok, site, _result} <- migrate(attrs, creator, copy, "Initial public-schema migration", migrate_opts) do
      {:ok, site}
    end
  end

  defp relocates?(migrator) do
    Code.ensure_loaded?(migrator) and function_exported?(migrator, :relocates?, 0) and migrator.relocates?()
  end

  @doc """
  Creates a site from `source_schema`, a schema in this database holding a
  restored copy of another installation's `public` schema, and
  `source_media`, a copy of its media tree. Both are only read.

  The source is checked before the site is created: its structure
  (`SchemaImport.compare/1`), and that its content is in languages the site
  has (`{:error, {:unconfigured_languages, [{language, tables}]}}`
  otherwise, since Brando cannot load the rows of another language). The
  site is created suspended, with an empty Production, so no worker,
  request, admin or sweep of active sites acts on what is copied. Its rows are copied into
  Production with their user references remapped by `:user_mapping`
  (`SchemaImport.user_mapping/2`, computed when not given), its media into
  `media/{site_key}`, and the stored page breadcrumbs are computed again for
  this installation before Staging is created as a copy. The site takes the
  status in `attrs` (`:active` when not given) as the last step. A failure,
  raised or returned, removes the new site.

  Returns `{:ok, site, report}`, the report being `SchemaImport.copy/4`'s.
  """
  @spec import_schema(map(), User.t(), keyword()) :: {:ok, Site.t(), SchemaImport.report()} | {:error, term()}
  def import_schema(attrs, %User{} = creator, opts) do
    attrs = normalise_attrs(attrs)
    source = Keyword.fetch!(opts, :source_schema)
    source_media = Keyword.fetch!(opts, :source_media)

    with :ok <- SchemaImport.validate_source(source),
         :ok <- SchemaImport.compare(source),
         :ok <- check_languages(source, attrs),
         {:ok, mapping} <- mapping(opts, source, creator) do
      copy = &import_into(&1, &2, source, source_media, mapping, creator)
      migrate(attrs, creator, copy, "Initial import from schema #{source}", hold: true)
    end
  end

  # Atom keys, as `Site.changeset/2` casts them, and the status an atom.
  # A string key that is not a site field is dropped, as the cast would.
  defp normalise_attrs(attrs) do
    fields = Map.new(Site.__schema__(:fields), &{to_string(&1), &1})

    attrs
    |> Enum.flat_map(fn
      {key, value} when is_binary(key) -> if field = fields[key], do: [{field, value}], else: []
      pair -> [pair]
    end)
    |> Map.new()
    |> Map.update(:status, :active, fn status ->
      Enum.find(Site.statuses(), status, &(to_string(&1) == to_string(status)))
    end)
  end

  @doc """
  Checks that the source's entries are in languages `attrs` configures for
  the site: `{:error, {:unconfigured_languages, [{language, tables}]}}`
  otherwise (`SchemaImport.content_languages/1`). Only reads the source.
  """
  @spec check_languages(String.t(), map()) :: :ok | {:error, term()}
  def check_languages(source, attrs) do
    languages = attrs |> normalise_attrs() |> Map.get(:languages, []) |> Enum.map(&to_string/1)

    with {:ok, found} <- SchemaImport.content_languages(source) do
      found
      |> Enum.reject(fn {language, _tables} -> language in languages end)
      |> unconfigured_languages()
    end
  end

  defp unconfigured_languages([]), do: :ok
  defp unconfigured_languages(unconfigured), do: {:error, {:unconfigured_languages, unconfigured}}

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

  # With `hold: true` the site is inserted suspended, so it is never active
  # (nor listed by a sweep of active sites) before it is given its status
  # last. A suspended site admits no one, so its environments are created as
  # the system, the creator having been authorized to create the site.
  # `:after_copy` runs on the site once the copy has returned; with
  # `relocates: true` the copy is the only one, and a failure after it keeps
  # the site.
  defp migrate(attrs, creator, copy, note, opts) do
    setup_opts = [environments: [@production], seed: false]
    site_attrs = if opts[:hold], do: Map.put(attrs, :status, :suspended), else: attrs

    with {:ok, site} <- Setup.create_site(site_attrs, creator, setup_opts) do
      production = Registry.get_environment_by_key(site, "production")

      fn -> copy.(site, Tenant.prefix(site, production)) end
      |> compensated()
      |> after_copy(site, production, attrs, creator, note, opts)
    end
  end

  defp after_copy({:ok, result}, site, production, attrs, creator, note, opts),
    do: finish(site, production, attrs, creator, note, result, opts)

  defp after_copy({:error, reason}, site, production, _attrs, _creator, _note, opts) do
    if Keyword.get(opts, :relocates, false) and holds_content?(Tenant.prefix(site, production)),
      do: {:error, {:migration_incomplete, :move, reason}},
      else: clean_up(site, reason)
  end

  # Provisioning leaves the schema's tables empty, so a row in one arrived
  # with the move. Anything but a clear "no rows" counts as content: the
  # schema is dropped next.
  defp holds_content?(prefix) do
    case StructureCloner.tenant_tables(prefix) do
      {:ok, []} ->
        false

      {:ok, tables} ->
        checks = Enum.map_join(tables, " OR ", &~s|EXISTS (SELECT 1 FROM "#{prefix}"."#{&1}")|)
        not match?({:ok, %{rows: [[false]]}}, SQL.query(Brando.Repo.repo(), "SELECT " <> checks, []))

      {:error, _reason} ->
        true
    end
  end

  defp finish(site, production, attrs, creator, note, result, opts) do
    hold? = Keyword.get(opts, :hold, false)
    after_copy = Keyword.get(opts, :after_copy, fn _site -> :ok end)
    actor = if hold?, do: [actor: :system, creator_id: creator.id], else: [creator: creator]

    with :ok <- step(:media, fn -> after_copy.(site) end),
         {:ok, staging} <-
           step(:staging, fn -> Environments.create_environment(site, @staging, [clone_structure: false] ++ actor) end),
         {:ok, _copy} <-
           step(:staging_copy, fn ->
             Environments.copy_environment(production, staging, [keep_archives: 0, note: note] ++ actor)
           end),
         {:ok, _site} <- step(:activation, fn -> release(site, attrs, hold?) end) do
      {:ok, Registry.get_site(site.id), result}
    else
      {:error, step, reason} ->
        if Keyword.get(opts, :relocates, false),
          do: {:error, {:migration_incomplete, step, reason}},
          else: clean_up(site, reason)
    end
  end

  defp step(name, fun) do
    case compensated(fun) do
      {:error, reason} -> {:error, name, reason}
      result -> result
    end
  end

  defp clean_up(site, reason) do
    cleanup = compensated(fn -> cleanup_failed_site(site) end)
    {:error, {:public_migration_failed, reason, cleanup}}
  end

  defp compensated(fun) do
    fun.()
  rescue
    exception -> {:error, {:raised, Exception.message(exception)}}
  catch
    kind, reason -> {:error, {:raised, Exception.format_banner(kind, reason)}}
  end

  defp release(site, attrs, true) do
    if attrs.status == :active, do: Setup.activate_site(site, actor: :system), else: {:ok, site}
  end

  defp release(site, _attrs, false), do: {:ok, site}

  # Undoes this call's own site: the creator was authorized to create it, and
  # may not be to delete sites, so the removal runs as the system
  defp cleanup_failed_site(site) do
    with {:ok, archived} <- Setup.archive_site(site, actor: :system),
         {:ok, _deleted} <- Setup.delete_site(archived, force: true, actor: :system) do
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
