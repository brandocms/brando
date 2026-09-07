defmodule Brando.Blueprint.MigrationsTest do
  use ExUnit.Case, async: false

  alias Brando.Blueprint.DatabaseIdentifier
  alias Brando.Blueprint.Migrations
  alias Brando.Blueprint.Migrations.Schema, as: MigrationSchema
  alias Brando.Blueprint.Snapshot
  alias Brando.Exception.BlueprintError

  @test_opts [
    migration_path: "tmp/test_migrations",
    snapshot_path: "tmp/test_snapshots"
  ]

  setup do
    File.rm_rf!("tmp/test_snapshots")
    File.rm_rf!("tmp/test_migrations")

    on_exit(fn ->
      File.rm_rf!("tmp/test_snapshots")
      File.rm_rf!("tmp/test_migrations")
    end)
  end

  test "generates ordered, reversible migrations from storage changes" do
    assert {:ok, initial} = Migrations.create_migration(Brando.MigrationTest.Project, @test_opts)
    assert initial.sequence == "001"
    assert initial.snapshot_version == 1
    assert File.exists?(initial.snapshot)

    initial_source = File.read!(initial.migration)

    assert initial_source =~ "create table(:projects)"
    assert initial_source =~ "add :sequence, :integer, default: 0"
    assert initial_source =~ "create index(:projects, [:language]"
    assert initial_source =~ ~s(name: "projects_slug_language_index")

    assert appears_before?(
             initial_source,
             "drop table(:projects_alternates)",
             "drop table(:projects)"
           )

    assert {:ok, update1} = Migrations.create_migration(Brando.MigrationTest.ProjectUpdate1, @test_opts)
    assert update1.sequence == "002"
    assert update1.snapshot_version == 2
    assert {:remove_column, :deleted_at} in update1.destructive_operations

    update1_source = File.read!(update1.migration)
    assert update1_source =~ "remove :deleted_at"
    assert update1_source =~ "add :meta_description, :text"
    assert update1_source =~ "add :photos_id"
    assert update1_source =~ "create unique_index(:projects, [:unique_hash]"

    update1_down_source = down_source(update1_source)

    assert appears_before?(
             update1_down_source,
             "drop index(:projects, [:unique_hash]",
             "alter table(:projects)"
           )

    assert {:ok, update2} = Migrations.create_migration(Brando.MigrationTest.ProjectUpdate2, @test_opts)
    assert update2.sequence == "003"
    assert update2.snapshot_version == 3

    update2_source = File.read!(update2.migration)
    assert update2_source =~ "remove :title"
    assert update2_source =~ "remove :cover_id"
    assert update2_source =~ "drop index(:projects, [:slug, :language]"

    assert appears_before?(
             update2_source,
             "drop index(:projects, [:slug, :language]",
             "alter table(:projects)"
           )

    assert length(Path.wildcard("tmp/test_migrations/*_brando_projects_project_*.exs")) == 3
    assert Snapshot.get_snapshot_version(Brando.MigrationTest.ProjectUpdate2, @test_opts) == 3
  end

  test "does not create files when the storage schema is unchanged" do
    assert {:ok, generated} = Migrations.create_migration(Brando.MigrationTest.Project, @test_opts)
    assert {:noop, noop} = Migrations.create_migration(Brando.MigrationTest.Project, @test_opts)

    assert noop.snapshot_version == 1
    assert Path.wildcard("tmp/test_migrations/*.exs") == [generated.migration]
    assert Path.wildcard("tmp/test_snapshots/**/*", match_dot: true) != []
    assert Snapshot.get_snapshot_version(Brando.MigrationTest.Project, @test_opts) == 1
  end

  test "canonicalizes overlong names in existing snapshots without migration churn" do
    module = Brando.MigrationTest.LongIdentifiers
    assert {:ok, generated} = Migrations.create_migration(module, @test_opts)

    snapshot = generated.snapshot |> File.read!() |> :erlang.binary_to_term()
    table = snapshot.schema.table
    full_unique_name = "#{table}_uniqueness_value_tenant_reference_identifier_index"
    full_foreign_key_name = "#{table}_owner_reference_identifier_id_fkey"

    indexes =
      Enum.map(snapshot.schema.indexes, fn
        %{unique: true} = index -> %{index | name: full_unique_name}
        index -> index
      end)

    columns =
      Enum.map(snapshot.schema.columns, fn
        %{name: :owner_reference_identifier_id, reference: reference} = column ->
          %{column | reference: %{reference | name: full_foreign_key_name}}

        column ->
          column
      end)

    overlong_snapshot = %{snapshot | schema: %{snapshot.schema | indexes: indexes, columns: columns}}
    File.write!(generated.snapshot, :erlang.term_to_binary(overlong_snapshot, compressed: 6))

    assert {:noop, %{snapshot_version: 1}} = Migrations.create_migration(module, @test_opts)
    assert Path.wildcard("tmp/test_migrations/*.exs") == [generated.migration]

    canonical_snapshot = Snapshot.get_latest_snapshot(module, @test_opts)
    unique_index = Enum.find(canonical_snapshot.schema.indexes, & &1.unique)
    owner_column = Enum.find(canonical_snapshot.schema.columns, &(&1.name == :owner_reference_identifier_id))

    assert unique_index.name == DatabaseIdentifier.normalize(full_unique_name)
    assert owner_column.reference.name == DatabaseIdentifier.normalize(full_foreign_key_name)
  end

  test "migration schemas use Ecto physical sources throughout the storage contract" do
    module = Brando.MigrationTest.PhysicalSources
    schema = MigrationSchema.build(module)

    assert module.__schema__(:field_source, :id) == :record_pk
    assert module.__schema__(:field_source, :title) == :headline
    assert module.__schema__(:field_source, :tenant_id) == :account_ref
    assert module.__schema__(:field_source, :owner_id) == :owner_ref
    assert module.__schema__(:field_source, :metadata) == :payload

    assert schema.primary_key == %{name: :record_pk, type: :id}
    assert Enum.map(schema.columns, & &1.name) == [:account_ref, :headline, :owner_ref, :payload]

    assert Enum.any?(schema.indexes, &(&1.fields == [:headline, :account_ref] and &1.unique))
    assert Enum.any?(schema.indexes, &(&1.fields == [:owner_ref, :account_ref] and &1.unique))

    changeset = module.changeset(struct(module), %{})
    runtime_constraint_names = MapSet.new(changeset.constraints, & &1.constraint)

    assert Enum.all?(schema.indexes, &MapSet.member?(runtime_constraint_names, &1.name))

    owner_column = Enum.find(schema.columns, &(&1.name == :owner_ref))
    assert owner_column.opts == %{null: false}
    assert owner_column.reference.on_delete == :restrict
    assert owner_column.reference.prefix == "public"
    assert MapSet.member?(runtime_constraint_names, owner_column.reference.name)

    [related_entries] = schema.auxiliary_tables
    parent_column = Enum.find(related_entries.columns, &(&1.name == :parent_id))
    assert parent_column.reference.column == :record_pk

    assert {:ok, generated} = Migrations.create_migration(module, @test_opts)
    source = File.read!(generated.migration)

    assert source =~ "create table(:#{schema.table}, primary_key: false)"
    assert source =~ "add :record_pk, :bigserial, primary_key: true"
    assert source =~ "add :headline, :text"
    assert source =~ "add :owner_ref,"
    assert source =~ "references(:users,"
    assert source =~ "on_delete: :restrict"
    assert source =~ ~s(prefix: "public")
    assert source =~ "add :payload, :jsonb"
    assert source =~ "column: :record_pk"
    refute source =~ "add :title,"
    refute source =~ "add :owner_id,"
  end

  test "legacy snapshots can explicitly qualify shared references with a reversible migration" do
    module = Brando.MigrationTest.PhysicalSources
    {:ok, initial} = Migrations.create_migration(module, @test_opts)
    snapshot = Snapshot.get_latest_snapshot(module, @test_opts)

    columns =
      Enum.map(snapshot.schema.columns, fn
        %{reference: %{prefix: _} = reference} = column -> %{column | reference: Map.delete(reference, :prefix)}
        column -> column
      end)

    legacy = %{snapshot | schema: %{snapshot.schema | columns: columns}}
    File.write!(initial.snapshot, :erlang.term_to_binary(legacy))

    {:ok, updated} = Migrations.create_migration(module, @test_opts)
    source = File.read!(updated.migration)
    assert source =~ ~s(prefix: "public")
    refute down_source(source) =~ ~s(prefix: "public")
    assert {:noop, _} = Migrations.create_migration(module, @test_opts)
  end

  test "migration schemas dump enum defaults and custom types to database representations" do
    module = Brando.MigrationTest.FieldOptions
    schema = MigrationSchema.build(module)
    columns = Map.new(schema.columns, &{&1.name, &1})

    assert columns.visibility.type == :text
    assert columns.visibility.opts == %{default: "private", null: false}
    assert columns.priority.type == :integer
    assert columns.priority.opts == %{default: 1, null: false}
    assert columns.formats.type == {:array, :text}
    assert columns.formats.opts == %{default: ["jpg"], null: false}
    assert columns.native_formats.type == {:array, :text}
    assert columns.native_formats.opts == %{default: ["png"], null: false}

    assert columns.amount.type == :decimal
    assert columns.amount.opts == %{default: "1.2500", null: false, precision: 12, scale: 4}
    assert columns.module_name.type == :string
    assert columns.module_name.opts.default == Atom.to_string(module)
    assert columns.payload.type == :map
    assert columns.payload.opts.default == %{}
    assert columns.published_on.type == :date
    assert columns.published_on.opts.default == "2026-01-02"

    assert {:ok, generated} = Migrations.create_migration(module, @test_opts)
    source = File.read!(generated.migration)

    assert source =~ "add :visibility, :text"
    assert source =~ ~s(default: "private")
    assert source =~ "add :priority, :integer"
    assert source =~ "add :formats, {:array, :text}"
    assert source =~ "add :amount, :decimal"
    assert source =~ "precision: 12"
    assert source =~ "scale: 4"
    assert source =~ "add :module_name, :string"
    assert source =~ "add :payload, :map"
    refute source =~ "Ecto.Enum"
    refute source =~ "Brando.Type.Module"
    refute source =~ "Brando.Type.Json"
  end

  test "relation primary-key shape changes require a hand-written migration" do
    assert {:ok, generated} =
             Migrations.create_migration(Brando.MigrationTest.RelationPrimaryKeyV1, @test_opts)

    source = File.read!(generated.migration)
    assert source =~ "add :owner_ref"
    assert source =~ "references(:users"
    assert source =~ "null: false"
    assert source =~ "primary_key: true"

    assert_raise BlueprintError, ~r/changed its relation primary-key columns from \[:owner_ref\] to \[\]/, fn ->
      Migrations.create_migration(Brando.MigrationTest.RelationPrimaryKeyV2, @test_opts)
    end
  end

  test "embedded Blueprints have no storage to diff and are refused" do
    assert_raise BlueprintError, ~r/declares `data_layer :embedded`/, fn ->
      Migrations.create_migration(Brando.MigrationTest.Property, @test_opts)
    end

    assert_raise BlueprintError, ~r/declares `data_layer :embedded`/, fn ->
      Migrations.rebaseline_snapshot(Brando.MigrationTest.Property, @test_opts)
    end

    # nothing was written for a Blueprint that owns no table
    refute File.exists?("tmp/test_migrations")
    refute File.exists?("tmp/test_snapshots/brando_projects_property")
  end

  # `function_exported?/3` reports on the loaded module and will not load it, so an
  # unloaded Blueprint answered "not embedded" and walked straight past the guard.
  # Whether it happened to be loaded depended on what ran before it.
  test "an embedded Blueprint is recognized even when its module is not loaded yet" do
    :code.purge(Brando.MigrationTest.Property)
    :code.delete(Brando.MigrationTest.Property)
    refute :erlang.module_loaded(Brando.MigrationTest.Property)

    assert Brando.Blueprint.embedded?(Brando.MigrationTest.Property)
  end

  # A Blueprint compiled against an older Brando has no `__data_layer__/0`, and a
  # guard keyed on that function alone silently lets it through — which is exactly
  # the situation during an upgrade, when these generators get used.
  test "embedded Blueprints are recognized from the compiled Ecto schema" do
    assert Brando.Blueprint.embedded?(Brando.MigrationTest.Property)
    assert is_nil(Brando.MigrationTest.Property.__schema__(:source))

    refute Brando.Blueprint.embedded?(Brando.MigrationTest.Project)
    assert Brando.MigrationTest.Project.__schema__(:source)
  end

  test "migration schemas reduce existing parameterized and custom Ecto types" do
    ref_schema = MigrationSchema.build(Brando.Content.Ref)
    ref_data = Enum.find(ref_schema.columns, &(&1.name == :data))
    assert ref_data.type == :map

    block_schema = MigrationSchema.build(Brando.Content.Block)
    source = Enum.find(block_schema.columns, &(&1.name == :source))
    identifier_metas = Enum.find(block_schema.columns, &(&1.name == :identifier_metas))

    assert source.type == :string
    assert identifier_metas.type == :map
  end

  test "define_field false attaches a foreign key to its declared physical column" do
    schema = MigrationSchema.build(Brando.MigrationTest.ManualPhysicalForeignKey)

    assert [column] = schema.columns
    assert column.name == :owner_ref
    assert column.reference.table == "users"

    assert column.reference.name ==
             DatabaseIdentifier.foreign_key_name(schema.table, :owner_ref)
  end

  test "primary_key false creates a table without an implicit id" do
    module = Brando.MigrationTest.NoPrimaryKey
    assert MigrationSchema.build(module).primary_key == false
    assert {:ok, generated} = Migrations.create_migration(module, @test_opts)

    source = File.read!(generated.migration)
    assert source =~ "create table(:#{module.__schema__(:source)}, primary_key: false)"
    refute source =~ "add :id,"
  end

  test "physical source changes use rename_from as a database column hint" do
    assert {:ok, _initial} = Migrations.create_migration(Brando.MigrationTest.PhysicalSourceV1, @test_opts)
    assert {:ok, update} = Migrations.create_migration(Brando.MigrationTest.PhysicalSourceV2, @test_opts)

    source = File.read!(update.migration)
    assert source =~ "rename table(:blueprint_physical_source_renames), :title, to: :headline"
    assert source =~ "rename table(:blueprint_physical_source_renames), :headline, to: :title"
    assert source =~ "blueprint_physical_source_renames_headline_index"
  end

  test "format-2 snapshots upgrade without migration churn" do
    module = Brando.MigrationTest.Project
    current = Snapshot.build_snapshot(module, 1)

    format_2_schema = %{
      current.schema
      | format_version: 2,
        primary_key: current.schema.primary_key.type
    }

    format_2_snapshot = %{
      current
      | format_version: 2,
        schema: format_2_schema
    }

    write_snapshot(module, 1, format_2_snapshot)
    File.mkdir_p!(@test_opts[:migration_path])

    File.write!(
      Path.join(@test_opts[:migration_path], "20260101000000_blueprint_brando_projects_project_001.exs"),
      "# matching format-2 migration"
    )

    assert {:noop, %{snapshot_version: 1}} = Migrations.create_migration(module, @test_opts)

    upgraded = snapshot_filename(module, 1) |> File.read!() |> :erlang.binary_to_term([:safe])
    assert upgraded.format_version == 3
    assert upgraded.migrated_from_format == nil
    assert upgraded.schema.primary_key == %{name: :id, type: :id}
  end

  test "a unique language attribute emits one unique index" do
    module = Brando.MigrationTest.UniqueLanguage
    schema = MigrationSchema.build(module)

    assert [%{fields: [:language], unique: true}] = schema.indexes
    assert {:ok, generated} = Migrations.create_migration(module, @test_opts)

    source = File.read!(generated.migration)
    assert length(Regex.scan(~r/create unique_index\([^\n]+\[:language\]/, source)) == 1
    refute source =~ "create index("
  end

  test "generated index names that collide after PostgreSQL normalization stop generation" do
    module = Brando.MigrationTest.CollidingIndexNames
    table = module.__schema__(:source)

    alpha_name = DatabaseIdentifier.index_name(table, [:extremely_long_shared_prefix_alpha])
    beta_name = DatabaseIdentifier.index_name(table, [:extremely_long_shared_prefix_beta])

    assert alpha_name == beta_name

    assert_raise BlueprintError, ~r/duplicate_names.*database_indexes.*#{alpha_name}/s, fn ->
      Migrations.create_migration(module, @test_opts)
    end

    assert Path.wildcard("tmp/test_migrations/*.exs") == []
    assert Path.wildcard("tmp/test_snapshots/**/*.snapshot") == []
  end

  test "duplicate foreign-key constraint names stop generation" do
    module = Brando.MigrationTest.CollidingForeignKeyNames

    assert_raise BlueprintError, ~r/duplicate_names.*references.*duplicate_owner_fkey/s, fn ->
      Migrations.create_migration(module, @test_opts)
    end

    assert Path.wildcard("tmp/test_migrations/*.exs") == []
    assert Path.wildcard("tmp/test_snapshots/**/*.snapshot") == []
  end

  test "stored snapshots reject colliding database index names across tables" do
    module = Brando.MigrationTest.Project
    snapshot = Snapshot.build_snapshot(module, 1)
    [owner_index | _] = snapshot.schema.indexes
    [auxiliary_table | remaining_tables] = snapshot.schema.auxiliary_tables
    [auxiliary_index | remaining_indexes] = auxiliary_table.indexes

    colliding_auxiliary_index = %{auxiliary_index | name: owner_index.name}

    colliding_table = %{
      auxiliary_table
      | indexes: [colliding_auxiliary_index | remaining_indexes]
    }

    colliding_schema = %{
      snapshot.schema
      | auxiliary_tables: [colliding_table | remaining_tables]
    }

    write_snapshot(module, 1, %{snapshot | schema: colliding_schema})

    assert_raise BlueprintError, ~r/duplicate_names.*database_indexes.*#{owner_index.name}/s, fn ->
      Snapshot.get_latest_snapshot(module, @test_opts)
    end
  end

  test "stored snapshots reject duplicate foreign-key names within a table" do
    module = Brando.MigrationTest.Project
    snapshot = Snapshot.build_snapshot(module, 1)

    [first_reference, second_reference | _] =
      snapshot.schema.columns
      |> Enum.filter(& &1.reference)
      |> Enum.map(& &1.reference)

    columns =
      Enum.map(snapshot.schema.columns, fn
        %{reference: %{name: name} = reference} = column when name == second_reference.name ->
          %{column | reference: %{reference | name: first_reference.name}}

        column ->
          column
      end)

    write_snapshot(module, 1, %{snapshot | schema: %{snapshot.schema | columns: columns}})

    assert_raise BlueprintError, ~r/duplicate_names.*references.*#{first_reference.name}/s, fn ->
      Snapshot.get_latest_snapshot(module, @test_opts)
    end
  end

  test "serializes concurrent generators across a migration directory" do
    results =
      [Brando.MigrationTest.Project, Brando.MigrationTest.Tag]
      |> Task.async_stream(&Migrations.create_migration(&1, @test_opts),
        max_concurrency: 2,
        ordered: false,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, _}, &1))

    versions =
      Enum.map(results, fn {:ok, metadata} ->
        metadata.migration
        |> Path.basename()
        |> String.split("_", parts: 2)
        |> hd()
      end)

    assert length(Enum.uniq(versions)) == 2
    assert length(Path.wildcard("tmp/test_migrations/*.exs")) == 2
  end

  test "renders rename and type changes in both directions" do
    assert {:ok, _} = Migrations.create_migration(Brando.MigrationTest.StorageV1, @test_opts)
    assert {:ok, update} = Migrations.create_migration(Brando.MigrationTest.StorageV2, @test_opts)

    source = File.read!(update.migration)

    assert source =~ "rename table(:storage_storage_records), :legacy_title, to: :title"
    assert source =~ "modify :title, :integer"
    assert source =~ "modify :title, :text"
    assert source =~ "rename table(:storage_storage_records), :title, to: :legacy_title"

    assert appears_before?(source, "modify :title, :text", "to: :legacy_title")

    assert {:noop, _} = Migrations.create_migration(Brando.MigrationTest.StorageV2, @test_opts)
  end

  test "join table foreign keys use deterministic delete behavior and names" do
    assert {:ok, _} = Migrations.create_migration(Brando.MigrationTest.Tag, @test_opts)
    assert {:ok, generated} = Migrations.create_migration(Brando.MigrationTest.ProjectTag, @test_opts)

    source = File.read!(generated.migration)

    assert source =~ "references(:projects,"
    assert source =~ "references(:projects_tags,"
    assert length(Regex.scan(~r/on_delete: :delete_all/, source)) == 2
    assert source =~ "projects_project_tags_project_id_fkey"
    assert source =~ "projects_project_tags_tag_id_fkey"
  end

  test "UUID owners propagate their key type to foreign and auxiliary tables" do
    on_exit(fn -> Code.ensure_loaded!(Brando.MigrationTest.Profile) end)

    :code.purge(Brando.MigrationTest.Profile)
    :code.delete(Brando.MigrationTest.Profile)
    refute Code.loaded?(Brando.MigrationTest.Profile)

    assert {:ok, generated} = Migrations.create_migration(Brando.Persons.Person, @test_opts)
    assert Code.loaded?(Brando.MigrationTest.Profile)

    source = File.read!(generated.migration)

    assert source =~ "create table(:persons, primary_key: false)"
    assert source =~ "add :id, :uuid, primary_key: true"
    assert source =~ "add :profile_id"
    assert source =~ "add :parent_id"
    assert source =~ "add :entry_id"
    assert length(Regex.scan(~r/type: :uuid/, source)) == 4
  end

  test "refuses to continue when migrations and snapshots have diverged" do
    File.mkdir_p!(@test_opts[:migration_path])

    File.write!(
      Path.join(@test_opts[:migration_path], "20260101000000_blueprint_brando_projects_project_001.exs"),
      "# existing migration"
    )

    assert_raise BlueprintError, ~r/missing its snapshot/, fn ->
      Migrations.create_migration(Brando.MigrationTest.Project, @test_opts)
    end

    File.rm_rf!(@test_opts[:migration_path])
    {:ok, _} = Snapshot.store_snapshot(Brando.MigrationTest.Project, @test_opts)

    assert_raise BlueprintError, ~r/missing its migration files/, fn ->
      Migrations.create_migration(Brando.MigrationTest.Project, @test_opts)
    end
  end

  test "corrupt snapshots stop generation instead of resetting history" do
    snapshot = Snapshot.build_snapshot(Brando.MigrationTest.Project, 1)
    {:ok, filename} = Snapshot.store_snapshot(snapshot, Brando.MigrationTest.Project, @test_opts)
    File.write!(filename, "not an external term")

    assert_raise BlueprintError, ~r/Could not decode Blueprint snapshot/, fn ->
      Migrations.create_migration(Brando.MigrationTest.Project, @test_opts)
    end

    assert Path.wildcard("tmp/test_migrations/*.exs") == []
  end

  test "executable snapshot terms stop generation" do
    module = Brando.MigrationTest.Project
    filename = snapshot_filename(module, 1)
    File.mkdir_p!(Path.dirname(filename))
    File.write!(filename, :erlang.term_to_binary(fn -> :not_allowed end))

    assert_raise BlueprintError, ~r/Could not decode Blueprint snapshot/, fn ->
      Migrations.create_migration(module, @test_opts)
    end

    assert Path.wildcard("tmp/test_migrations/*.exs") == []
  end

  test "unsupported snapshot formats stop generation" do
    module = Brando.MigrationTest.Project
    snapshot = %{Snapshot.build_snapshot(module, 1) | format_version: 4}
    filename = write_snapshot(module, 1, snapshot)

    assert_raise BlueprintError, ~r/Unsupported Blueprint snapshot format: 4/, fn ->
      Snapshot.get_latest_snapshot(module, @test_opts)
    end

    assert File.exists?(filename)
    assert Path.wildcard("tmp/test_migrations/*.exs") == []
  end

  test "malformed normalized snapshot schemas stop generation" do
    module = Brando.MigrationTest.Project
    snapshot = %{Snapshot.build_snapshot(module, 1) | schema: %{format_version: 3}}
    write_snapshot(module, 1, snapshot)

    assert_raise BlueprintError, ~r/Invalid Blueprint snapshot.*missing_field.*table/s, fn ->
      Migrations.create_migration(module, @test_opts)
    end

    assert Path.wildcard("tmp/test_migrations/*.exs") == []
  end

  test "snapshot filenames and embedded versions must agree" do
    module = Brando.MigrationTest.Project
    snapshot = Snapshot.build_snapshot(module, 1)
    write_snapshot(module, 2, snapshot)

    assert_raise BlueprintError, ~r/snapshot_version_mismatch.*2.*1/s, fn ->
      Snapshot.get_latest_snapshot(module, @test_opts)
    end
  end

  test "invalid normalized snapshot metadata stops generation" do
    module = Brando.MigrationTest.Project

    for {field, value, expected_error} <- [
          {:rebaseline?, :yes, "invalid_rebaseline"},
          {:migrated_from_format, 0, "invalid_migrated_from_format"},
          {:updated_at, nil, "invalid_updated_at"}
        ] do
      snapshot = module |> Snapshot.build_snapshot(1) |> Map.put(field, value)
      filename = write_snapshot(module, 1, snapshot)

      assert_raise BlueprintError, ~r/#{expected_error}/, fn ->
        Migrations.create_migration(module, @test_opts)
      end

      File.rm!(filename)
    end

    assert Path.wildcard("tmp/test_migrations/*.exs") == []
  end

  test "prepared snapshots reject invalid storage column options before writing" do
    module = Brando.MigrationTest.Project
    snapshot = Snapshot.build_snapshot(module, 1)
    [column | columns] = snapshot.schema.columns

    for {option, value} <- [
          default: fn -> :not_allowed end,
          null: :yes,
          precision: 0,
          primary_key: :yes,
          scale: -1
        ] do
      invalid_column = put_in(column, [:opts, option], value)
      invalid_snapshot = put_in(snapshot.schema.columns, [invalid_column | columns])

      assert_raise BlueprintError, ~r/invalid_field.*opts/s, fn ->
        Snapshot.store_snapshot(invalid_snapshot, module, @test_opts)
      end

      refute File.exists?(snapshot_filename(module, 1))
    end
  end

  test "prepared snapshots reject columns that collide with generated timestamps" do
    module = Brando.MigrationTest.Project
    snapshot = Snapshot.build_snapshot(module, 1)
    [column | columns] = snapshot.schema.columns
    invalid_snapshot = put_in(snapshot.schema.columns, [%{column | name: :inserted_at} | columns])

    assert_raise BlueprintError, ~r/duplicate_names.*columns.*inserted_at/s, fn ->
      Snapshot.store_snapshot(invalid_snapshot, module, @test_opts)
    end

    refute File.exists?(snapshot_filename(module, 1))
  end

  test "explicit re-baselining records current state without inventing a migration" do
    assert {:ok, metadata} = Migrations.rebaseline_snapshot(Brando.MigrationTest.Project, @test_opts)

    assert metadata.snapshot_version == 1
    assert File.exists?(metadata.snapshot)
    assert Path.wildcard("tmp/test_migrations/*.exs") == []
    assert {:noop, _} = Migrations.create_migration(Brando.MigrationTest.Project, @test_opts)
  end

  test "legacy snapshots upgrade in place when storage is unchanged" do
    module = Brando.MigrationTest.Project
    snapshot_directory = Snapshot.build_path(module, @test_opts)
    snapshot_filename = Path.join(snapshot_directory, "001.snapshot")
    File.mkdir_p!(snapshot_directory)

    legacy = %Snapshot{
      format_version: nil,
      schema: nil,
      version: 1,
      updated_at: DateTime.utc_now(),
      attributes: Brando.Blueprint.Attributes.__attributes__(module),
      assets: Brando.Blueprint.Assets.__assets__(module),
      relations: Brando.Blueprint.Relations.__relations__(module),
      traits: module.__traits__()
    }

    File.write!(snapshot_filename, :erlang.term_to_binary(legacy))
    File.mkdir_p!(@test_opts[:migration_path])

    File.write!(
      Path.join(@test_opts[:migration_path], "20260101000000_blueprint_brando_projects_project_001.exs"),
      "# matching legacy migration"
    )

    assert {:noop, _} = Migrations.create_migration(module, @test_opts)

    upgraded = snapshot_filename |> File.read!() |> :erlang.binary_to_term([:safe])
    assert upgraded.format_version == 3
    assert upgraded.migrated_from_format == nil
    assert is_map(upgraded.schema)
    assert upgraded.attributes == nil
  end

  test "source-controlled legacy snapshots with retired declaration atoms remain readable" do
    assert %Snapshot{
             format_version: 3,
             migrated_from_format: 1,
             version: 1
           } =
             Snapshot.get_latest_snapshot(Brando.Videos.Video,
               snapshot_path: "priv/blueprints/snapshots"
             )
  end

  test "table and primary-key changes require a hand-written migration" do
    assert {:ok, _} = Migrations.create_migration(Brando.MigrationTest.StorageV1, @test_opts)

    assert_raise BlueprintError, ~r/changed its table/, fn ->
      Migrations.create_migration(Brando.MigrationTest.StorageTableV2, @test_opts)
    end

    assert_raise BlueprintError, ~r/changed its primary key/, fn ->
      Migrations.create_migration(Brando.MigrationTest.StorageUuidV2, @test_opts)
    end

    assert length(Path.wildcard("tmp/test_migrations/*.exs")) == 1
    assert Snapshot.get_snapshot_version(Brando.MigrationTest.StorageV1, @test_opts) == 1
  end

  defp appears_before?(source, first, second) do
    first_position = source |> :binary.match(first) |> elem(0)
    second_position = source |> :binary.match(second) |> elem(0)
    first_position < second_position
  end

  defp down_source(source) do
    source
    |> String.split("def down")
    |> List.last()
  end

  defp write_snapshot(module, version, snapshot) do
    filename = snapshot_filename(module, version)
    File.mkdir_p!(Path.dirname(filename))
    File.write!(filename, :erlang.term_to_binary(snapshot))
    filename
  end

  defp snapshot_filename(module, version) do
    directory = Snapshot.build_path(module, @test_opts)
    Path.join(directory, "#{String.pad_leading(to_string(version), 3, "0")}.snapshot")
  end
end
