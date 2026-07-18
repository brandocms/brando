defmodule Brando.Blueprint.MigrationExecutionTest do
  use ExUnit.Case, async: false

  alias Brando.Blueprint.Migrations
  alias Brando.Blueprint.Migrations.Schema, as: MigrationSchema

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

    assert %{rows: [["RESTRICT"]]} =
             Ecto.Adapters.SQL.query!(
               MigrationRepo,
               """
               SELECT delete_rule
               FROM information_schema.referential_constraints
               WHERE constraint_schema = $1
                 AND constraint_name = $2
               """,
               [prefix, "#{table}_owner_ref_fkey"]
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

  test "field options execute with dumped defaults and primitive custom types", %{prefix: prefix} do
    opts = [migration_path: @migration_path, snapshot_path: @snapshot_path]
    module = Brando.MigrationTest.FieldOptions
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

    column_types =
      MigrationRepo
      |> Ecto.Adapters.SQL.query!(
        """
        SELECT column_name, data_type, udt_name, is_nullable
        FROM information_schema.columns
        WHERE table_schema = $1 AND table_name = $2 AND column_name != 'id'
        """,
        [prefix, table]
      )
      |> Map.fetch!(:rows)
      |> Map.new(fn [name, data_type, udt_name, nullable] ->
        {name, {data_type, udt_name, nullable}}
      end)

    assert column_types["visibility"] == {"text", "text", "NO"}
    assert column_types["priority"] == {"integer", "int4", "NO"}
    assert column_types["formats"] == {"ARRAY", "_text", "NO"}
    assert column_types["native_formats"] == {"ARRAY", "_text", "NO"}
    assert column_types["amount"] == {"numeric", "numeric", "NO"}
    assert column_types["module_name"] == {"character varying", "varchar", "NO"}
    assert column_types["payload"] == {"jsonb", "jsonb", "NO"}
    assert column_types["published_on"] == {"date", "date", "NO"}

    assert %{rows: [[12, 4]]} =
             Ecto.Adapters.SQL.query!(
               MigrationRepo,
               """
               SELECT numeric_precision, numeric_scale
               FROM information_schema.columns
               WHERE table_schema = $1 AND table_name = $2 AND column_name = 'amount'
               """,
               [prefix, table]
             )

    assert %{rows: [["private", 1, ["jpg"], ["png"], amount, module_name, %{}, ~D[2026-01-02]]]} =
             Ecto.Adapters.SQL.query!(
               MigrationRepo,
               ~s|INSERT INTO "#{prefix}"."#{table}" DEFAULT VALUES RETURNING visibility, priority, formats, native_formats, amount, module_name, payload, published_on|,
               []
             )

    assert Decimal.equal?(amount, Decimal.new("1.2500"))
    assert module_name == Atom.to_string(module)

    assert [^version] =
             Ecto.Migrator.run(MigrationRepo, migration_source, :down,
               all: true,
               prefix: prefix,
               log: false
             )
  end

  test "alter operations execute against PostgreSQL and reverse without losing preserved data", %{prefix: prefix} do
    opts = [migration_path: @migration_path, snapshot_path: @snapshot_path]
    v1_module = Brando.MigrationTest.OperationMatrixV1
    v2_module = Brando.MigrationTest.OperationMatrixV2
    table = v1_module.__schema__(:source)

    create_dependency_tables!(prefix, ~w(users images files content_identifiers))

    Enum.each(~w(users images files), fn dependency ->
      Ecto.Adapters.SQL.query!(
        MigrationRepo,
        ~s|INSERT INTO "#{prefix}"."#{dependency}" (id) VALUES (1)|,
        []
      )
    end)

    assert {:ok, v1} = Migrations.create_migration(v1_module, opts)
    assert {:ok, v2} = Migrations.create_migration(v2_module, opts)

    {v1_version, v1_migration} = compiled_migration(v1.migration)
    {v2_version, v2_migration} = compiled_migration(v2.migration)

    assert [^v1_version] = run_migration(prefix, v1_version, v1_migration, :up)

    Ecto.Adapters.SQL.query!(
      MigrationRepo,
      """
      INSERT INTO "#{prefix}"."#{table}"
        (legacy_title, amount, obsolete, tenant_id, code, owner_id, cover_id, inserted_at, updated_at)
      VALUES
        ('preserved', 7, 'removed', 9, 'code-1', 1, 1, NOW(), NOW())
      """,
      []
    )

    [legacy_auxiliary] = Brando.Blueprint.Migrations.Schema.build(v1_module).auxiliary_tables
    [current_auxiliary] = Brando.Blueprint.Migrations.Schema.build(v2_module).auxiliary_tables

    assert table_exists?(prefix, legacy_auxiliary.name)
    refute table_exists?(prefix, current_auxiliary.name)

    assert [^v2_version] = run_migration(prefix, v2_version, v2_migration, :up)

    assert column_names(prefix, table) ==
             ~w(added amount code cover_id headline id inserted_at owner_id tenant_id updated_at)

    assert column(prefix, table, "amount") == ["double precision", "NO", "2.5"]
    assert column(prefix, table, "added") == ["boolean", "NO", "false"]
    assert column(prefix, table, "owner_id") == ["bigint", "YES", nil]

    assert %{rows: [["preserved", 7.0, false, 9, "code-1", 1, 1]]} =
             Ecto.Adapters.SQL.query!(
               MigrationRepo,
               ~s|SELECT headline, amount, added, tenant_id, code, owner_id, cover_id FROM "#{prefix}"."#{table}"|,
               []
             )

    assert foreign_key(prefix, table, "#{table}_owner_id_fkey") == ["users", "CASCADE"]
    assert foreign_key(prefix, table, "#{table}_cover_id_fkey") == ["files", "SET NULL"]

    v2_index_names = index_names(prefix, table)
    assert "#{table}_code_index" in v2_index_names
    refute "#{table}_code_tenant_id_index" in v2_index_names
    refute table_exists?(prefix, legacy_auxiliary.name)
    assert table_exists?(prefix, current_auxiliary.name)

    assert [^v2_version] = run_migration(prefix, v2_version, v2_migration, :down)

    assert column_names(prefix, table) ==
             ~w(amount code cover_id id inserted_at legacy_title obsolete owner_id tenant_id updated_at)

    assert column(prefix, table, "amount") == ["integer", "NO", "1"]
    assert column(prefix, table, "owner_id") == ["bigint", "NO", nil]

    assert %{rows: [["preserved", 7, nil, 9, "code-1", 1, 1]]} =
             Ecto.Adapters.SQL.query!(
               MigrationRepo,
               ~s|SELECT legacy_title, amount, obsolete, tenant_id, code, owner_id, cover_id FROM "#{prefix}"."#{table}"|,
               []
             )

    assert foreign_key(prefix, table, "#{table}_owner_id_fkey") == ["users", "RESTRICT"]
    assert foreign_key(prefix, table, "#{table}_cover_id_fkey") == ["images", "SET NULL"]

    v1_index_names = index_names(prefix, table)
    assert "#{table}_code_tenant_id_index" in v1_index_names
    refute "#{table}_code_index" in v1_index_names
    assert table_exists?(prefix, legacy_auxiliary.name)
    refute table_exists?(prefix, current_auxiliary.name)

    assert [^v1_version] = run_migration(prefix, v1_version, v1_migration, :down)
    refute table_exists?(prefix, table)
  end

  test "timestamp additions and removals execute in both directions", %{prefix: prefix} do
    opts = [migration_path: @migration_path, snapshot_path: @snapshot_path]

    migrations =
      [
        Brando.MigrationTest.TimestampMatrixV1,
        Brando.MigrationTest.TimestampMatrixV2,
        Brando.MigrationTest.TimestampMatrixV3
      ]
      |> Enum.map(fn module ->
        assert {:ok, generated} = Migrations.create_migration(module, opts)
        compiled_migration(generated.migration)
      end)

    [{v1_version, v1}, {v2_version, v2}, {v3_version, v3}] = migrations
    table = Brando.MigrationTest.TimestampMatrixV1.__schema__(:source)

    assert [^v1_version] = run_migration(prefix, v1_version, v1, :up)
    assert column_names(prefix, table) == ~w(id label)

    assert [^v2_version] = run_migration(prefix, v2_version, v2, :up)
    assert column_names(prefix, table) == ~w(id inserted_at label updated_at)

    assert [^v3_version] = run_migration(prefix, v3_version, v3, :up)
    assert column_names(prefix, table) == ~w(id label)

    assert [^v3_version] = run_migration(prefix, v3_version, v3, :down)
    assert column_names(prefix, table) == ~w(id inserted_at label updated_at)

    assert [^v2_version] = run_migration(prefix, v2_version, v2, :down)
    assert column_names(prefix, table) == ~w(id label)

    assert [^v1_version] = run_migration(prefix, v1_version, v1, :down)
    refute table_exists?(prefix, table)
  end

  test "UUID and absent primary keys execute against PostgreSQL", %{prefix: prefix} do
    opts = [migration_path: @migration_path, snapshot_path: @snapshot_path]

    migrations =
      [Brando.MigrationTest.StorageUuidV2, Brando.MigrationTest.NoPrimaryKey]
      |> Enum.map(fn module ->
        assert {:ok, generated} = Migrations.create_migration(module, opts)
        {module, compiled_migration(generated.migration)}
      end)

    Enum.each(migrations, fn {module, {version, migration}} ->
      assert [^version] = run_migration(prefix, version, migration, :up)

      table = module.__schema__(:source)

      case module do
        Brando.MigrationTest.StorageUuidV2 ->
          assert column(prefix, table, "id") == ["uuid", "NO", nil]
          assert primary_key_columns(prefix, table) == ["id"]

        Brando.MigrationTest.NoPrimaryKey ->
          assert column_names(prefix, table) == ["key"]
          assert primary_key_columns(prefix, table) == []
      end
    end)

    migrations
    |> Enum.reverse()
    |> Enum.each(fn {module, {version, migration}} ->
      assert [^version] = run_migration(prefix, version, migration, :down)
      refute table_exists?(prefix, module.__schema__(:source))
    end)
  end

  test "belongs-to primary keys stay aligned across Ecto and PostgreSQL", %{prefix: prefix} do
    opts = [migration_path: @migration_path, snapshot_path: @snapshot_path]
    module = Brando.MigrationTest.RelationPrimaryKeyV1
    table = module.__schema__(:source)

    create_dependency_tables!(prefix, ["users"])

    assert module.__schema__(:primary_key) == [:owner_id]
    assert module.__schema__(:field_source, :owner_id) == :owner_ref

    [owner_column] = MigrationSchema.build(module).columns
    assert owner_column.name == :owner_ref
    assert owner_column.opts == %{null: false, primary_key: true}

    assert {:ok, generated} = Migrations.create_migration(module, opts)
    {version, migration} = compiled_migration(generated.migration)

    assert [^version] = run_migration(prefix, version, migration, :up)
    assert column_names(prefix, table) == ["owner_ref"]
    assert primary_key_columns(prefix, table) == ["owner_ref"]
    assert foreign_key(prefix, table, "#{table}_owner_ref_fkey") == ["users", "RESTRICT"]

    assert [^version] = run_migration(prefix, version, migration, :down)
    refute table_exists?(prefix, table)
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

  defp compiled_migration(filename) do
    {migration_version(filename), compile_migration!(filename)}
  end

  defp run_migration(prefix, version, migration, direction) do
    Ecto.Migrator.run(MigrationRepo, [{version, migration}], direction,
      all: true,
      prefix: prefix,
      log: false
    )
  end

  defp create_dependency_tables!(prefix, tables) do
    Enum.each(tables, fn table ->
      Ecto.Adapters.SQL.query!(
        MigrationRepo,
        ~s|CREATE TABLE "#{prefix}"."#{table}" (id bigserial PRIMARY KEY)|,
        []
      )
    end)
  end

  defp table_exists?(prefix, table) do
    %{rows: [[qualified_name]]} =
      Ecto.Adapters.SQL.query!(MigrationRepo, "SELECT to_regclass($1)::text", ["#{prefix}.#{table}"])

    qualified_name == "#{prefix}.#{table}"
  end

  defp column_names(prefix, table) do
    MigrationRepo
    |> Ecto.Adapters.SQL.query!(
      """
      SELECT column_name
      FROM information_schema.columns
      WHERE table_schema = $1 AND table_name = $2
      ORDER BY column_name
      """,
      [prefix, table]
    )
    |> Map.fetch!(:rows)
    |> Enum.map(&hd/1)
  end

  defp column(prefix, table, name) do
    %{rows: [column]} =
      Ecto.Adapters.SQL.query!(
        MigrationRepo,
        """
        SELECT data_type, is_nullable, column_default
        FROM information_schema.columns
        WHERE table_schema = $1 AND table_name = $2 AND column_name = $3
        """,
        [prefix, table, name]
      )

    column
  end

  defp foreign_key(prefix, table, constraint) do
    %{rows: [foreign_key]} =
      Ecto.Adapters.SQL.query!(
        MigrationRepo,
        """
        SELECT target.relname,
               CASE foreign_key.confdeltype
                 WHEN 'a' THEN 'NO ACTION'
                 WHEN 'r' THEN 'RESTRICT'
                 WHEN 'c' THEN 'CASCADE'
                 WHEN 'n' THEN 'SET NULL'
                 WHEN 'd' THEN 'SET DEFAULT'
               END
        FROM pg_constraint AS foreign_key
        JOIN pg_class AS owner ON owner.oid = foreign_key.conrelid
        JOIN pg_namespace AS namespace ON namespace.oid = owner.relnamespace
        JOIN pg_class AS target ON target.oid = foreign_key.confrelid
        WHERE namespace.nspname = $1
          AND owner.relname = $2
          AND foreign_key.conname = $3
        """,
        [prefix, table, constraint]
      )

    foreign_key
  end

  defp index_names(prefix, table) do
    MigrationRepo
    |> Ecto.Adapters.SQL.query!(
      """
      SELECT indexname
      FROM pg_indexes
      WHERE schemaname = $1 AND tablename = $2
      ORDER BY indexname
      """,
      [prefix, table]
    )
    |> Map.fetch!(:rows)
    |> Enum.map(&hd/1)
  end

  defp primary_key_columns(prefix, table) do
    MigrationRepo
    |> Ecto.Adapters.SQL.query!(
      """
      SELECT attribute.attname
      FROM pg_constraint AS primary_key
      JOIN pg_class AS owner ON owner.oid = primary_key.conrelid
      JOIN pg_namespace AS namespace ON namespace.oid = owner.relnamespace
      JOIN unnest(primary_key.conkey) WITH ORDINALITY AS key(attnum, position) ON true
      JOIN pg_attribute AS attribute
        ON attribute.attrelid = owner.oid
       AND attribute.attnum = key.attnum
      WHERE namespace.nspname = $1
        AND owner.relname = $2
        AND primary_key.contype = 'p'
      ORDER BY key.position
      """,
      [prefix, table]
    )
    |> Map.fetch!(:rows)
    |> Enum.map(&hd/1)
  end
end
