defmodule Mix.Tasks.Brando.MigrateToTenant do
  @shortdoc "Copies an existing public-schema installation into a new tenant site"

  @moduledoc """
  Migrates existing public content into a new site's Production schema, then
  creates Staging as a complete copy.

      mix brando.migrate_to_tenant --site-key=my-site
      mix brando.migrate_to_tenant --site-key=my-site --name="My Site" --creator-email=admin@example.com

  Global users, sessions, tenant registry rows, Oban jobs, and asset-set
  metadata remain in `public` and are never copied into the tenant schema.

  Content is copied by default, which leaves the original rows in `public` as a
  rollback window. Pass `--move` to relocate the tables instead:

      mix brando.migrate_to_tenant --site-key=my-site --move

  Moving is a catalog operation, so it does not rewrite table data and is
  therefore constant-time regardless of installation size. It leaves no legacy
  rows behind, so take a restorable backup first.

  In `:multi`, media is copied into `media/{site_key}` and the original tree is
  kept for rollback, so the copy needs as much free space again. The task
  reports the size first and asks before copying a large tree; `--yes` skips
  that question for scripted runs. `:single` keeps using the existing media
  root and copies nothing.

  ## Importing another installation's site

  In `:multi`, `--source-schema` names a schema in this installation's
  database that holds a restored copy of another installation's `public`
  schema, and `--source-media` a copy of its media tree:

      mix brando.migrate_to_tenant --site-key=acme --name="Acme" \\
        --source-schema=import_acme --source-media=/srv/import/acme-media \\
        --creator-email=admin@example.com

  Both are only read, and the task opens no connection to the other
  installation. `--creator-email` and `--source-media` are required, and
  `--move` is refused; `--source-media` without `--source-schema` is refused
  too. The task:

    1. compares the source's tenant tables with this installation's and stops,
       before creating anything, with a list of what differs. Migrate the
       copy with the other installation's application first. A table only
       this installation has is left empty and named in the report (one
       Brando derives from content, such as the search index, with the
       action that rebuilds it). It also stops, before creating anything
       and before asking anything, when the source has entries in a
       language this installation does not configure;
    2. prints how the source's users map to users here: one whose email
       matches, ignoring case, becomes that user (the first by id, when
       several match the same one), and every other one the
       `--creator-email` user. No user is created;
    3. reports the size of the media copy and, above 1 GB, asks first;
    4. creates the site suspended, so no request, editor or job reaches it,
       and copies the tenant tables (never the shared ones, users included)
       with their user references remapped, pauses the copied webhooks and
       notification routes, disables markdown sources and IndexNow, and
       marks provider videos so deleting one here leaves it at the provider
       (`Brando.Tenant.SchemaImport`);
    5. copies the media into `media/{site_key}`, computes the stored page
       breadcrumbs again, creates Staging as a copy of Production, and
       activates the site;
    6. prints what it neutralised and what to check by hand, and the
       `DROP SCHEMA` statement that removes the source schema, which it does
       not run.

  A failure removes the new site; the source schema and media are untouched.
  If removing the site fails too, the task says what may be left and prints
  the commands that remove it. The same holds without `--source-schema`,
  except after a successful `--move`: the site's Production schema then holds
  the only copy of the content, so a later failure keeps the site, and the
  task says which step failed and prints the commands that finish the rest.
  """

  use Mix.Task

  import Ecto.Query, only: [from: 2]

  alias Brando.Tenant.PublicDataMigrator
  alias Brando.Tenant.SchemaImport
  alias Brando.Users.User

  @switches [
    site_key: :string,
    name: :string,
    creator_email: :string,
    move: :boolean,
    yes: :boolean,
    source_schema: :string,
    source_media: :string
  ]

  # Below this, the copy is quick enough not to be worth interrupting for.
  @large_media_bytes 1_000_000_000

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _remaining, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [], do: Mix.raise("Invalid options: #{inspect(invalid)}")

    site_key = opts[:site_key] || Mix.raise("--site-key is required")

    cond do
      opts[:source_schema] ->
        validate_import_options!(opts)

      opts[:source_media] ->
        Mix.raise("--source-media needs --source-schema: without it the task copies this installation's own media")

      true ->
        :ok
    end

    name = opts[:name] || site_key |> String.replace("-", " ") |> String.capitalize()
    creator = creator!(opts[:creator_email])
    languages = configured_languages()
    default_language = Brando.config(:default_language) |> to_string()

    attrs = %{
      name: name,
      key: site_key,
      languages: languages,
      default_language: default_language,
      status: :active,
      delivery_mode: :dynamic
    }

    if opts[:source_schema], do: import_schema(attrs, creator, opts), else: migrate_public(attrs, creator, opts)
  end

  defp migrate_public(attrs, creator, opts) do
    confirm_media_copy!(opts)

    case Brando.Tenant.Migration.migrate_public(attrs, creator, migration_opts(opts)) do
      {:ok, site} ->
        Mix.shell().info("#{verb(opts)} public content into site #{site.key} with Production and Staging environments")

      {:error, reason} ->
        Mix.raise("Tenant migration failed: " <> failure_message(attrs.key, reason))
    end
  end

  @doc false
  # What a failed run left behind: nothing, the new site removed, or the
  # site and how to remove it
  def failure_message(site_key, {:public_migration_failed, reason, :ok}) do
    "#{inspect(reason)}\n\nThe new site #{site_key} was removed."
  end

  def failure_message(site_key, {:public_migration_failed, reason, cleanup}) do
    "#{inspect(reason)}\n\n" <> not_removed(site_key, cleanup)
  end

  def failure_message(_site_key, {:site_setup_failed, reason, :ok}) do
    "#{inspect(reason)}\n\nThe partly created site was removed: nothing the task created is left."
  end

  def failure_message(site_key, {:site_setup_failed, reason, compensation}) do
    "#{inspect(reason)}\n\n" <> not_removed(site_key, compensation)
  end

  def failure_message(site_key, {:migration_incomplete, step, reason}) do
    """
    #{incomplete_step(step)} failed: #{inspect(reason)}

    The content was moved: it now lives in the schema tenant_#{site_key}_production,
    and the tables in public are empty. The site #{site_key} was kept, so nothing
    was lost. #{incomplete_remedy(site_key, step)}
    """
  end

  def failure_message(_site_key, {:unconfigured_languages, languages}) do
    lines = Enum.map_join(languages, "\n", fn {language, tables} -> "  #{language}: #{Enum.join(tables, ", ")}" end)

    """
    the source has content in languages this installation does not configure:

    #{lines}

    Nothing was created. Add the languages to `config :brando, languages:`, or
    remove that content from the copy, then run the task again.
    """
  end

  def failure_message(_site_key, reason), do: "#{inspect(reason)}\n\nNothing was created."

  defp incomplete_step(:media), do: "Copying the media"
  defp incomplete_step(:staging), do: "Creating Staging"
  defp incomplete_step(:staging_copy), do: "Copying Production into Staging"
  defp incomplete_step(step), do: "The step #{inspect(step)}"

  defp incomplete_remedy(site_key, :media) do
    """
    To finish, fix the cause, then copy the media and
    create Staging:

        mix run -e 'site = Brando.Tenant.Registry.get_site_by_key("#{site_key}")
          :ok = Brando.Tenant.PublicMediaMigrator.migrate(site)
          #{create_staging_command()}
          #{copy_staging_command()}'
    """
  end

  defp incomplete_remedy(site_key, :staging) do
    """
    To finish, fix the cause, then create Staging as a
    copy of Production:

        mix run -e 'site = Brando.Tenant.Registry.get_site_by_key("#{site_key}")
          #{create_staging_command()}
          #{copy_staging_command()}'
    """
  end

  defp incomplete_remedy(site_key, :staging_copy) do
    """
    To finish, fix the cause, then copy Production into
    Staging:

        mix run -e 'site = Brando.Tenant.Registry.get_site_by_key("#{site_key}")
          staging = Brando.Tenant.Registry.get_environment_by_key(site, "staging")
          #{copy_staging_command()}'
    """
  end

  defp incomplete_remedy(_site_key, _step), do: "Finish the remaining steps by hand."

  defp create_staging_command do
    ~s|{:ok, staging} = Brando.Environments.create_environment(site, %{name: "Staging", key: "staging", live: false}, actor: :system, clone_structure: false)|
  end

  defp copy_staging_command do
    ~s|{:ok, _} = Brando.Environments.copy_environment(Brando.Tenant.Registry.get_environment_by_key(site, "production"), staging, actor: :system, keep_archives: 0)|
  end

  # The registry row goes before the directories, so the command also works
  # when only the directories, or only the schemas, are left
  defp not_removed(site_key, cleanup) do
    """
    The new site #{site_key} could not be removed (#{inspect(cleanup_reason(cleanup))}). What may be left:
    its row in the sites registry, the schemas tenant_#{site_key}_production and
    tenant_#{site_key}_staging, and the directories media/#{site_key} and
    sites/#{site_key}. Remove them with:

        mix run -e 'case Brando.Tenant.Registry.get_site_by_key("#{site_key}") do
            nil -> :ok
            site ->
              {:ok, site} = Brando.Tenant.Setup.archive_site(site, actor: :system)
              {:ok, _} = Brando.Tenant.Setup.delete_site(site, force: true, actor: :system)
          end
          :ok = Brando.Environments.Schema.drop("tenant_#{site_key}_production")
          :ok = Brando.Environments.Schema.drop("tenant_#{site_key}_staging")
          :ok = Brando.Tenant.Storage.delete(%Brando.Sites.Site{key: "#{site_key}"})'
    """
  end

  defp cleanup_reason({:error, reason}), do: reason
  defp cleanup_reason(other), do: other

  defp validate_import_options!(opts) do
    cond do
      Brando.Tenant.mode() != :multi ->
        Mix.raise("--source-schema needs tenancy_mode: :multi")

      opts[:move] ->
        Mix.raise("--move cannot be used with --source-schema: the source schema is only read")

      is_nil(opts[:creator_email]) ->
        Mix.raise("--creator-email is required with --source-schema")

      is_nil(opts[:source_media]) ->
        Mix.raise("--source-media is required with --source-schema")

      not File.dir?(opts[:source_media]) ->
        Mix.raise("--source-media=#{opts[:source_media]} is not a directory")

      true ->
        :ok
    end
  end

  defp import_schema(attrs, creator, opts) do
    source = opts[:source_schema]
    check_source!(source, attrs)

    mapping =
      case SchemaImport.user_mapping(source, creator) do
        {:ok, mapping} -> mapping
        {:error, reason} -> Mix.raise("Could not read the users of #{source}: #{inspect(reason)}")
      end

    print_mapping(source, mapping)
    confirm_media_copy!(opts, opts[:source_media])

    import_opts = [source_schema: source, source_media: opts[:source_media], user_mapping: mapping]

    case Brando.Tenant.Migration.import_schema(attrs, creator, import_opts) do
      {:ok, site, report} ->
        Mix.shell().info("Imported #{source} into site #{site.key} with Production and Staging environments")
        print_report(report)

        Mix.shell().info("""

        The source schema is no longer needed once the site is verified. To remove it, run:

            DROP SCHEMA "#{source}" CASCADE;
        """)

      {:error, reason} ->
        Mix.raise("Import failed: " <> failure_message(attrs.key, reason))
    end
  end

  defp check_source!(source, attrs) do
    with :ok <- SchemaImport.validate_source(source),
         :ok <- SchemaImport.compare(source),
         :ok <- Brando.Tenant.Migration.check_languages(source, attrs) do
      :ok
    else
      {:error, {:unconfigured_languages, _languages} = reason} ->
        Mix.raise("Cannot import from #{source}: " <> failure_message(attrs.key, reason))

      {:error, {:source_structure_differs, differences}} ->
        Mix.raise("""
        The tenant tables of #{source} do not match this installation's:

        #{SchemaImport.format_differences(differences)}

        Nothing was created. Migrate the copy first: run the source application's
        migrations, at a version that matches this installation, against the scratch
        database the copy came from, then restore it here again.
        """)

      {:error, reason} ->
        Mix.raise("Cannot import from #{source}: #{inspect(reason)}")
    end
  end

  defp print_mapping(source, mapping) do
    lines =
      Enum.map_join(mapping, "\n", fn entry ->
        how =
          cond do
            entry.matched -> "same email"
            entry[:duplicate_of] -> "same email as source user #{entry.duplicate_of}, which takes it; creator"
            true -> "no match, creator"
          end

        "  #{entry.source_id} #{entry.source_email} -> #{entry.target_id} #{entry.target_email} (#{how})"
      end)

    Mix.shell().info("""

    Users of #{source}, and the user here each one becomes:

    #{if lines == "", do: "  (none)", else: lines}
    """)
  end

  @report_lines %{
    webhooks_paused: "webhooks paused: resume each after checking its URL, and rotate its secret",
    notification_routes_paused: "notification routes paused: check the channel and recipients, then resume",
    markdown_sources_disabled: "markdown sources disabled: check the connection, then enable",
    index_now_disabled: "IndexNow disabled: enable it once the site serves its own host",
    provider_videos_kept_at_provider:
      "provider videos marked imported: deleting one here leaves it at the provider, where the source plays it",
    scheduled_revisions: "scheduled revisions: their jobs stayed with the source, so schedule them again",
    scheduled_dates:
      "entries with a future publish or unpublish date: the scheduled publishing sweep carries them out, in both environments",
    forms_with_recipients: "forms that email recipients on a submission: check the addresses",
    cdn_images: "images on a CDN: their files stay in the source's bucket and were not copied",
    cdn_files: "files on a CDN: their files stay in the source's bucket and were not copied",
    undecoded_snapshots:
      "revisions or pending translations whose user ids could not be remapped (they cannot be decoded here)",
    tables_not_in_source: "tables the source does not have, left empty",
    derived_tables_not_in_source:
      "tables Brando derives from content, which the source does not have: rebuild each with the Configuration → Utilities action named, in Production and in Staging"
  }

  defp print_report(report) do
    {neutralised, to_check} = Enum.split_with(report, &(&1.action == :neutralised))

    Mix.shell().info("""

    Neutralised in the copy:
    #{report_lines(Enum.filter(neutralised, &(&1.count > 0)))}

    To check by hand:
    #{report_lines(to_check)}
      deploy targets are not copied: the site delivers dynamically until one is configured
    """)
  end

  defp report_lines([]), do: "  (nothing)"
  defp report_lines(items), do: Enum.map_join(items, "\n", &report_line/1)

  defp report_line(%{key: :derived_tables_not_in_source, names: names} = item) do
    actions = SchemaImport.derived_tables()
    named = Enum.map_join(names, ", ", &"#{&1} (#{Map.fetch!(actions, &1)})")
    "  #{item.count} #{Map.fetch!(@report_lines, item.key)}: #{named}"
  end

  defp report_line(%{names: [_ | _] = names} = item),
    do: "  #{item.count} #{Map.fetch!(@report_lines, item.key)}: #{Enum.join(names, ", ")}"

  defp report_line(item), do: "  #{item.count} #{Map.fetch!(@report_lines, item.key)}"

  # Only `:multi` copies media; `:single` keeps using the existing media root,
  # so there is nothing to duplicate and nothing to warn about.
  defp confirm_media_copy!(opts, media_path \\ Brando.config(:media_path)) do
    if Brando.Tenant.mode() == :multi do
      bytes = directory_size(media_path)

      Mix.shell().info("""

      Media at #{media_path} is #{format_bytes(bytes)}.
      It will be COPIED into media/#{opts[:site_key]}, so that much free disk
      space is needed. The original tree is left untouched for rollback.
      """)

      if bytes >= @large_media_bytes, do: confirm_large_media!(opts)
    end
  end

  defp confirm_large_media!(opts) do
    if !Mix.Brando.confirm?("Continue and copy this media tree?", yes: opts[:yes]) do
      Mix.raise("Aborted before copying media")
    end
  end

  @doc """
  Returns the total size in bytes of the files under `path`, or 0 when it
  does not exist. Public so the size reporting can be tested without running
  a migration.
  """
  def directory_size(path) do
    case File.stat(path) do
      {:ok, %{type: :directory}} ->
        path
        |> File.ls!()
        |> Enum.reduce(0, &(directory_size(Path.join(path, &1)) + &2))

      {:ok, %{size: size}} ->
        size

      {:error, _reason} ->
        0
    end
  end

  @doc "Formats a byte count for the media size report, such as `\"5.7 GB\"`."
  def format_bytes(bytes) when bytes >= 1_000_000_000,
    do: "#{Float.round(bytes / 1_000_000_000, 1)} GB"

  def format_bytes(bytes) when bytes >= 1_000_000,
    do: "#{Float.round(bytes / 1_000_000, 1)} MB"

  def format_bytes(bytes), do: "#{bytes} B"

  defp migration_opts(opts) do
    if opts[:move], do: [public_data_migrator: PublicDataMigrator.Move], else: []
  end

  defp verb(opts), do: if(opts[:move], do: "Moved", else: "Copied")

  defp creator!(nil) do
    from(user in User,
      where: user.role == :superuser and user.active,
      order_by: [asc: user.id],
      limit: 1
    )
    |> Brando.Repo.one(prefix: "public")
    |> case do
      %User{} = user -> user
      nil -> Mix.raise("No active superuser exists; pass --creator-email")
    end
  end

  defp creator!(email) do
    from(user in User, where: user.email == ^email and user.active)
    |> Brando.Repo.one(prefix: "public")
    |> case do
      %User{} = user -> user
      nil -> Mix.raise("No active user found for --creator-email=#{email}")
    end
  end

  defp configured_languages do
    Brando.config(:languages)
    |> List.wrap()
    |> Enum.map(fn
      options when is_list(options) -> options[:value]
      %{value: value} -> value
      language -> language
    end)
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
    |> case do
      [] -> [Brando.config(:default_language) |> to_string()]
      languages -> languages
    end
  end
end
