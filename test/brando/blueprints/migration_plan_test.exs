defmodule Brando.Blueprint.MigrationPlanTest do
  use ExUnit.Case, async: false

  alias Brando.Blueprint.Migrations
  alias Brando.Blueprint.Snapshot
  alias Brando.Exception.BlueprintError

  setup do
    root = Path.join(System.tmp_dir!(), "brando-migration-plan-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)

    {:ok,
     root: root, options: [migration_path: Path.join(root, "migrations"), snapshot_path: Path.join(root, "snapshots")]}
  end

  test "planning and declining create no files or directories; commit writes the reviewed pair", %{
    root: root,
    options: opts
  } do
    plan = Migrations.plan(Brando.MigrationTest.Project, opts)
    assert plan.migration_source =~ "create table(:projects)"
    assert plan.metadata.snapshot_version == 1
    refute File.exists?(root)
    assert {:ok, metadata} = Migrations.commit_plan(plan)
    assert metadata == plan.metadata
    assert File.read!(metadata.migration) == plan.migration_source
    assert Snapshot.get_latest_snapshot(plan.module, opts) == plan.snapshot
    assert_raise BlueprintError, ~r/changed after planning/, fn -> Migrations.commit_plan(plan) end
  end

  test "an unrelated migration added after review makes the plan stale", %{options: opts} do
    plan = Migrations.plan(Brando.MigrationTest.Project, opts)
    File.mkdir_p!(opts[:migration_path])
    other = Path.join(opts[:migration_path], "20990101000000_custom.exs")
    File.write!(other, "# Preserve this newly generated migration")
    assert_raise BlueprintError, ~r/changed after planning/, fn -> Migrations.commit_plan(plan) end
    assert Path.wildcard(Path.join(opts[:migration_path], "*.exs")) == [other]
    refute File.exists?(plan.metadata.snapshot)
  end

  test "editing an existing snapshot after review invalidates the plan", %{options: opts} do
    {:ok, initial} = Migrations.create_migration(Brando.MigrationTest.Project, opts)
    plan = Migrations.plan(Brando.MigrationTest.ProjectUpdate1, opts)
    snapshot = Snapshot.get_latest_snapshot(Brando.MigrationTest.Project, opts)
    File.write!(initial.snapshot, :erlang.term_to_binary(%{snapshot | updated_at: ~U[2000-01-01 00:00:00Z]}))
    assert_raise BlueprintError, ~r/changed after planning/, fn -> Migrations.commit_plan(plan) end
    refute File.exists?(plan.metadata.migration)
    assert Snapshot.get_snapshot_version(Brando.MigrationTest.Project, opts) == 1
  end

  test "a different compiled schema cannot be substituted after review", %{options: opts} do
    plan = Migrations.plan(Brando.MigrationTest.Project, opts)
    plan = %{plan | module: Brando.MigrationTest.ProjectUpdate1}
    assert_raise BlueprintError, ~r/changed after planning/, fn -> Migrations.commit_plan(plan) end
    refute File.exists?(plan.metadata.migration)
  end

  test "snapshot persistence failure removes the new migration", %{root: root, options: opts} do
    plan = Migrations.plan(Brando.MigrationTest.Project, opts)
    File.mkdir_p!(root)
    File.write!(opts[:snapshot_path], "blocked directory")
    assert_raise File.Error, fn -> Migrations.commit_plan(plan) end
    refute File.exists?(plan.metadata.migration)
    assert File.read!(opts[:snapshot_path]) == "blocked directory"
    assert Path.wildcard(Path.join(opts[:migration_path], "*")) == []
  end

  test "competing reviewed plans cannot reuse a migration version", %{options: opts} do
    first = Migrations.plan(Brando.MigrationTest.Project, opts)
    second = Migrations.plan(Brando.MigrationTest.Tag, opts)
    assert {:ok, _} = Migrations.commit_plan(first)
    assert_raise BlueprintError, ~r/changed after planning/, fn -> Migrations.commit_plan(second) end
    replacement = Migrations.plan(Brando.MigrationTest.Tag, opts)
    assert {:ok, _} = Migrations.commit_plan(replacement)
    assert Path.basename(replacement.metadata.migration) > Path.basename(first.metadata.migration)
  end

  test "rebaseline requires an explicit committed plan and noop leaves history untouched", %{root: root, options: opts} do
    plan = Migrations.plan(Brando.MigrationTest.Project, Keyword.put(opts, :rebaseline, true))
    assert plan.snapshot.rebaseline?
    assert plan.migration_source == nil
    refute File.exists?(root)
    {:ok, metadata} = Migrations.commit_plan(plan)
    before = File.read!(metadata.snapshot)
    noop = Migrations.plan(Brando.MigrationTest.Project, opts)
    assert noop.result == :noop
    assert noop.snapshot == nil
    assert {:noop, _} = Migrations.commit_plan(noop)
    assert File.read!(metadata.snapshot) == before
    refute File.exists?(opts[:migration_path])
  end
end
