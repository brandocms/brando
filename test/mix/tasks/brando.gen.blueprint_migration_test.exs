defmodule Brando.MigrationTest.FixedPrefix do
  use Brando.Blueprint,
    application: "Brando",
    domain: "MigrationTest",
    schema: "FixedPrefix",
    singular: "fixed_prefix",
    plural: "fixed_prefixes"

  @schema_prefix "shared"
  attributes do
    attribute :title, :string
  end
end

defmodule Mix.Tasks.Brando.Gen.BlueprintMigrationTest do
  use ExUnit.Case, async: false

  alias Brando.Blueprint.Snapshot
  alias Mix.Brando.MigrationRequest
  alias Mix.Tasks.Brando.Gen.BlueprintMigration

  setup do
    # Planning checks the database for tables the plan would create.
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Brando.repo())
    Mix.shell(Mix.Shell.Process)
    root = Path.join(System.tmp_dir!(), "brando-mix-migration-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root, migration_path: Path.join(root, "migrations"), snapshot_path: Path.join(root, "snapshots")}
  end

  defp plan(context, flags \\ []) do
    Igniter.Test.test_project()
    |> Igniter.compose_task(BlueprintMigration, [
      "Brando.MigrationTest.ExecutionV1",
      "--migration-path",
      context.migration_path,
      "--snapshot-path",
      context.snapshot_path | flags
    ])
  end

  test "previews exact migration source and queues paired persistence without files", context do
    planned = plan(context, ["--dry-run"])
    assert planned.issues == []
    assert_received {:mix_shell, :info, preview}
    preview = IO.iodata_to_binary(preview)
    assert preview =~ "create table"
    assert preview =~ "version 1"
    refute File.exists?(context.root)
    Igniter.Test.assert_unchanged(planned)
    assert [{"brando.blueprint.apply_plan", [request]}] = planned.tasks
    assert {:ok, metadata} = MigrationRequest.apply(request)
    assert File.exists?(metadata.migration)
    assert File.exists?(metadata.snapshot)
    assert File.read!(metadata.migration) == planned.assigns.brando_storage_plan.migration_source
    rerun = plan(context)
    assert rerun.issues == []
    assert rerun.tasks == []
  end

  describe "legacy snapshot hints" do
    defp plan_for(context, module) do
      Igniter.Test.test_project()
      |> Igniter.compose_task(BlueprintMigration, [
        inspect(module),
        "--dry-run",
        "--migration-path",
        context.migration_path,
        "--snapshot-path",
        context.snapshot_path
      ])
    end

    test "creating a table the database already has points at the legacy snapshot guide", context do
      # The test database has `projects`; there is no snapshot for it here.
      planned = plan_for(context, Brando.MigrationTest.Project)
      assert planned.issues == []
      assert [warning] = Enum.filter(planned.warnings, &(&1 =~ "already exist in the database"))
      assert warning =~ "projects"
      assert warning =~ ~s("Legacy snapshots")

      new_table = plan_for(context, Brando.MigrationTest.ExecutionV1)
      refute Enum.any?(new_table.warnings, &(&1 =~ "already exist"))
    end

    test "adding columns the database already has points at the legacy snapshot guide", context do
      opts = [migration_path: context.migration_path, snapshot_path: context.snapshot_path]
      {:ok, _} = Brando.Blueprint.Migrations.create_migration(Brando.MigrationTest.LegacyProjectV1, opts)

      # The test database's `projects` has the rendered_blocks columns already.
      planned = plan_for(context, Brando.MigrationTest.LegacyProjectV2)
      assert [warning] = Enum.filter(planned.warnings, &(&1 =~ "already exist in the database"))
      assert warning =~ "projects.rendered_blocks, projects.rendered_blocks_at,"
      refute warning =~ "never_added"
      assert warning =~ "add_if_not_exists"
    end

    test "dropping legacy Villain columns points at the legacy snapshot guide", context do
      opts = [migration_path: context.migration_path, snapshot_path: context.snapshot_path]
      {:ok, _} = Brando.Blueprint.Migrations.create_migration(Brando.MigrationTest.VillainV1, opts)

      planned = plan_for(context, Brando.MigrationTest.VillainV2)
      assert [warning] = Enum.filter(planned.warnings, &(&1 =~ "legacy Villain columns"))
      assert warning =~ ":data, :hero_data, :html"
      assert warning =~ ~s("Legacy snapshots")
    end
  end

  test "rebaseline is explicitly reviewed and persists only after acceptance", context do
    planned = plan(context, ["--rebaseline"])
    assert planned.issues == []
    assert_received {:mix_shell, :info, preview}
    preview = IO.iodata_to_binary(preview)
    assert preview =~ "Rebaseline: true"
    refute File.exists?(context.root)
    [{_, [request]}] = planned.tasks
    assert {:ok, metadata} = MigrationRequest.apply(request)
    assert File.exists?(metadata.snapshot)
    refute File.exists?(context.migration_path)

    assert Snapshot.get_latest_snapshot(Brando.MigrationTest.ExecutionV1, snapshot_path: context.snapshot_path).rebaseline?
  end

  test "stale requests cannot write a new migration or snapshot", context do
    planned = plan(context)
    [{_, [request]}] = planned.tasks
    File.mkdir_p!(context.migration_path)
    File.write!(Path.join(context.migration_path, "20000101000000_existing.exs"), "# Added after review")
    assert_raise Mix.Error, ~r/stale/, fn -> MigrationRequest.apply(request) end
    assert length(Path.wildcard(Path.join(context.migration_path, "*.exs"))) == 1
    refute File.exists?(context.snapshot_path)
  end

  test "invalid requests and multiple composed storage plans are rejected", context do
    assert_raise Mix.Error, ~r/Invalid Blueprint/, fn -> MigrationRequest.apply("invalid request") end
    first = plan(context)
    second = Igniter.compose_task(first, BlueprintMigration, ["Brando.MigrationTest.ExecutionV1"])
    assert Enum.any?(second.issues, &String.contains?(&1, "one Blueprint storage plan"))
    refute File.exists?(context.root)
  end

  test "review fingerprints remain valid in the separate Mix process used by Igniter", context do
    planned = plan(context)
    [{_, [request]}] = planned.tasks

    {output, status} =
      System.cmd(
        "mix",
        ["run", "--no-start", "-e", "Mix.Brando.MigrationRequest.apply(System.fetch_env!(\"BRANDO_REVIEWED_REQUEST\"))"],
        env: [{"BRANDO_REVIEWED_REQUEST", request}, {"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert File.exists?(planned.assigns.brando_storage_plan.metadata.migration)
    assert File.exists?(planned.assigns.brando_storage_plan.metadata.snapshot)
  end

  test "new tenant storage defaults to tenant migrations without changing explicit paths", context do
    for mode <- [:none, :single, :multi] do
      project =
        Brando.IgniterCase.phoenix_project(
          files: %{
            "config/brando.exs" => "import Config\nconfig :brando, tenancy_mode: :#{mode}\n"
          }
        )

      result =
        Igniter.compose_task(project, BlueprintMigration, [
          "Brando.MigrationTest.ExecutionV1",
          "--snapshot-path",
          context.snapshot_path
        ])

      assert result.issues == []
      expected = if mode == :none, do: "priv/repo/migrations", else: "priv/repo/tenant_migrations"
      assert Path.dirname(result.assigns.brando_storage_plan.metadata.migration) == expected
      refute File.exists?(result.assigns.brando_storage_plan.metadata.migration)
      refute File.exists?(context.root)

      explicit =
        Igniter.compose_task(project, BlueprintMigration, [
          "Brando.MigrationTest.ExecutionV1",
          "--snapshot-path",
          context.snapshot_path,
          "--migration-path",
          context.migration_path
        ])

      assert explicit.issues == []
      assert Path.dirname(explicit.assigns.brando_storage_plan.metadata.migration) == context.migration_path
    end
  end

  test "custom fixed prefixes need an explicit storage destination", context do
    result = Igniter.Test.test_project() |> Igniter.compose_task(BlueprintMigration, ["Brando.MigrationTest.FixedPrefix"])
    assert Enum.any?(result.issues, &String.contains?(&1, "fixes its schema prefix"))
    assert result.tasks == []
    Igniter.Test.assert_unchanged(result)

    explicit =
      Igniter.Test.test_project()
      |> Igniter.compose_task(BlueprintMigration, [
        "Brando.MigrationTest.FixedPrefix",
        "--migration-path",
        context.migration_path,
        "--snapshot-path",
        context.snapshot_path
      ])

    assert explicit.issues == []
    refute File.exists?(context.root)
  end
end
