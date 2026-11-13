defmodule Brando.TenantSchemaImportIntegrationTest do
  # pg_dump and psql connect on their own and cannot see a sandbox
  # transaction, so this file commits through its own repo and removes what
  # it made.
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Environments.SchemaCloner.Postgres, as: SchemaCloner
  alias Brando.Environments.StructureCloner.Postgres, as: StructureCloner
  alias Brando.IntegrationRepo
  alias Brando.Tenant.Migration
  alias Brando.Tenant.Registry
  alias Brando.Tenant.SchemaImport
  alias Brando.Tenant.Setup
  alias Ecto.Adapters.SQL

  defmodule Repo do
    use Ecto.Repo,
      otp_app: :brando,
      adapter: Ecto.Adapters.Postgres
  end

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  setup_all do
    IntegrationRepo.start(Repo)
  end

  setup do
    unique = System.unique_integer([:positive])
    root = Path.join(System.tmp_dir!(), "brando-schema-import-#{unique}")
    source = "import_acme#{unique}"
    site_key = "acme#{unique}"

    put_test_env(:repo_module, Repo)
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:sites_path, Path.join(root, "sites"))
    Brando.Tenant.Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Brando.Tenant.put_prefix(nil)
      Brando.Tenant.Cache.clear()
    end)

    creator = insert_user!("creator-#{unique}@example.com", "superuser")
    local = insert_user!("editor-#{unique}@example.com", "editor")

    on_exit(fn ->
      with_repo(fn ->
        remove_site(site_key)
        query!(~s|DROP SCHEMA IF EXISTS "#{source}" CASCADE|)
        query!("DELETE FROM public.users WHERE id = ANY($1)", [[creator.id, local.id]])
      end)
    end)

    source_media = Path.join(root, "acme-media")
    File.mkdir_p!(Path.join(source_media, "images/site"))
    File.write!(Path.join(source_media, "images/site/logo.png"), "logo bytes")
    File.write!(Path.join(source_media, "robots.txt"), "user-agent: *")

    build_source!(source, unique)

    %{
      creator: creator,
      local: local,
      source: source,
      site_key: site_key,
      source_media: source_media,
      unique: unique
    }
  end

  describe "a successful import" do
    test "copies the content with its users remapped and leaves the source as it was", context do
      before_schema = source_snapshot(context.source)
      before_media = media_snapshot(context.source_media)

      assert {:ok, mapping} = SchemaImport.user_mapping(context.source, context.creator)

      assert [
               %{source_id: 1, target_id: local_id, matched: true},
               %{source_id: 2, target_id: creator_id, matched: false}
             ] = mapping

      assert local_id == context.local.id
      assert creator_id == context.creator.id

      assert {:ok, site, report} =
               Migration.import_schema(site_attrs(context.site_key), context.creator,
                 source_schema: context.source,
                 source_media: context.source_media
               )

      production = "tenant_#{site.key}_production"
      staging = "tenant_#{site.key}_staging"

      # Users: the match by email, the rest the creator; a listing view of a
      # user who is not here is gone
      assert %{rows: [[^local_id, ^creator_id], [^creator_id, ^local_id]]} =
               query!(~s|SELECT creator_id, updated_by_id FROM "#{production}".pages ORDER BY id|)

      assert %{rows: [[^local_id]]} = query!(~s|SELECT creator_id FROM "#{production}".listing_views|)
      assert %{rows: [[^creator_id]]} = query!(~s|SELECT actor_id FROM "#{production}".content_markdown_events|)
      assert %{rows: [[[^local_id]]]} = query!(~s|SELECT recipient_ids FROM "#{production}".notification_routes|)

      assert %{
               rows: [
                 [^creator_id, %{"content_blocks" => [%{"creator_id" => ^local_id, "updated_by_id" => ^creator_id}]}]
               ]
             } =
               query!(~s|SELECT removed_by_id, data FROM "#{production}".content_block_archive|)

      # The revision restores no source user id
      %{rows: [[encoded]]} = query!(~s|SELECT encoded_entry FROM "#{production}".revisions|)
      snapshot = Brando.Utils.binary_to_term(encoded)
      assert snapshot.creator_id == creator_id
      assert snapshot.updated_by_id == local_id

      # Breadcrumbs carry the identity's name in both environments
      for prefix <- [production, staging] do
        %{rows: [[breadcrumbs]]} =
          query!(~s|SELECT breadcrumbs FROM "#{prefix}".pages WHERE is_homepage = false|)

        assert [%{"title" => "Acme Identity", "uri" => "/"} | _] = breadcrumbs
      end

      # Sequences continue after the copied ids
      %{rows: [[next_id]]} =
        query!(
          ~s|INSERT INTO "#{production}".pages (language, inserted_at, updated_at) VALUES ('en', now(), now()) RETURNING id|
        )

      assert next_id > 11

      # What could act on the outside world is inert
      assert %{rows: [[false, "manual"]]} = query!(~s|SELECT active, paused_reason FROM "#{production}".webhooks|)

      assert %{rows: [[false, "manual"]]} =
               query!(~s|SELECT active, paused_reason FROM "#{production}".notification_routes|)

      assert %{rows: [[false]]} = query!(~s|SELECT enabled FROM "#{production}".content_markdown_sources|)
      assert %{rows: [[%{"imported" => true}]]} = query!(~s|SELECT meta FROM "#{production}".videos|)

      assert %{key: :webhooks_paused, count: 1, action: :neutralised} in report
      assert %{key: :scheduled_revisions, count: 1, action: :check} in report
      assert %{key: :scheduled_dates, count: 1, action: :check} in report

      # Users stay this installation's
      assert %{rows: [[false]]} =
               query!("SELECT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = $1 AND tablename = 'users')", [
                 production
               ])

      assert File.read!(Path.join([Brando.config(:media_path), site.key, "images/site/logo.png"])) == "logo bytes"

      assert source_snapshot(context.source) == before_schema
      assert media_snapshot(context.source_media) == before_media
    end
  end

  test "the task prints the user mapping before writing, the report, and the DROP SCHEMA it leaves to the operator",
       context do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    Mix.Task.reenable("brando.migrate_to_tenant")

    Mix.Tasks.Brando.MigrateToTenant.run([
      "--site-key=#{context.site_key}",
      "--name=Acme",
      "--source-schema=#{context.source}",
      "--source-media=#{context.source_media}",
      "--creator-email=#{context.creator.email}"
    ])

    output = collect_output()
    mapping_at = :binary.match(output, "and the user here each one becomes") |> elem(0)
    imported_at = :binary.match(output, "Imported #{context.source} into site #{context.site_key}") |> elem(0)

    assert mapping_at < imported_at
    assert output =~ "1 EDITOR-#{context.unique}@Example.com -> #{context.local.id} #{context.local.email} (same email)"
    assert output =~ "2 gone@elsewhere.example -> #{context.creator.id} #{context.creator.email} (no match, creator)"
    assert output =~ "1 webhooks paused"
    assert output =~ ~s|DROP SCHEMA "#{context.source}" CASCADE;|
    assert %{rows: [[true]]} = query!("SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = $1)", [context.source])
  end

  defp collect_output(acc \\ "") do
    receive do
      {:mix_shell, :info, [line]} -> collect_output(acc <> line <> "\n")
    after
      0 -> acc
    end
  end

  describe "a failed import" do
    test "stops before creating anything when the source lacks a column", context do
      query!(~s|ALTER TABLE "#{context.source}".pages DROP COLUMN meta_description|)
      before_schema = source_snapshot(context.source)

      assert {:error, {:source_structure_differs, differences}} =
               Migration.import_schema(site_attrs(context.site_key), context.creator,
                 source_schema: context.source,
                 source_media: context.source_media
               )

      assert {:missing_column, "pages", "meta_description"} in differences
      assert SchemaImport.format_differences(differences) =~ "pages.meta_description: missing in the source"
      refute Registry.get_site_by_key(context.site_key)
      assert source_snapshot(context.source) == before_schema
    end

    test "removes the new site and leaves the source as it was", context do
      outside = Path.join(Path.dirname(context.source_media), "outside.txt")
      File.write!(outside, "not media")
      File.ln_s!(outside, Path.join(context.source_media, "escape"))
      before_schema = source_snapshot(context.source)
      before_media = media_snapshot(context.source_media)

      assert {:error, {:public_migration_failed, {:media_migration_failed, {:unsupported_media_file, _}}, :ok}} =
               Migration.import_schema(site_attrs(context.site_key), context.creator,
                 source_schema: context.source,
                 source_media: context.source_media
               )

      refute Registry.get_site_by_key(context.site_key)
      refute File.exists?(Path.join(Brando.config(:media_path), context.site_key))

      assert %{rows: []} =
               query!("SELECT nspname FROM pg_namespace WHERE nspname LIKE $1", ["tenant_#{context.site_key}_%"])

      assert source_snapshot(context.source) == before_schema
      assert media_snapshot(context.source_media) == before_media
    end
  end

  test "refuses a source that is not a restored copy", context do
    assert {:error, {:reserved_source_schema, "public"}} = SchemaImport.validate_source("public")
    assert {:error, {:reserved_source_schema, _}} = SchemaImport.validate_source("tenant_acme_production")
    assert {:error, {:invalid_source_schema, _}} = SchemaImport.validate_source(~s|bad"name|)
    assert {:error, {:source_schema_not_found, _}} = SchemaImport.validate_source("#{context.source}_missing")
  end

  # A copy of another installation's `public`: the tenant tables as they are
  # here, its own `users` table, and rows that point at its users.
  defp build_source!(source, unique) do
    query!(~s|CREATE SCHEMA "#{source}"|)
    :ok = StructureCloner.clone_structure("public", source)

    %{rows: constraints} =
      query!(
        """
        SELECT r.relname, c.conname FROM pg_constraint AS c
        JOIN pg_class AS r ON r.oid = c.conrelid
        WHERE c.contype = 'f' AND c.connamespace = $1::text::regnamespace AND c.confrelid = 'public.users'::regclass
        """,
        [source]
      )

    Enum.each(constraints, fn [table, name] ->
      query!(~s|ALTER TABLE "#{source}"."#{table}" DROP CONSTRAINT "#{name}"|)
    end)

    query!(~s|CREATE TABLE "#{source}".users (id bigserial PRIMARY KEY, email text NOT NULL)|)

    query!(~s|INSERT INTO "#{source}".users (id, email) VALUES (1, $1), (2, 'gone@elsewhere.example')|, [
      "EDITOR-#{unique}@Example.com"
    ])

    query!("""
    INSERT INTO "#{source}".sites_identities (name, language, inserted_at, updated_at)
    VALUES ('Acme Identity', 'en', now(), now())
    """)

    query!("""
    INSERT INTO "#{source}".pages (id, title, uri, language, is_homepage, creator_id, updated_by_id, breadcrumbs, inserted_at, updated_at)
    VALUES
      (10, 'Home', 'index', 'en', true, 1, 2, '[]', now(), now()),
      (11, 'About', 'about', 'en', false, 2, 1, '[{"title": "MyApp", "uri": "/"}]', now(), now())
    """)

    query!(~s|UPDATE "#{source}".pages SET parent_id = 10, publish_at = now() + interval '2 days' WHERE id = 11|)

    query!("""
    INSERT INTO "#{source}".content_block_archive (root_block_id, data, removed_by_id, inserted_at)
    VALUES (5, '{"content_blocks": [{"id": 5, "creator_id": 1, "updated_by_id": 2}]}', 2, now())
    """)

    query!(~s|SELECT setval('"#{source}"."pages_id_seq"', 11)|)

    snapshot = Brando.Utils.term_to_binary(%Brando.Pages.Page{id: 11, title: "About", creator_id: 2, updated_by_id: 1})

    query!(
      """
      INSERT INTO "#{source}".revisions (entry_type, entry_id, revision, encoded_entry, metadata, creator_id, scheduled, inserted_at, updated_at)
      VALUES ('Elixir.Brando.Pages.Page', 11, 1, $1, '{}', 2, true, now(), now())
      """,
      [snapshot]
    )

    query!("""
    INSERT INTO "#{source}".listing_views (name, schema, listing, creator_id, inserted_at, updated_at)
    VALUES ('mine', 'pages', 'default', 1, now(), now()), ('theirs', 'pages', 'default', 2, now(), now())
    """)

    query!("""
    INSERT INTO "#{source}".content_markdown_events (actor_id, action, inserted_at) VALUES (2, 'synced', now())
    """)

    query!("""
    INSERT INTO "#{source}".content_markdown_sources (name, path, ref, connection, enabled, inserted_at, updated_at)
    VALUES ('Docs', 'docs', 'main', 'github', true, now(), now())
    """)

    query!("""
    INSERT INTO "#{source}".notification_routes (name, kind, recipient_ids, creator_id, active, inserted_at, updated_at)
    VALUES ('Editors', 'email', ARRAY[1, 2], 1, true, now(), now())
    """)

    query!("""
    INSERT INTO "#{source}".webhooks (name, url, secret_ciphertext, active, creator_id, inserted_at, updated_at)
    VALUES ('Build', 'https://hooks.example.com/build', 'ciphertext', true, 2, now(), now())
    """)

    query!("""
    INSERT INTO "#{source}".videos (type, remote_id, meta, inserted_at, updated_at)
    VALUES ('vimeo_account', '123', '{"provider": "vimeo"}', now(), now())
    """)
  end

  defp source_snapshot(source) do
    {:ok, dump} = SchemaCloner.dump_schema(source)
    dump
  end

  defp media_snapshot(root) do
    root
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.sort()
    |> Enum.map(fn path ->
      {:ok, stat} = File.lstat(path)
      content = if stat.type == :regular, do: :crypto.hash(:sha256, File.read!(path))
      {Path.relative_to(path, root), stat.type, stat.mode, stat.mtime, content}
    end)
  end

  defp insert_user!(email, role) do
    %{rows: [[id]]} =
      query!(
        """
        INSERT INTO public.users (name, email, password, role, active, language, inserted_at, updated_at)
        VALUES ($1, $1, 'x', $2, true, 'en', now(), now()) RETURNING id
        """,
        [email, role]
      )

    %Brando.Users.User{id: id, email: email, role: String.to_existing_atom(role), active: true}
  end

  defp remove_site(site_key) do
    case Registry.get_site_by_key(site_key) do
      nil ->
        :ok

      site ->
        {:ok, archived} = Setup.archive_site(site)
        {:ok, _deleted} = Setup.delete_site(archived, force: true)
    end
  end

  # on_exit runs in another process, which needs the repo set again
  defp with_repo(fun) do
    previous = Application.fetch_env(:brando, :repo_module)
    Application.put_env(:brando, :repo_module, Repo)
    Brando.Test.ScopedEnv.put(:tenancy_mode, :multi)

    try do
      fun.()
    after
      IntegrationRepo.restore_env(:repo_module, previous)
      Brando.Test.ScopedEnv.delete(self(), :tenancy_mode)
    end
  end

  defp site_attrs(key) do
    %{name: "Acme", key: key, languages: ["en"], default_language: "en", status: :active, delivery_mode: :dynamic}
  end

  defp query!(sql, params \\ []), do: SQL.query!(Repo, sql, params)
end
