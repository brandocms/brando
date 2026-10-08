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
    assert length(loops) == 7

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

    # Every 2xx migration that loops over the environments can run in one
    assert Enum.map(replays, &elem(&1, 1)) == for({_, file} <- loops(copied), do: Path.basename(file, ".exs"))

    # Every template would fail with "already exists" in public and the live
    # environment if it ran there too
    assert :ok = ArchiveUpgrade.replay(replays, restored)
    assert ArchiveUpgrade.missing(restored, @live) == []
    assert ArchiveUpgrade.replay(replays, restored) == :ok
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

  test "takes the archive's age from its name" do
    assert ArchiveUpgrade.taken_at("tenant_acme_production_archive_20261008123456") == ~N[2026-10-08 12:34:56]
    assert ArchiveUpgrade.taken_at("tenant_acme_production_archive_20261008123456_0a1b2c3d") == ~N[2026-10-08 12:34:56]
    assert ArchiveUpgrade.taken_at("tenant_acme_production") == nil
    assert {:error, {:archive_behind, :unknown_age}} = ArchiveUpgrade.plan("tenant_acme_production")
  end
end
