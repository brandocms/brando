defmodule Mix.Tasks.Brando.Gen.BlueprintMigrationTest do
  use ExUnit.Case, async: false

  @migration_path "tmp/mix_task_blueprint_migrations"
  @snapshot_path "tmp/mix_task_blueprint_snapshots"

  setup do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    File.rm_rf!(@migration_path)
    File.rm_rf!(@snapshot_path)

    on_exit(fn ->
      Mix.shell(previous_shell)
      File.rm_rf!(@migration_path)
      File.rm_rf!(@snapshot_path)
    end)
  end

  test "generates and reports Blueprint migrations" do
    Mix.Tasks.Brando.Gen.BlueprintMigration.run([
      "Brando.MigrationTest.ExecutionV1",
      "--migration-path",
      @migration_path,
      "--snapshot-path",
      @snapshot_path
    ])

    assert_received {:mix_shell, :info, migration_message}
    assert_received {:mix_shell, :info, snapshot_message}
    assert IO.iodata_to_binary(migration_message) =~ "Created #{@migration_path}/"
    assert IO.iodata_to_binary(snapshot_message) =~ "Created #{@snapshot_path}/"
    assert [_migration] = Path.wildcard(Path.join(@migration_path, "*.exs"))
    assert [_snapshot] = Path.wildcard(Path.join(@snapshot_path, "**/*.snapshot"))
  end

  test "supports explicit snapshot re-baselining" do
    Mix.Tasks.Brando.Gen.BlueprintMigration.run([
      "Brando.MigrationTest.ExecutionV1",
      "--rebaseline",
      "--migration-path",
      @migration_path,
      "--snapshot-path",
      @snapshot_path
    ])

    assert_received {:mix_shell, :info, message}
    assert IO.iodata_to_binary(message) =~ "Re-baselined Brando.MigrationTest.ExecutionV1"
    assert Path.wildcard(Path.join(@migration_path, "*.exs")) == []
    assert [_snapshot] = Path.wildcard(Path.join(@snapshot_path, "**/*.snapshot"))
  end
end
