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

  # The fingerprint a request carried before --reconcile existed, so a request
  # reviewed on the earlier version still applies after the upgrade.
  test "a plan without --reconcile keeps its earlier fingerprint", context do
    plan = plan(context, ["--dry-run"]).assigns.brando_storage_plan

    options =
      plan.options
      |> Keyword.delete(:planned_migration_version)
      |> Keyword.put(:rebaseline, plan.options[:rebaseline] || false)
      |> Enum.sort()

    earlier =
      %{plan | snapshot: %{plan.snapshot | updated_at: nil}, options: options}
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    assert Brando.Blueprint.Migrations.plan_digest(plan) == earlier

    assert Brando.Blueprint.Migrations.plan_digest(%{plan | options: Keyword.put(plan.options, :reconcile, false)}) ==
             earlier
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

  # The legacy tables are created inside the test's sandbox transaction, and the
  # generated migrations run on its connection; Postgres DDL is transactional,
  # so the sandbox undoes all of it.
  describe "--reconcile" do
    alias Brando.Blueprint.Migrations

    alias Brando.MigrationTest.{
      ReconcileArticleV1,
      ReconcileArticleV2,
      ReconcileArticleV3,
      ReconcileFarm,
      ReconcileFarmV2
    }

    defp query!(sql, params \\ []), do: Brando.repo().query!(sql, params, log: false)

    defp columns(table) do
      query!(
        "SELECT column_name::text FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1 ORDER BY 1",
        [table]
      ).rows
      |> List.flatten()
    end

    defp indexes(table) do
      query!("SELECT indexname::text FROM pg_indexes WHERE schemaname = 'public' AND tablename = $1 ORDER BY 1", [table]).rows
      |> List.flatten()
    end

    defp table?(table), do: query!("SELECT to_regclass($1) IS NOT NULL", [table]).rows == [[true]]

    # The migration's comments as one line; the generator wraps them.
    defp comments(source) do
      for "#" <> line <- source |> String.split("\n") |> Enum.map(&String.trim/1), into: "", do: line
    end

    # `reconcile_articles` as a legacy site has it: the blocks conversion and
    # the Translatable trait came after the snapshot, the Creator trait's
    # `creator_id` was added by hand with its foreign key, and the alternates
    # table exists without its unique index.
    defp create_legacy_articles do
      query!("""
      CREATE TABLE reconcile_articles (
        id bigserial PRIMARY KEY,
        title text,
        data jsonb,
        html text,
        link text,
        stale text,
        rendered_blocks text,
        language text,
        creator_id bigint CONSTRAINT reconcile_articles_creator_id_fkey REFERENCES public.users (id),
        inserted_at timestamp(0) NOT NULL DEFAULT now(),
        updated_at timestamp(0) NOT NULL DEFAULT now()
      )
      """)

      query!("CREATE INDEX reconcile_articles_language_index ON reconcile_articles (language)")

      query!("""
      CREATE TABLE reconcile_articles_alternates (
        id bigserial PRIMARY KEY,
        entry_id bigint REFERENCES reconcile_articles (id) ON DELETE CASCADE,
        linked_entry_id bigint REFERENCES reconcile_articles (id) ON DELETE CASCADE,
        inserted_at timestamp(0) NOT NULL,
        updated_at timestamp(0) NOT NULL
      )
      """)

      query!("""
      INSERT INTO reconcile_articles (title, data, link)
      VALUES ('First', '{"blocks": []}', 'https://example.com'), ('Second', '{}', NULL)
      """)
    end

    # `reconcile_farms` from before Blueprint snapshots: no Creator trait
    # columns but a hand-added `creator_id` without its foreign key, and no slug index.
    defp create_legacy_farms do
      query!("""
      CREATE TABLE reconcile_farms (
        id bigserial PRIMARY KEY,
        title text,
        slug text,
        creator_id bigint,
        inserted_at timestamp(0) NOT NULL DEFAULT now(),
        updated_at timestamp(0) NOT NULL DEFAULT now()
      )
      """)

      query!("INSERT INTO reconcile_farms (title, slug) VALUES ('Farm', 'farm')")
    end

    defp reconcile(context, module, flags \\ []) do
      Igniter.Test.test_project()
      |> Igniter.compose_task(BlueprintMigration, [
        inspect(module),
        "--reconcile",
        "--migration-path",
        context.migration_path,
        "--snapshot-path",
        context.snapshot_path | flags
      ])
    end

    # Runs `fun` with the migration compiled, after running its up/0.
    defp migrate_up(source, fun) do
      [{module, _}] = Code.compile_string(source)
      repo = Brando.repo()
      run = &Ecto.Migration.Runner.run(repo, repo.config(), 1, module, :forward, &1, &1, log: false)

      try do
        run.(:up)
        fun.(fn -> run.(:down) end)
      after
        :code.purge(module)
        :code.delete(module)
      end
    end

    test "fits a legacy snapshot's plan to the tables, columns and indexes the database has", context do
      opts = [migration_path: context.migration_path, snapshot_path: context.snapshot_path]
      {:ok, _} = Migrations.create_migration(ReconcileArticleV1, opts)
      create_legacy_articles()
      legacy_columns = columns("reconcile_articles")

      planned = reconcile(context, ReconcileArticleV2, ["--dry-run"])
      assert planned.issues == []
      plan = planned.assigns.brando_storage_plan
      [up, down] = String.split(plan.migration_source, "def down do")

      # Existing columns and indexes are guarded; existing ones with a foreign
      # key are left out, since PostgreSQL would add the constraint again.
      assert up =~ "add_if_not_exists :language, :text"
      assert up =~ "add_if_not_exists :rendered_blocks, :text"
      assert up =~ "add :summary, :text"
      assert up =~ "add :edited_at, :utc_datetime"
      assert up =~ ~r/add :updated_by_id,\s+references\(:users/
      refute plan.migration_source =~ ":creator_id"
      assert up =~ ~r/create_if_not_exists index\(:reconcile_articles, \[:language\]/
      assert up =~ "create_if_not_exists table(:reconcile_articles_alternates)"
      assert up =~ ~r/create unique_index\(:reconcile_articles_alternates/

      # Only a column without data is dropped; the drop of one the database
      # never had is left out.
      assert up =~ "remove :stale"

      for column <- [:data, :html, :link, :never_created],
          do: refute(plan.migration_source =~ "remove #{inspect(column)}")

      comments = comments(plan.migration_source)
      [[database]] = query!("SELECT current_database()").rows

      assert comments =~
               "Reconciled against #{inspect(Brando.repo())}, database #{database} (schemas: public)."

      assert comments =~
               "reconcile_articles.link holds 1 value, so this migration keeps it. Dropping it is a separate decision."

      assert comments =~
               "reconcile_articles.data is a legacy Villain column holding 2 values; --reconcile never drops it."

      assert comments =~ "reconcile_articles.html is a legacy Villain column holding 0 values"

      assert comments =~
               "reconcile_articles.creator_id already exists with its foreign key, so this migration leaves it out."

      # down/0 undoes only what up/0 added.
      assert down =~ ~r/drop index\(:reconcile_articles_alternates/
      refute down =~ "drop table"
      refute down =~ "reconcile_articles_language_index"
      refute down =~ ~r/remove :(language|rendered_blocks)/
      assert down =~ "remove :summary"
      assert down =~ "add :stale, :text"

      refute Enum.any?(planned.warnings, &(&1 =~ "already exist in the database" or &1 =~ "legacy Villain"))
      assert [notice] = Enum.filter(planned.notices, &(&1 =~ "Reconciled with the database"))
      assert notice =~ "read from #{inspect(Brando.repo())}, database #{database}"
      assert notice =~ "Brando.MigrationTest.ReconcileArticleV2: #{Path.relative_to_cwd(plan.metadata.migration)}"
      assert notice =~ "reconcile_articles.language, reconcile_articles.rendered_blocks"
      assert notice =~ "reconcile_articles.creator_id"
      assert notice =~ "drop of reconcile_articles.never_created (not in the database)"
      assert notice =~ "reconcile_articles.link (1 value)"
      assert notice =~ "reconcile_articles.data (legacy Villain column, 2 values)"

      migrate_up(plan.migration_source, fn down ->
        migrated = columns("reconcile_articles")
        assert Enum.all?(~w(summary edited_at updated_by_id), &(&1 in migrated))
        refute "stale" in migrated
        assert "reconcile_articles_alternates_entry_id_linked_entry_id_index" in indexes("reconcile_articles_alternates")

        assert query!("SELECT count(data), count(link), count(edited_at) FROM reconcile_articles").rows == [[2, 1, 2]]

        down.()
        assert columns("reconcile_articles") == legacy_columns
        assert table?("reconcile_articles_alternates")
        assert indexes("reconcile_articles_alternates") == ["reconcile_articles_alternates_pkey"]
        assert "reconcile_articles_language_index" in indexes("reconcile_articles")
      end)
    end

    test "the reviewed plan is applied as previewed, and a second run has nothing to do", context do
      opts = [migration_path: context.migration_path, snapshot_path: context.snapshot_path]
      {:ok, _} = Migrations.create_migration(ReconcileArticleV1, opts)
      create_legacy_articles()

      planned = reconcile(context, ReconcileArticleV2)
      [{"brando.blueprint.apply_plan", [request]}] = planned.tasks
      assert {:ok, metadata} = MigrationRequest.apply(request)
      assert File.read!(metadata.migration) == planned.assigns.brando_storage_plan.migration_source
      assert File.read!(metadata.migration) =~ "add_if_not_exists :rendered_blocks"

      rerun = reconcile(context, ReconcileArticleV2, ["--dry-run"])
      assert rerun.issues == []
      assert rerun.tasks == []
      assert rerun.notices == ["No storage changes necessary for Brando.MigrationTest.ReconcileArticleV2."]
    end

    # Whether a column is empty depends on the database read: on a development
    # copy it may be, in production not.
    test "never drops a column the Blueprint's own migrations did not create", context do
      create_legacy_farms()
      query!("UPDATE reconcile_farms SET slug = NULL")

      [{_, [request]}] = reconcile(context, ReconcileFarm).tasks
      assert {:ok, metadata} = MigrationRequest.apply(request)
      assert Snapshot.get_latest_snapshot(ReconcileFarm, snapshot_path: context.snapshot_path).rebaseline?

      migrate_up(File.read!(metadata.migration), fn _down ->
        planned = reconcile(context, ReconcileFarmV2, ["--dry-run"])
        plan = planned.assigns.brando_storage_plan
        assert plan.migration_source =~ ~r/drop index\(:reconcile_farms, \[:slug\]/
        refute plan.migration_source =~ "remove :slug"

        assert comments(plan.migration_source) =~
                 "reconcile_farms.slug predates this Blueprint's generated migrations, so --reconcile keeps it"

        assert Enum.any?(planned.notices, &(&1 =~ "reconcile_farms.slug (predates the Blueprint's generated migrations)"))
      end)
    end

    test "counts that change after review do not make the plan stale", context do
      opts = [migration_path: context.migration_path, snapshot_path: context.snapshot_path]
      {:ok, _} = Migrations.create_migration(ReconcileArticleV1, opts)
      create_legacy_articles()

      [{_, [request]}] = reconcile(context, ReconcileArticleV2).tasks
      query!("INSERT INTO reconcile_articles (title, data, link) VALUES ('Third', '{}', 'https://example.org')")
      assert {:ok, metadata} = MigrationRequest.apply(request)
      assert comments(File.read!(metadata.migration)) =~ "reconcile_articles.link holds 2 values"
    end

    test "a request goes stale when the database changes after review", context do
      opts = [migration_path: context.migration_path, snapshot_path: context.snapshot_path]
      {:ok, _} = Migrations.create_migration(ReconcileArticleV1, opts)
      create_legacy_articles()

      [{_, [request]}] = reconcile(context, ReconcileArticleV2).tasks
      query!("UPDATE reconcile_articles SET stale = 'now in use'")
      assert_raise Mix.Error, ~r/stale/, fn -> MigrationRequest.apply(request) end
    end

    test "a table with no snapshot history is altered, and once it matches only a baseline is recorded", context do
      create_legacy_farms()
      legacy_columns = columns("reconcile_farms")

      planned = reconcile(context, ReconcileFarm, ["--dry-run"])
      assert planned.issues == []
      plan = planned.assigns.brando_storage_plan
      [up, down] = String.split(plan.migration_source, "def down do")

      comments = comments(plan.migration_source)

      assert comments =~
               "reconcile_farms predates this Blueprint's snapshots, so this migration adds only what the database lacks."

      assert comments =~
               "reconcile_farms.creator_id already exists without the foreign key reconcile_farms_creator_id_fkey"

      refute plan.migration_source =~ "create table"
      assert up =~ "alter table(:reconcile_farms)"
      assert up =~ "add :edited_at, :utc_datetime"
      assert up =~ ~r/add :updated_by_id,\s+references\(:users/
      refute plan.migration_source =~ ~r/:(title|slug|creator_id),/
      refute up =~ "timestamps()"
      assert up =~ "UPDATE reconcile_farms SET edited_at = updated_at WHERE edited_at IS NULL"
      assert up =~ ~r/create unique_index\(:reconcile_farms, \[:slug\]/
      assert down =~ ~r/drop index\(:reconcile_farms, \[:slug\]/
      assert down =~ "remove :edited_at"
      refute down =~ "drop table"

      assert Enum.any?(planned.notices, &(&1 =~ "reconcile_farms already exists; the migration alters it"))

      migrate_up(plan.migration_source, fn down ->
        assert query!("SELECT edited_at IS NOT NULL FROM reconcile_farms").rows == [[true]]

        matched = reconcile(context, ReconcileFarm, ["--dry-run"])
        assert matched.issues == []
        baseline = matched.assigns.brando_storage_plan
        assert baseline.migration_source == nil
        assert baseline.snapshot.rebaseline?
        assert [notice] = Enum.filter(matched.notices, &(&1 =~ "Reconciled with the database"))
        assert notice =~ "(snapshot only, a baseline the database already matches)"
        assert notice =~ "left out: reconcile_farms.creator_id (exists, without its foreign key)"
        refute notice =~ "alters it"

        down.()
        assert columns("reconcile_farms") == legacy_columns
        assert indexes("reconcile_farms") == ["reconcile_farms_pkey"]
      end)
    end

    test "a removed trait's table and column are kept while they hold data", context do
      opts = [migration_path: context.migration_path, snapshot_path: context.snapshot_path]
      {:ok, created} = Migrations.create_migration(ReconcileArticleV2, opts)

      migrate_up(File.read!(created.migration), fn _down ->
        query!("""
        INSERT INTO reconcile_articles (title, language, inserted_at, updated_at)
        VALUES ('First', 'en', now(), now()), ('Second', 'no', now(), now())
        """)

        query!("""
        INSERT INTO reconcile_articles_alternates (entry_id, linked_entry_id, inserted_at, updated_at)
        SELECT min(id), max(id), now(), now() FROM reconcile_articles
        """)

        planned = reconcile(context, ReconcileArticleV3, ["--dry-run"])
        assert planned.issues == []
        plan = planned.assigns.brando_storage_plan
        [up, down] = String.split(plan.migration_source, "def down do")
        refute plan.migration_source =~ "table(:reconcile_articles_alternates)"
        refute plan.migration_source =~ ":language,"
        refute up =~ "remove :language"
        assert up =~ ~r/drop index\(:reconcile_articles, \[:language\]/
        assert down =~ ~r/create index\(:reconcile_articles, \[:language\]/

        comments = comments(plan.migration_source)
        assert comments =~ "reconcile_articles_alternates holds 1 row, so this migration keeps it."
        assert comments =~ "reconcile_articles.language holds 2 values, so this migration keeps it."

        migrate_up(plan.migration_source, fn down ->
          refute "reconcile_articles_language_index" in indexes("reconcile_articles")
          down.()
          assert "reconcile_articles_language_index" in indexes("reconcile_articles")
        end)

        query!("DELETE FROM reconcile_articles_alternates")
        emptied = reconcile(context, ReconcileArticleV3, ["--dry-run"]).assigns.brando_storage_plan
        [up, down] = String.split(emptied.migration_source, "def down do")
        assert up =~ "drop table(:reconcile_articles_alternates)"
        assert down =~ "create table(:reconcile_articles_alternates)"
      end)
    end

    test "a table the database does not have is created as usual", context do
      planned = reconcile(context, ReconcileFarm, ["--dry-run"])
      assert planned.issues == []
      assert planned.assigns.brando_storage_plan.migration_source =~ "create table(:reconcile_farms)"
      assert Enum.any?(planned.notices, &(&1 =~ "Brando.MigrationTest.ReconcileFarm: " and &1 =~ "nothing to reconcile"))
    end

    test "plans every Blueprint with --all, and refuses --rebaseline", context do
      create_legacy_farms()

      planned =
        Igniter.Test.test_project()
        |> Igniter.assign(:brando_blueprints, [ReconcileFarm, Brando.MigrationTest.ExecutionV1])
        |> Igniter.compose_task(BlueprintMigration, [
          "--all",
          "--reconcile",
          "--dry-run",
          "--snapshot-path",
          context.snapshot_path
        ])

      assert planned.issues == []
      assert [{"brando.blueprint.apply_plan", [_, _]}] = planned.tasks
      assert [notice] = Enum.filter(planned.notices, &(&1 =~ "Reconciled with the database"))
      assert notice =~ "Brando.MigrationTest.ReconcileFarm: priv/repo/migrations/"
      assert notice =~ "reconcile_farms already exists; the migration alters it"
      assert notice =~ "Brando.MigrationTest.ExecutionV1: priv/repo/migrations/"

      refused = reconcile(context, ReconcileFarm, ["--rebaseline"])
      assert [issue] = refused.issues
      assert issue =~ "--reconcile"
      assert issue =~ "--rebaseline"
      assert refused.tasks == []
    end

    test "a planned alter of a table the database lacks stops instead of guessing", context do
      opts = [migration_path: context.migration_path, snapshot_path: context.snapshot_path]
      {:ok, _} = Migrations.create_migration(ReconcileArticleV1, opts)

      planned = reconcile(context, ReconcileArticleV2, ["--dry-run"])
      assert [issue] = planned.issues
      assert issue =~ "reconcile_articles is not in it"
      assert planned.tasks == []
    end
  end
end
