defmodule Brando.Blueprint.MigrationExecutionTest do
  use ExUnit.Case, async: false

  alias Brando.Blueprint.Migrations

  defmodule MigrationRepo do
    use Ecto.Repo,
      otp_app: :brando,
      adapter: Ecto.Adapters.Postgres
  end

  @migration_path "tmp/executable_blueprint_migrations"
  @snapshot_path "tmp/executable_blueprint_snapshots"

  setup_all do
    integration_config = BrandoIntegration.Repo.config()

    repo_options =
      integration_config
      |> Keyword.take([:database, :hostname, :password, :port, :socket_options, :ssl, :username])
      |> Keyword.merge(pool: DBConnection.ConnectionPool, pool_size: 2)

    {:ok, repo} = MigrationRepo.start_link(repo_options)

    on_exit(fn ->
      try do
        GenServer.stop(repo)
      catch
        :exit, _ -> :ok
      end
    end)

    :ok
  end

  setup do
    File.rm_rf!(@migration_path)
    File.rm_rf!(@snapshot_path)

    prefix = "blueprint_migration_#{System.unique_integer([:positive])}"
    Ecto.Adapters.SQL.query!(MigrationRepo, ~s(CREATE SCHEMA "#{prefix}"), [])

    on_exit(fn ->
      Ecto.Adapters.SQL.query!(MigrationRepo, ~s(DROP SCHEMA IF EXISTS "#{prefix}" CASCADE), [])
      File.rm_rf!(@migration_path)
      File.rm_rf!(@snapshot_path)
    end)

    {:ok, prefix: prefix}
  end

  test "generated migrations execute up and roll back down", %{prefix: prefix} do
    opts = [migration_path: @migration_path, snapshot_path: @snapshot_path]

    assert {:ok, first} = Migrations.create_migration(Brando.MigrationTest.ExecutionV1, opts)
    assert {:ok, second} = Migrations.create_migration(Brando.MigrationTest.ExecutionV2, opts)

    first_version = migration_version(first.migration)
    second_version = migration_version(second.migration)
    assert second_version > first_version

    migration_source = [
      {first_version, compile_migration!(first.migration)},
      {second_version, compile_migration!(second.migration)}
    ]

    assert [^first_version, ^second_version] =
             Ecto.Migrator.run(MigrationRepo, migration_source, :up,
               all: true,
               prefix: prefix,
               log: false
             )

    assert %{rows: [["integer", "0"]]} =
             Ecto.Adapters.SQL.query!(
               MigrationRepo,
               """
               SELECT data_type, column_default
               FROM information_schema.columns
               WHERE table_schema = $1
                 AND table_name = 'blueprint_migration_execution_records'
                 AND column_name = 'count'
               """,
               [prefix]
             )

    assert [^second_version, ^first_version] =
             Ecto.Migrator.run(MigrationRepo, migration_source, :down,
               all: true,
               prefix: prefix,
               log: false
             )

    assert %{rows: [[nil]]} =
             Ecto.Adapters.SQL.query!(
               MigrationRepo,
               "SELECT to_regclass($1)",
               ["#{prefix}.blueprint_migration_execution_records"]
             )
  end

  test "unique language attributes create a real unique PostgreSQL index", %{prefix: prefix} do
    opts = [migration_path: @migration_path, snapshot_path: @snapshot_path]
    module = Brando.MigrationTest.UniqueLanguage
    table = module.__schema__(:source)

    assert {:ok, generated} = Migrations.create_migration(module, opts)
    version = migration_version(generated.migration)
    migration_source = [{version, compile_migration!(generated.migration)}]

    assert [^version] =
             Ecto.Migrator.run(MigrationRepo, migration_source, :up,
               all: true,
               prefix: prefix,
               log: false
             )

    assert %{rows: [[1]]} =
             Ecto.Adapters.SQL.query!(
               MigrationRepo,
               """
               SELECT count(*)
               FROM pg_indexes
               WHERE schemaname = $1
                 AND tablename = $2
                 AND indexdef LIKE 'CREATE UNIQUE INDEX%'
                 AND indexdef LIKE '%(language)%'
               """,
               [prefix, table]
             )

    assert [^version] =
             Ecto.Migrator.run(MigrationRepo, migration_source, :down,
               all: true,
               prefix: prefix,
               log: false
             )
  end

  test "physical field sources execute with matching keys, indexes, and references", %{prefix: prefix} do
    opts = [migration_path: @migration_path, snapshot_path: @snapshot_path]
    module = Brando.MigrationTest.PhysicalSources
    table = module.__schema__(:source)

    Ecto.Adapters.SQL.query!(
      MigrationRepo,
      ~s|CREATE TABLE "#{prefix}".users (id bigserial PRIMARY KEY)|,
      []
    )

    Ecto.Adapters.SQL.query!(
      MigrationRepo,
      ~s|CREATE TABLE "#{prefix}".content_identifiers (id bigserial PRIMARY KEY)|,
      []
    )

    assert {:ok, generated} = Migrations.create_migration(module, opts)
    version = migration_version(generated.migration)
    migration_source = [{version, compile_migration!(generated.migration)}]

    assert [^version] =
             Ecto.Migrator.run(MigrationRepo, migration_source, :up,
               all: true,
               prefix: prefix,
               log: false
             )

    assert %{rows: [["account_ref"], ["headline"], ["owner_ref"], ["payload"], ["record_pk"]]} =
             Ecto.Adapters.SQL.query!(
               MigrationRepo,
               """
               SELECT column_name
               FROM information_schema.columns
               WHERE table_schema = $1 AND table_name = $2
               ORDER BY column_name
               """,
               [prefix, table]
             )

    assert %{rows: [[2]]} =
             Ecto.Adapters.SQL.query!(
               MigrationRepo,
               """
               SELECT count(*)
               FROM pg_indexes
               WHERE schemaname = $1
                 AND tablename = $2
                 AND indexdef LIKE 'CREATE UNIQUE INDEX%'
                 AND (indexdef LIKE '%(headline, account_ref)%'
                      OR indexdef LIKE '%(owner_ref, account_ref)%')
               """,
               [prefix, table]
             )

    auxiliary_table = "#{table}_related_entries_identifiers"

    assert %{rows: [["record_pk"]]} =
             Ecto.Adapters.SQL.query!(
               MigrationRepo,
               """
               SELECT target_column.attname
               FROM pg_constraint AS con
               JOIN pg_class AS owner_table ON owner_table.oid = con.conrelid
               JOIN pg_namespace AS namespace ON namespace.oid = owner_table.relnamespace
               JOIN pg_class AS target_table ON target_table.oid = con.confrelid
               JOIN pg_attribute AS target_column
                 ON target_column.attrelid = target_table.oid
                AND target_column.attnum = con.confkey[1]
               WHERE namespace.nspname = $1
                 AND owner_table.relname = $2
                 AND con.contype = 'f'
                 AND target_table.relname = $3
               """,
               [prefix, auxiliary_table, table]
             )

    assert [^version] =
             Ecto.Migrator.run(MigrationRepo, migration_source, :down,
               all: true,
               prefix: prefix,
               log: false
             )
  end

  defp migration_version(filename) do
    filename
    |> Path.basename()
    |> String.split("_", parts: 2)
    |> hd()
    |> String.to_integer()
  end

  defp compile_migration!(filename) do
    [{module, _bytecode}] = Code.compile_file(filename)
    module
  end
end
