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

defmodule Brando.MigrationTest.SharedPublic do
  use Brando.Blueprint,
    application: "Brando",
    domain: "MigrationTest",
    schema: "SharedPublic",
    singular: "shared_public",
    plural: "shared_publics"

  @schema_prefix "public"
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

  describe "--all" do
    alias Brando.Blueprint.Migrations

    defp plan_all(context, modules, flags \\ [], project \\ Igniter.Test.test_project()) do
      project
      |> Igniter.assign(:brando_blueprints, modules)
      |> Igniter.compose_task(BlueprintMigration, ["--all", "--snapshot-path", context.snapshot_path | flags])
    end

    defp previews do
      Stream.repeatedly(fn ->
        receive do
          {:mix_shell, :info, [preview]} -> preview
        after
          0 -> nil
        end
      end)
      |> Enum.take_while(& &1)
      |> Enum.filter(&String.starts_with?(&1, "Blueprint storage plan for"))
    end

    test "plans every changed Blueprint in one review and lists the rest as up to date", context do
      {:ok, _} = Migrations.rebaseline_snapshot(Brando.MigrationTest.StorageV1, snapshot_path: context.snapshot_path)

      planned =
        plan_all(
          context,
          [
            Brando.MigrationTest.Tag,
            Brando.MigrationTest.StorageV1,
            Brando.MigrationTest.ExecutionV1,
            Brando.MigrationTest.Property
          ],
          ["--dry-run"]
        )

      assert planned.issues == []
      plans = planned.assigns.brando_storage_plans
      assert Enum.map(plans, & &1.module) == [Brando.MigrationTest.ExecutionV1, Brando.MigrationTest.Tag]
      assert length(previews()) == 2

      versions = Enum.map(plans, &(&1.metadata.migration |> Path.basename() |> String.split("_", parts: 2) |> hd()))
      assert versions == versions |> Enum.uniq() |> Enum.sort()

      assert [{"brando.blueprint.apply_plan", requests}] = planned.tasks
      assert length(requests) == 2
      assert [summary] = planned.notices
      assert summary =~ "Brando.MigrationTest.ExecutionV1: priv/repo/migrations/#{hd(versions)}_"
      assert summary =~ "Up to date: Brando.MigrationTest.StorageV1"
      assert summary =~ "mix brando.migrate --tenants"
      refute summary =~ "Property"

      Igniter.Test.assert_unchanged(planned)
      refute Enum.any?(plans, &File.exists?(&1.metadata.migration))
      assert Path.wildcard(Path.join(context.snapshot_path, "**/*.snapshot")) |> length() == 1
    end

    test "nothing to plan is a notice and queues no task", context do
      {:ok, _} = Migrations.rebaseline_snapshot(Brando.MigrationTest.StorageV1, snapshot_path: context.snapshot_path)
      planned = plan_all(context, [Brando.MigrationTest.StorageV1])
      assert planned.issues == []
      assert planned.tasks == []
      assert planned.notices == ["No storage changes necessary. Up to date: Brando.MigrationTest.StorageV1."]
    end

    test "each Blueprint keeps the migration path a single run would pick", context do
      project =
        Brando.IgniterCase.phoenix_project(
          files: %{"config/brando.exs" => "import Config\nconfig :brando, tenancy_mode: :multi\n"}
        )

      modules = [Brando.MigrationTest.ExecutionV1, Brando.MigrationTest.SharedPublic, Brando.MigrationTest.FixedPrefix]
      planned = plan_all(context, modules, [], project)

      assert planned.issues == []

      paths =
        Map.new(planned.assigns.brando_storage_plans, &{&1.module, Path.dirname(&1.metadata.migration)})

      assert paths == %{
               Brando.MigrationTest.ExecutionV1 => "priv/repo/tenant_migrations",
               Brando.MigrationTest.SharedPublic => "priv/repo/migrations"
             }

      assert [warning] = Enum.filter(planned.warnings, &(&1 =~ "Left out of --all"))
      assert warning =~ "Brando.MigrationTest.FixedPrefix fixes its schema prefix"

      for module <- [Brando.MigrationTest.ExecutionV1, Brando.MigrationTest.SharedPublic] do
        single =
          Igniter.compose_task(project, BlueprintMigration, [inspect(module), "--snapshot-path", context.snapshot_path])

        assert Path.dirname(single.assigns.brando_storage_plan.metadata.migration) == paths[module]
      end
    end

    test "refuses a Blueprint argument, --migration-path and --rebaseline", context do
      for flags <- [
            ["Brando.MigrationTest.ExecutionV1"],
            ["--migration-path", context.migration_path],
            ["--rebaseline"]
          ] do
        planned = plan_all(context, [Brando.MigrationTest.ExecutionV1], flags)
        assert [issue] = planned.issues
        assert issue =~ "--all"
        assert planned.tasks == []
      end

      refute File.exists?(context.root)
    end

    test "the reviewed requests are written together or not at all", context do
      opts = [migration_path: context.migration_path, snapshot_path: context.snapshot_path]
      {:ok, initial} = Migrations.create_migration(Brando.MigrationTest.Project, opts)
      plans = Migrations.plan_all([{Brando.MigrationTest.ProjectUpdate1, opts}, {Brando.MigrationTest.Tag, opts}])
      requests = Enum.map(plans, &MigrationRequest.encode/1)

      snapshot = Snapshot.get_latest_snapshot(Brando.MigrationTest.Project, opts)
      original = File.read!(initial.snapshot)
      File.write!(initial.snapshot, :erlang.term_to_binary(%{snapshot | updated_at: ~U[2000-01-01 00:00:00Z]}))
      assert_raise Mix.Error, ~r/stale/, fn -> Mix.Tasks.Brando.Blueprint.ApplyPlan.run(requests) end
      assert Path.wildcard(Path.join(context.migration_path, "*.exs")) == [initial.migration]

      File.write!(initial.snapshot, original)
      Mix.Tasks.Brando.Blueprint.ApplyPlan.run(requests)
      assert Enum.all?(plans, &File.exists?(&1.metadata.migration))
      assert Enum.all?(plans, &File.exists?(&1.metadata.snapshot))
      assert_received {:mix_shell, :info, ["Created " <> _]}
    end
  end
end
