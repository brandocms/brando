defmodule Brando.Environments.ArchiveUpgradeTest do
  # A site with a live environment holding content, archived before the
  # brando_2xx migrations ran, then upgraded. Restoring that archive either
  # ends with an environment as up to date as the live one, or is refused
  # and leaves nothing behind.
  #
  # Schemas are copied with SQL rather than pg_dump, which cannot see the
  # sandbox transaction; everything is undone with it.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Brando.MigrationTemplates

  alias Brando.Environments
  alias Brando.Environments.ArchiveUpgrade
  alias Brando.Environments.Environment
  alias Brando.Environments.OperationLog
  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry

  @live "tenant_acme_production"

  defmodule SqlSchemaCloner do
    @moduledoc false
    @behaviour Brando.Environments.SchemaCloner

    @impl true
    def clone_schema(source, target), do: Brando.MigrationTemplates.copy_schema(source, target)
  end

  defmodule NoTenantMigrations do
    @moduledoc false
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  defmodule RaisingSchemaCloner do
    @moduledoc false
    @behaviour Brando.Environments.SchemaCloner

    # Half a copy, then a crash
    @impl true
    def clone_schema(source, target) do
      Brando.MigrationTemplates.query!(~s(CREATE SCHEMA "#{target}"))
      Brando.MigrationTemplates.copy_tables(source, target, ["pages"], true)
      raise "the clone broke halfway"
    end
  end

  defmodule RaisingTenantMigrations do
    @moduledoc false
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: raise("a tenant migration broke")
  end

  defmodule RaisingMigrator do
    @moduledoc false
    def up(_repo, _version, _module, _opts), do: raise("a replay broke")
  end

  defmodule ExitingMigrator do
    @moduledoc false
    def up(_repo, _version, _module, _opts), do: exit(:replay_went_away)
  end

  # Replays slowly, checking its module is still there, with the database
  # work taken one at a time (the sandbox has one connection)
  defmodule SlowMigrator do
    @moduledoc false
    def up(repo, version, module, opts) do
      send(Application.fetch_env!(:brando, :archive_replay_test_pid), {:replaying, module})
      Process.sleep(20)
      true = Code.ensure_loaded?(module)

      :global.trans({__MODULE__, :database}, fn ->
        Brando.MigrationTemplates.InProcessMigrator.up(repo, version, module, opts)
      end)
    end
  end

  setup do
    directory = Path.join(System.tmp_dir!(), "brando_archive_upgrade_#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)

    put_test_env(:tenancy_mode, :multi)
    put_test_env(:tenant_migrator, NoTenantMigrations)
    put_test_env(:environment_schema_cloner, SqlSchemaCloner)
    put_test_env(:public_migrations_path, directory)
    put_test_env(:archive_upgrade_migrator, Brando.MigrationTemplates.InProcessMigrator)
    Cache.clear()

    on_exit(fn ->
      File.rm_rf!(directory)
      Cache.clear()
    end)

    {:ok, site} =
      Registry.create_site(%{
        name: "Acme",
        key: "acme",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, _live} = Registry.create_environment(site, %{name: "Production", key: "production", live: true})

    # Before the upgrade: the live environment holds content, and is archived
    # an hour before the migrations run
    roll_back_2xx()
    content = provision(@live)
    # Its tenant migrations' history, which provisioning starts
    copy_table("public", @live, "schema_migrations")
    taken_at = NaiveDateTime.add(NaiveDateTime.utc_now(), -3600)
    archive = "#{@live}_archive_#{Calendar.strftime(taken_at, "%Y%m%d%H%M%S")}"
    copy_schema(@live, archive)

    # The test database's own migrations ran before the archive was taken,
    # however recently it was built (CI builds it just before the run)
    query!("UPDATE schema_migrations SET inserted_at = $1", [NaiveDateTime.add(taken_at, -86_400)])

    # The upgrade, as `mix brando.migrate` runs it
    copied = copy_2xx(directory)
    migrate(directory, :up)

    %{site: site, archive: archive, content: content, directory: directory, copied: copied}
  end

  defp restored_schemas,
    do: List.flatten(rows("SELECT nspname FROM pg_namespace WHERE nspname LIKE 'tenant_acme_rollback%'"))

  defp environment_keys(site), do: site |> Registry.list_environments() |> Enum.map(& &1.key) |> Enum.sort()
  defp rollbacks(site), do: Enum.filter(Environments.list_operation_logs(site), &(&1.operation == :rollback))

  defp loops(copied), do: Enum.filter(copied, fn {_, file} -> File.read!(path(file)) =~ "nspname ~ '^tenant_" end)

  # The 2xx tables, with foreign keys to the environment's own tables named
  # `:own`, so two environments compare equal
  defp own_tables(schema) do
    Map.new(table_set(schema, environment_tables()), fn {table, {columns, indexes, references}} ->
      {table,
       {columns, indexes,
        Enum.map(references, fn
          {column, ^schema, target} -> {column, :own, target}
          other -> other
        end)}}
    end)
  end

  # Every table of a schema: its columns, indexes and rows
  defp fingerprint(schema) do
    Map.new(tables(schema), fn table ->
      [[rows]] =
        rows(~s{SELECT md5(coalesce(string_agg(t::text, '|' ORDER BY t::text), '')) FROM "#{schema}"."#{table}" t})

      {table, {column_definitions(schema, table), indexes(schema, table), rows}}
    end)
  end

  defp assert_nothing_restored(site, archive) do
    assert environment_keys(site) == ["production"]
    assert restored_schemas() == []
    assert rollbacks(site) == []
    # The archive is as it was
    refute table?(archive, "search_documents")
  end

  test "a missed migration is replayed in the restored environment only", %{
    site: site,
    archive: archive,
    content: content,
    copied: copied
  } do
    loops = Enum.map(loops(copied), &elem(&1, 0))
    assert length(loops) == 9

    assert {:ok, %Environment{live: false} = restored} = Environments.rollback(site, archive_schema: archive)
    prefix = Tenant.prefix(site, restored)

    assert ArchiveUpgrade.missing(prefix, @live) == []
    assert own_tables(prefix) == own_tables(@live)
    assert column_set(prefix, environment_columns()) == column_set(@live, environment_columns())

    # The data migrations ran on the archive's content
    assert rows(~s(SELECT content_modified_at FROM "#{prefix}".pages WHERE id = $1), [content.page]) ==
             [[~N[2026-01-01 10:00:00]]]

    assert [[code]] = rows(~s(SELECT code FROM "#{prefix}".content_modules WHERE id = $1), [content.module])
    assert code =~ "{% picture image.image %}"

    # Recorded in the environment's own history
    replayed = List.flatten(rows(~s(SELECT version FROM "#{prefix}".schema_migrations)))
    assert Enum.sort(replayed) == Enum.sort(loops)

    for schema <- [Brando.Pages.Page, Brando.Search.Document, Brando.Webhooks.Webhook, Brando.Notes.Note] do
      assert is_list(BrandoIntegration.Repo.all(schema, prefix: prefix))
    end

    refute table?(archive, "search_documents")
    assert [%OperationLog{archive_schema: ^archive}] = rollbacks(site)
  end

  # Outside a restore, so `Ecto.Migrator` can take a connection of its own
  test "replays through Ecto.Migrator in the one environment it is given", %{archive: archive, copied: copied} do
    put_test_env(:archive_upgrade_migrator, Ecto.Migrator)
    restored = "tenant_acme_restored"
    copy_schema(archive, restored)

    assert {:ok, replays} = ArchiveUpgrade.plan(archive)

    # Every 2xx migration that loops over the environments can run in one;
    # the ones that only change public are left alone
    assert length(copied) == 14
    assert Enum.map(replays, & &1.name) == for({_, file} <- loops(copied), do: Path.basename(file, ".exs"))

    public = fingerprint("public")
    live = fingerprint(@live)

    assert :ok = ArchiveUpgrade.replay(replays, restored)
    assert ArchiveUpgrade.missing(restored, @live) == []
    assert ArchiveUpgrade.replay(replays, restored) == :ok

    # Nothing outside the restored schema was written
    assert fingerprint("public") == public
    assert fingerprint(@live) == live
  end

  test "an archive taken after the migrations ran is restored as it is", %{site: site} do
    taken_at = NaiveDateTime.add(NaiveDateTime.utc_now(), 60)
    archive = "#{@live}_archive_#{Calendar.strftime(taken_at, "%Y%m%d%H%M%S")}"
    copy_schema(@live, archive)

    assert {:ok, %Environment{} = restored} = Environments.rollback(site, archive_schema: archive)
    assert rows(~s{SELECT count(*) FROM "#{Tenant.prefix(site, restored)}".schema_migrations}) == [[0]]
  end

  test "is refused before anything changes when a missed migration cannot be replayed", %{
    site: site,
    archive: archive,
    directory: directory
  } do
    # An older Brando migration, without the single-environment hook, and
    # one of the application's own that loops over the environments
    File.cp!(
      path("brando_198_fix_legacy_block_sources.exs"),
      Path.join(directory, "20260101000198_brando_198_fix_legacy_block_sources.exs")
    )

    File.write!(
      Path.join(directory, "20261001000000_tag_every_environment.exs"),
      "# nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
    )

    for version <- [20_260_101_000_198, 20_261_001_000_000] do
      query!("INSERT INTO schema_migrations (version, inserted_at) VALUES ($1, $2)", [version, NaiveDateTime.utc_now()])
    end

    assert {:error, {:archive_behind, {:migrations, ["brando_198_fix_legacy_block_sources", "tag_every_environment"]}}} =
             Environments.rollback(site, archive_schema: archive)

    assert_nothing_restored(site, archive)
  end

  test "is refused and undone when the result lacks what the live environment has", %{site: site, archive: archive} do
    query!(~s(ALTER TABLE "#{@live}".pages ADD COLUMN subtitle text))

    assert {:error, {:archive_behind, {:structure, ["pages.subtitle"]}}} =
             Environments.rollback(site, archive_schema: archive)

    assert_nothing_restored(site, archive)
  end

  test "is undone when a replay fails", %{site: site, archive: archive} do
    # The archive has the table brando_212 creates, so replaying it fails
    query!(~s{CREATE TABLE "#{archive}".search_documents (LIKE public.search_documents INCLUDING ALL)})

    assert {:error, {:archive_upgrade_failed, {"brando_212_add_search_documents", message}}} =
             Environments.rollback(site, archive_schema: archive)

    assert message =~ "already exists"
    assert environment_keys(site) == ["production"]
    assert restored_schemas() == []
    assert rollbacks(site) == []
  end

  test "compares indexes by what they cover, not by their names", %{archive: archive} do
    other = "tenant_acme_other"
    copy_schema(@live, other)
    assert ArchiveUpgrade.missing(other, @live) == []

    # Tenant migrations name some indexes after the schema
    query!(~s{CREATE INDEX "#{@live}_pages_title_index" ON "#{@live}".pages (title)})
    assert ArchiveUpgrade.missing(other, @live) == ["index on pages (title)"]

    query!(~s{CREATE INDEX "#{other}_pages_title_index" ON "#{other}".pages (title)})
    assert ArchiveUpgrade.missing(other, @live) == []

    assert "sites_indexnow" in ArchiveUpgrade.missing(archive, @live)
    assert "pages.meta_canonical_url" in ArchiveUpgrade.missing(archive, @live)
  end

  describe "a step that raises after the environment was created" do
    @describetag :capture_log

    test "cloning", %{site: site, archive: archive} do
      put_test_env(:environment_schema_cloner, RaisingSchemaCloner)

      assert {:error, {:archive_restore_failed, {:exception, "the clone broke halfway"}}} =
               Environments.rollback(site, archive_schema: archive)

      assert_nothing_restored(site, archive)
    end

    test "replaying", %{site: site, archive: archive} do
      put_test_env(:archive_upgrade_migrator, RaisingMigrator)

      assert {:error, {:archive_upgrade_failed, {"brando_200_fix_assigned_gallery_loops", "a replay broke"}}} =
               Environments.rollback(site, archive_schema: archive)

      assert_nothing_restored(site, archive)

      put_test_env(:archive_upgrade_migrator, ExitingMigrator)

      assert {:error, {:archive_upgrade_failed, {_name, {:exit, :replay_went_away}}}} =
               Environments.rollback(site, archive_schema: archive)

      assert_nothing_restored(site, archive)
    end

    test "running the tenant migrations", %{site: site, archive: archive} do
      put_test_env(:tenant_migrator, RaisingTenantMigrations)

      assert {:error, {:archive_restore_failed, {:exception, "a tenant migration broke"}}} =
               Environments.rollback(site, archive_schema: archive)

      assert_nothing_restored(site, archive)
    end

    test "comparing with the live environment", %{site: site, archive: archive} do
      # A shared table setting Brando cannot read
      put_test_env(:shared_tables, [%{}])

      assert {:error, {:archive_restore_failed, {:exception, _message}}} =
               Environments.rollback(site, archive_schema: archive)

      put_test_env(:shared_tables, [])
      assert_nothing_restored(site, archive)
    end

    test "logging the operation", %{site: site, archive: archive} do
      # No such user
      assert {:error, {:archive_restore_failed, {:exception, message}}} =
               Environments.rollback(site, archive_schema: archive, creator_id: -1)

      assert message =~ "environment_operation_logs_creator_id_fkey"
      assert_nothing_restored(site, archive)
    end
  end

  test "an index whose name has a space in it is compared like any other", %{site: site, archive: archive} do
    for schema <- [@live, archive], do: query!(~s{CREATE INDEX "my idx" ON "#{schema}".pages (title)})

    assert {:ok, %Environment{} = restored} = Environments.rollback(site, archive_schema: archive)
    assert ArchiveUpgrade.missing(Tenant.prefix(site, restored), @live) == []

    query!(~s{DROP INDEX "#{Tenant.prefix(site, restored)}"."my idx"})
    assert ArchiveUpgrade.missing(Tenant.prefix(site, restored), @live) == ["index on pages (title)"]
  end

  test "two replays at once, as for two sites, keep to their own modules", %{archive: archive} do
    put_test_env(:archive_upgrade_migrator, SlowMigrator)
    put_test_env(:archive_replay_test_pid, self())
    assert {:ok, replays} = ArchiveUpgrade.plan(archive)

    schemas = ["tenant_acme_first", "tenant_beta_second"]
    Enum.each(schemas, &copy_schema(archive, &1))

    assert [:ok, :ok] =
             schemas
             |> Enum.map(fn schema -> Task.async(fn -> ArchiveUpgrade.replay(replays, schema) end) end)
             |> Task.await_many(30_000)

    for schema <- schemas, do: assert(ArchiveUpgrade.missing(schema, @live) == [])

    modules =
      for _ <- 1..(2 * length(replays)) do
        assert_receive {:replaying, module}
        module
      end

    assert length(Enum.uniq(modules)) == length(modules)
    refute Enum.any?(modules, &Code.ensure_loaded?/1)
  end

  describe "planning looks only at what ran since the archive was taken" do
    test "a version from before it, whose file is long gone, is no reason to refuse", %{archive: archive, copied: copied} do
      taken_at = ArchiveUpgrade.taken_at(archive)

      # The test database's own versions have no file in the migrations
      # directory here either
      assert length(rows("SELECT version FROM schema_migrations")) > length(copied)

      # Squashed or deleted years ago, and one loaded from a structure.sql
      # dump, which records no time
      query!("INSERT INTO schema_migrations (version, inserted_at) VALUES ($1, $2), ($3, NULL)", [
        19_990_101_000_000,
        ~N[1999-01-01 10:00:00],
        19_990_102_000_000
      ])

      # One second before the archive was taken
      query!("INSERT INTO schema_migrations (version, inserted_at) VALUES ($1, $2)", [
        20_990_101_000_000,
        NaiveDateTime.add(taken_at, -1)
      ])

      assert {:ok, replays} = ArchiveUpgrade.plan(archive)
      assert length(replays) == 9
    end

    test "a version from the second it was taken counts as since", %{archive: archive} do
      query!("INSERT INTO schema_migrations (version, inserted_at) VALUES ($1, $2)", [
        20_990_101_000_000,
        ArchiveUpgrade.taken_at(archive)
      ])

      assert {:error, {:archive_behind, {:migrations, ["20990101000000 (no migration file)"]}}} =
               ArchiveUpgrade.plan(archive)
    end

    test "an older archive misses more", %{archive: archive, copied: copied} do
      # Taken before brando_210 ran: 210, 211, 212, 215 and 216 were missed
      versions = Map.new(copied, fn {version, file} -> {number(file), version} end)
      taken_at = ArchiveUpgrade.taken_at(archive)

      ran_at = fn number ->
        if number < 210, do: NaiveDateTime.add(taken_at, -60), else: NaiveDateTime.add(taken_at, 60)
      end

      for {number, version} <- versions,
          do: query!("UPDATE schema_migrations SET inserted_at = $1 WHERE version = $2", [ran_at.(number), version])

      assert {:ok, replays} = ArchiveUpgrade.plan(archive)
      assert Enum.map(replays, &number(&1.name <> ".exs")) == [210, 211, 212, 215, 216]
    end
  end

  describe "planning refuses an archive it cannot account for" do
    test "a migration that ran since, without a file", %{site: site, archive: archive} do
      query!("INSERT INTO schema_migrations (version, inserted_at) VALUES ($1, $2)", [
        20_991_231_000_000,
        NaiveDateTime.utc_now()
      ])

      assert {:error, {:archive_behind, {:migrations, ["20991231000000 (no migration file)"]}}} =
               Environments.rollback(site, archive_schema: archive)

      assert_nothing_restored(site, archive)
    end

    test "a migrations directory that is not there", %{site: site, archive: archive, directory: directory} do
      put_test_env(:public_migrations_path, [directory, "/nonexistent/migrations"])

      assert {:error, {:archive_behind, {:migrations_path, "/nonexistent/migrations"}}} =
               Environments.rollback(site, archive_schema: archive)

      assert_nothing_restored(site, archive)
    end

    test "but finds migrations in subdirectories", %{archive: archive, directory: directory} do
      File.mkdir_p!(Path.join(directory, "brando"))

      for file <- Path.wildcard(Path.join(directory, "*_brando_21*.exs")),
          do: File.rename!(file, Path.join([directory, "brando", Path.basename(file)]))

      assert {:ok, replays} = ArchiveUpgrade.plan(archive)
      assert length(replays) == 9
    end
  end

  test "a migration that ran in the second the archive was taken, and is in it, is not replayed", %{
    site: site,
    archive: archive,
    copied: copied
  } do
    # The archive is taken in the same second as the upgrade, with brando_212 in it already
    second = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    versions = Enum.map(copied, &elem(&1, 0))
    query!("UPDATE schema_migrations SET inserted_at = $1 WHERE version = ANY($2)", [second, versions])

    same_second = "#{@live}_archive_#{Calendar.strftime(second, "%Y%m%d%H%M%S")}"
    copy_schema(archive, same_second)
    copy_tables(@live, same_second, ["search_documents"], true)

    assert {:ok, %Environment{} = restored} = Environments.rollback(site, archive_schema: same_second)
    prefix = Tenant.prefix(site, restored)
    assert ArchiveUpgrade.missing(prefix, @live) == []

    # brando_212 was rolled back and not recorded; the others ran
    replayed = List.flatten(rows(~s(SELECT version FROM "#{prefix}".schema_migrations)))
    assert length(replayed) == 8
  end

  describe "comparing with the live environment" do
    setup do
      other = "tenant_acme-shop_production"
      copy_schema(@live, other)
      %{other: other}
    end

    test "names in another schema, quoted or not, are no difference", %{other: other} do
      assert ArchiveUpgrade.missing(other, @live) == []
      assert ArchiveUpgrade.missing(@live, other) == []
    end

    test "finds columns whose nullability or default differ", %{other: other} do
      query!(~s{ALTER TABLE "#{other}".sites_not_found_hits ALTER COLUMN url DROP NOT NULL})
      query!(~s{ALTER TABLE "#{other}".sites_not_found_hits ALTER COLUMN hits DROP DEFAULT})

      assert Enum.sort(ArchiveUpgrade.missing(other, @live)) == ["sites_not_found_hits.hits", "sites_not_found_hits.url"]
    end

    test "finds missing foreign keys and unique constraints", %{other: other} do
      query!(~s{ALTER TABLE "#{other}".webhook_deliveries DROP CONSTRAINT webhook_deliveries_webhook_id_fkey})
      query!(~s{ALTER TABLE "#{other}".sites_indexnow DROP CONSTRAINT sites_indexnow_pkey})

      assert ArchiveUpgrade.missing(other, @live) == [
               "foreign key on webhook_deliveries (webhook_id) to webhooks (id)",
               "unique index on sites_indexnow (id)",
               "unique on sites_indexnow (id)"
             ]
    end
  end

  # A replay runs a template's up/0 for one environment. Anything outside its
  # loop over prefixes() would run against public, or wherever it points.
  test "every template with the replay hook does all its work inside the loop" do
    hooked =
      for template <- Path.wildcard(path("brando_*.exs")),
          File.read!(template) =~ ~r/case prefix\(\) do/,
          do: template

    assert length(hooked) == 9

    for template <- hooked do
      {:ok, ast} = template |> File.read!() |> Code.string_to_quoted()

      [body] =
        ast
        |> Macro.prewalk([], fn
          {:def, _, [{:up, _, args}, [do: body]]} = node, found when args in [nil, []] -> {node, [body | found]}
          node, found -> {node, found}
        end)
        |> elem(1)

      statements =
        case body do
          {:__block__, _, statements} -> statements
          statement -> [statement]
        end

      for statement <- statements do
        assert in_loop?(statement), "#{Path.basename(template)}: #{Macro.to_string(statement)}"
      end
    end
  end

  defp in_loop?({:for, _, args}), do: Enum.any?(args, &match?({:<-, _, [_, {:prefixes, _, []}]}, &1))
  defp in_loop?({:flush, _, []}), do: true
  defp in_loop?(_statement), do: false

  test "the test-only migrator setting is not documented" do
    {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(ArchiveUpgrade)
    refute moduledoc =~ "archive_upgrade_migrator"
  end

  test "takes the archive's age from its name" do
    assert ArchiveUpgrade.taken_at("tenant_acme_production_archive_20261008123456") == ~N[2026-10-08 12:34:56]
    assert ArchiveUpgrade.taken_at("tenant_acme_production_archive_20261008123456_0a1b2c3d") == ~N[2026-10-08 12:34:56]
    assert ArchiveUpgrade.taken_at("tenant_acme_production") == nil
    assert {:error, {:archive_behind, :unknown_age}} = ArchiveUpgrade.plan("tenant_acme_production")
  end
end
