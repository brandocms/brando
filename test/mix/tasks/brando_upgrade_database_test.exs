defmodule Brando.UpgradeDatabaseTest.Shared do
  use Brando.Blueprint,
    application: "Brando",
    domain: "UpgradeDatabase",
    schema: "Shared",
    singular: "shared",
    plural: "shareds"

  @schema_prefix "shared"
  attributes do
    attribute :title, :string
  end
end

defmodule Mix.Tasks.Brando.UpgradeDatabaseTest.Outcome do
  use Mix.Task

  @impl Mix.Task
  def run([outcome]) do
    send(self(), {:task_ran, outcome})

    case outcome do
      "ok" -> :done
      "exit0" -> exit({:shutdown, 0})
      "exit1" -> exit({:shutdown, 1})
      "mix_error" -> Mix.raise("No such entry")
      "no_input" -> raise "No input detected when asking for confirmation, perhaps you meant to use `--yes`?"
    end
  end
end

defmodule Mix.Tasks.Brando.Upgrade.DatabaseTest do
  use ExUnit.Case, async: false

  alias Brando.Blueprint.Migrations
  alias Brando.Upgrade.Database
  alias Mix.Tasks.Brando.Upgrade.Database, as: Task

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Brando.repo())
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)

    root = Path.join(System.tmp_dir!(), "brando-upgrade-database-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  # The state of a Lett-like 0.53 site once Brando's migrations are copied:
  # all of them pending, every Blueprint behind its snapshot.
  defp state(overrides \\ %{}) do
    Map.merge(
      %{
        tenancy: :none,
        database: "lett_copy",
        missing_templates: [],
        pending: [{20_260_101_000_143, "brando_143_x"}, {20_260_101_000_218, "brando_218_y"}],
        blueprints: {:ok, %{changed: [Lett.Articles.Article], up_to_date: [], left_out: []}},
        search: %{rebuilt_at: nil, migrated_at: ~N[2026-10-12 13:23:14]}
      },
      overrides
    )
  end

  defp touch(dir, names) do
    File.mkdir_p!(dir)
    Enum.each(names, &File.write!(Path.join(dir, &1), "# migration\n"))
  end

  describe "missing_templates/2" do
    test "lists the templates without a copy, matched by name without the version", %{root: root} do
      templates = Path.join(root, "templates")
      migrations = Path.join(root, "migrations")
      touch(templates, ~w(brando_01_a.exs brando_10_c.exs brando_9_b.exs brando_103_d.exs))
      # Old copies carry their own versions; the one for brando_9 was renamed by hand
      touch(migrations, ~w(20210101000000_brando_01_a.exs 20260101000103_brando_103_d.exs 20220101_brando_9_other.exs))

      assert Database.missing_templates(migrations, templates) == ["brando_9_b.exs", "brando_10_c.exs"]

      touch(migrations, ~w(20260101000009_brando_9_b.exs 20260101000010_brando_10_c.exs))
      assert Database.missing_templates(migrations, templates) == []
    end

    test "every template is missing from an empty or absent directory", %{root: root} do
      templates = Path.join(root, "templates")
      touch(templates, ~w(brando_01_a.exs))

      assert Database.missing_templates(Path.join(root, "none"), templates) == ["brando_01_a.exs"]
    end
  end

  describe "pending_migrations/2" do
    test "lists the files whose version the database has not run", %{root: root} do
      repo = Brando.repo()
      %{rows: [[ran]]} = repo.query!("SELECT max(version) FROM schema_migrations")
      touch(root, ["#{ran}_already_ran.exs", "29990101000000_brando_300_new.exs", "29990101000001_add_things.exs"])

      assert Database.pending_migrations(repo, root) == [
               {29_990_101_000_000, "brando_300_new"},
               {29_990_101_000_001, "add_things"}
             ]
    end
  end

  describe "blueprints/2" do
    test "names the Blueprints behind their snapshot, and those --all leaves out", %{root: root} do
      opts = [migration_path: Path.join(root, "migrations"), snapshot_path: Path.join(root, "snapshots")]
      modules = [Brando.MigrationTest.ExecutionV1, Brando.UpgradeDatabaseTest.Shared]

      assert {:ok, %{changed: [Brando.MigrationTest.ExecutionV1], up_to_date: [], left_out: left_out}} =
               Database.blueprints(modules, opts)

      assert left_out == [Brando.UpgradeDatabaseTest.Shared]
      refute File.exists?(opts[:migration_path])

      {:ok, _metadata} = Migrations.create_migration(Brando.MigrationTest.ExecutionV1, opts)

      assert {:ok, %{changed: [], up_to_date: [Brando.MigrationTest.ExecutionV1]}} =
               Database.blueprints(modules, opts)
    end

    test "returns the planner's error instead of raising", %{root: root} do
      opts = [migration_path: Path.join(root, "migrations"), snapshot_path: Path.join(root, "snapshots")]
      modules = [Brando.MigrationTest.ExecutionV1, Brando.MigrationTest.ExecutionV2]

      assert {:error, message} = Database.blueprints(modules, opts)
      assert message =~ "share the snapshot directory"
    end
  end

  describe "search_index/1" do
    test "reads when the index was rebuilt and when the last migration ran" do
      assert %{rebuilt_at: nil, migrated_at: %NaiveDateTime{}} = Database.search_index(Brando.repo())

      Brando.Search.Indexer.mark_rebuilt(~U[2999-01-01 00:00:00Z])
      search = Database.search_index(Brando.repo())
      assert search.rebuilt_at == ~U[2999-01-01 00:00:00Z]
      assert Database.derived_reason(state(%{pending: [], search: search})) == nil
    end
  end

  describe "plan/2" do
    test "refuses named environments" do
      assert Database.plan(state(%{tenancy: :multi})) == [{:stop, :tenancy}]
    end

    test "copies missing templates first and stops for their review" do
      assert [{:run, :gen_migrations}, {:stop, :review_migrations} | later] =
               Database.plan(state(%{missing_templates: ["brando_103_x.exs"]}))

      assert Enum.map(later, &elem(&1, 1)) == Database.steps() -- [:gen_migrations]
      assert Enum.all?(later, &match?({:later, _, _}, &1))
    end

    test "with Brando's migrations pending: check, migrate, check the conversion, write Blueprint migrations, stop" do
      assert Database.plan(state()) == [
               {:skip, :gen_migrations, "every Brando migration template has a copy"},
               {:run, :migrations_check},
               {:run, :migrate},
               {:run, :legacy_check},
               {:run, :gen_blueprint},
               {:stop, :review_blueprint_migrations},
               {:later, :resave, "waits for the review"},
               {:later, :identifiers, "waits for the review"},
               {:later, :adopt_dry_run, "waits for the review"},
               {:later, :adopt, "waits for the review"},
               {:later, :image_texts, "waits for the review"},
               {:later, :search_index, "waits for the review"}
             ]
    end

    test "the conversion check runs until the Blueprint migrations are written, unless skipped" do
      # Brando's migrations ran in an earlier run, whose conversion check failed
      plan = Database.plan(state(%{pending: []}))
      assert {:run, :legacy_check} in plan
      assert {:skip, :migrate, "every migration has run"} in plan

      plan = Database.plan(state(%{pending: []}), skip_conversion_check: true)
      assert {:skip, :legacy_check, "--skip-conversion-check"} in plan
      assert {:run, :gen_blueprint} in plan
    end

    test "with reviewed Blueprint migrations pending: migrate, then repair the derived data" do
      reviewed =
        state(%{
          pending: [{20_261_012_000_001, "lett_articles_article_002"}],
          blueprints: {:ok, %{changed: [], up_to_date: [Lett.Articles.Article], left_out: []}},
          search: %{rebuilt_at: nil, migrated_at: ~N[2026-10-12 13:23:14]}
        })

      assert Database.plan(reviewed) == [
               {:skip, :gen_migrations, "every Brando migration template has a copy"},
               {:skip, :migrations_check, "no Brando migration is pending"},
               {:run, :migrate},
               {:skip, :legacy_check, "no Brando migration is pending and no Blueprint migration is due"},
               {:skip, :gen_blueprint, "every Blueprint matches its latest snapshot"},
               {:run, :resave},
               {:run, :identifiers},
               {:run, :adopt_dry_run},
               {:run, :adopt},
               {:run, :image_texts},
               {:run, :search_index},
               {:stop, :done}
             ]
    end

    test "nothing to do once the search index was rebuilt after the last migration" do
      done =
        state(%{
          pending: [],
          blueprints: {:ok, %{changed: [], up_to_date: [Lett.Articles.Article], left_out: []}},
          search: %{rebuilt_at: ~U[2026-10-12 13:44:03Z], migrated_at: ~N[2026-10-12 13:23:14]}
        })

      {steps, stop} = done |> Database.plan() |> Enum.split(-1)
      assert stop == [{:stop, :done}]
      assert Enum.all?(steps, &match?({:skip, _, _}, &1))

      stale = put_in(done, [:search, :rebuilt_at], ~U[2026-10-12 13:00:00Z])
      assert Database.derived_reason(stale) == "migrations ran after the search index was last rebuilt"
      assert {:run, :resave} in Database.plan(stale)
    end

    test "stops when the Blueprints cannot be planned" do
      plan = Database.plan(state(%{blueprints: {:error, "share the snapshot directory"}}))
      assert {:stop, :blueprint_error} in plan
      refute {:run, :gen_blueprint} in plan
      refute Enum.any?(plan, &match?({:run, step} when step in [:resave, :search_index], &1))
    end
  end

  describe "execute/3" do
    defp recorder(results \\ %{}) do
      test = self()

      fn step, _opts ->
        send(test, {:ran, step})
        Map.get(results, step, :ok)
      end
    end

    defp ran do
      receive do
        {:ran, step} -> [step | ran()]
      after
        0 -> []
      end
    end

    defp output do
      receive do
        {:mix_shell, kind, [message]} when kind in [:info, :error] -> IO.iodata_to_binary(message) <> "\n" <> output()
      after
        0 -> ""
      end
    end

    test "answering no runs no database step" do
      send(self(), {:mix_shell_input, :prompt, "n"})

      log = Task.execute(Database.plan(state()), state(), runner: recorder())

      assert ran() == [:migrations_check]
      assert {:declined, :migrate, "you answered no"} in log
      assert {:later, :gen_blueprint, "waits"} in log
      assert_received {:mix_shell, :prompt, [question]}
      assert question =~ "Run 2 pending migrations on database lett_copy (2 of Brando's, 0 of the application's)?"
      assert output() =~ "nothing more was done"
    end

    test "with nobody to answer, it stops before the first database step, as entries.resave does" do
      send(self(), {:mix_shell_input, :prompt, :eof})

      assert_raise Mix.Error, ~r/stdin is closed, so nothing was done. Pass --yes/, fn ->
        Task.execute(Database.plan(state()), state(), runner: recorder())
      end

      assert ran() == [:migrations_check]
      summary = output()
      assert summary =~ "ran      mix brando.migrations.check"
      assert summary =~ "declined mix brando.migrate: nobody answered"
    end

    test "--yes migrates, checks the conversion, writes the Blueprint migrations and stops for their review" do
      log = Task.execute(Database.plan(state()), state(), runner: recorder(), yes: true)

      assert ran() == [:migrations_check, :migrate, :legacy_check, :gen_blueprint]
      refute_received {:mix_shell, :prompt, _}
      assert {:later, :resave, "waits for the review"} in log

      text = output()
      assert text =~ "Stopped for review of the Blueprint migrations"
      assert text =~ "mix ecto.rollback -n"
      assert text =~ "not run  mix brando.entries.resave --yes: waits for the review"
    end

    test "a failed conversion check stops before any Blueprint migration is written" do
      runner = recorder(%{legacy_check: {:error, "it exited with status 1"}})

      catch_exit(Task.execute(Database.plan(state()), state(), runner: runner, yes: true))

      assert ran() == [:migrations_check, :migrate, :legacy_check]
      text = output()
      assert text =~ "FAILED   mix brando.check.legacy_conversion: it exited with status 1"
      assert text =~ "--skip-conversion-check"
    end

    test "outdated copies stop before migrating" do
      runner = recorder(%{migrations_check: {:error, "it exited with status 1"}})

      assert catch_exit(Task.execute(Database.plan(state()), state(), runner: runner)) == {:shutdown, 1}

      assert ran() == [:migrations_check]
      refute_received {:mix_shell, :prompt, _}
      assert output() =~ "mix brando.migrations.check --update"
    end

    test "copying templates stops for review, and a declined copy says nothing was written" do
      copying = state(%{missing_templates: ["brando_103_x.exs"]})
      Task.execute(Database.plan(copying), copying, runner: recorder())
      assert ran() == [:gen_migrations]
      assert output() =~ "Stopped for review. Read the copied migrations"

      runner = recorder(%{gen_migrations: {:declined, "nothing was written"}})
      log = Task.execute(Database.plan(copying), copying, runner: runner)
      assert {:declined, :gen_migrations, "nothing was written"} in log
      assert output() =~ "nothing more was done"
    end

    test "derived data: asks once for the stretch, and again before adopting images" do
      reviewed =
        state(%{
          pending: [],
          blueprints: {:ok, %{changed: [], up_to_date: [Lett.Articles.Article], left_out: []}}
        })

      send(self(), {:mix_shell_input, :prompt, "y"})
      send(self(), {:mix_shell_input, :prompt, "n"})

      log = Task.execute(Database.plan(reviewed), reviewed, runner: recorder())

      assert ran() == [:resave, :identifiers, :adopt_dry_run, :image_texts, :search_index]
      assert {:skipped, :adopt, "you answered no"} in log
      assert_received {:mix_shell, :prompt, [derived]}
      assert derived =~ "Resave every entry, sync identifiers and rebuild the search index on database lett_copy?"
      assert_received {:mix_shell, :prompt, [adopt]}
      assert adopt =~ "Record the config of the images"
      assert output() =~ "The database phase is done"
    end

    test "declining the derived data runs none of it" do
      reviewed = state(%{pending: [], blueprints: {:ok, %{changed: [], up_to_date: [], left_out: []}}})
      send(self(), {:mix_shell_input, :prompt, "n"})

      Task.execute(Database.plan(reviewed), reviewed, runner: recorder())

      assert ran() == []
    end
  end

  describe "the steps" do
    test "run the existing tasks, passing --yes where they ask" do
      assert Task.task(:gen_migrations, false) == {"brando.gen.migrations", []}
      assert Task.task(:gen_migrations, true) == {"brando.gen.migrations", ["--yes"]}
      assert Task.task(:gen_blueprint, false) == {"brando.gen.blueprint_migration", ["--all", "--reconcile"]}
      assert Task.task(:migrate, true) == {"brando.migrate", []}
      assert Task.task(:resave, false) == {"brando.entries.resave", ["--yes"]}
      assert Task.task(:identifiers, true) == {"brando.identifiers.sync", []}
      assert Task.task(:adopt_dry_run, false) == {"brando.images.adopt", ["--dry-run"]}
      assert Task.task(:adopt, false) == {"brando.images.adopt", []}

      for step <- Database.steps() -- [:search_index] do
        {task, _args} = Task.task(step, false)
        assert Mix.Task.get(task), "#{task} is not a Mix task"
      end
    end
  end

  describe "run_task/2" do
    test "runs a task again each time, and turns its failures into errors" do
      task = "brando.upgrade_database_test.outcome"

      assert Task.run_task(task, ["ok"]) == {:ok, :done}
      assert Task.run_task(task, ["ok"]) == {:ok, :done}
      assert Task.run_task(task, ["exit0"]) == {:ok, nil}
      assert Task.run_task(task, ["exit1"]) == {:error, "it exited with status 1"}
      assert Task.run_task(task, ["mix_error"]) == {:error, "No such entry"}

      assert Task.run_task(task, ["no_input"]) ==
               {:error, "stdin is closed, so nothing was written. Pass --yes to go ahead without asking."}

      assert_received {:task_ran, "ok"}
      assert_received {:task_ran, "ok"}
    end

    test "runs a read-only check in the running application" do
      assert Task.run_step(:image_texts, []) == :ok
      assert output() =~ "No template prints an image's alt text"
    end
  end

  describe "run/1" do
    test "refuses an application with named environments" do
      original = Application.fetch_env(:brando, :tenancy_mode)
      Application.put_env(:brando, :tenancy_mode, :single)

      on_exit(fn ->
        case original do
          {:ok, mode} -> Application.put_env(:brando, :tenancy_mode, mode)
          :error -> Application.delete_env(:brando, :tenancy_mode)
        end
      end)

      assert_raise Mix.Error, ~r/named environments/, fn -> Task.run(["--dry-run"]) end
    end

    test "rejects unknown arguments" do
      assert_raise Mix.Error, ~r/Unknown arguments: --bogus/, fn -> Task.run(["--bogus"]) end
    end
  end
end
