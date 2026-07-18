defmodule Brando.Blueprint.MigrationsTest do
  use ExUnit.Case, async: false

  alias Brando.Blueprint.Migrations
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
    snapshot = %{Snapshot.build_snapshot(module, 1) | format_version: 3}
    filename = write_snapshot(module, 1, snapshot)

    assert_raise BlueprintError, ~r/Unsupported Blueprint snapshot format: 3/, fn ->
      Snapshot.get_latest_snapshot(module, @test_opts)
    end

    assert File.exists?(filename)
    assert Path.wildcard("tmp/test_migrations/*.exs") == []
  end

  test "malformed normalized snapshot schemas stop generation" do
    module = Brando.MigrationTest.Project
    snapshot = %{Snapshot.build_snapshot(module, 1) | schema: %{format_version: 2}}
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

  test "prepared snapshots reject non-storage column options before writing" do
    module = Brando.MigrationTest.Project
    snapshot = Snapshot.build_snapshot(module, 1)
    [column | columns] = snapshot.schema.columns
    invalid_column = put_in(column, [:opts, :default], fn -> :not_allowed end)
    invalid_snapshot = put_in(snapshot.schema.columns, [invalid_column | columns])

    assert_raise BlueprintError, ~r/invalid_field.*opts/s, fn ->
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
    assert upgraded.format_version == 2
    assert upgraded.migrated_from_format == nil
    assert is_map(upgraded.schema)
    assert upgraded.attributes == nil
  end

  test "source-controlled legacy snapshots with retired declaration atoms remain readable" do
    assert %Snapshot{
             format_version: 2,
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
