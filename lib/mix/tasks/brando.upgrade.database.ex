defmodule Mix.Tasks.Brando.Upgrade.Database do
  use Mix.Task

  alias Brando.Upgrade.Database

  @shortdoc "Walks the database phase of an upgrade, stopping at each review point"

  @moduledoc """
  Runs the database phase of an upgrade (guides/migrating_from_053.md,
  sections 3 and 4) one stretch at a time, and stops wherever the guide has
  you review something:

      mix brando.upgrade.database
      mix brando.upgrade.database --dry-run
      mix brando.upgrade.database --yes

  Each run reads where the application stands (see `Brando.Upgrade.Database`),
  prints it, runs the next steps and stops with what to review and how to go
  on, which is usually to run it again. Nothing is kept between runs. In
  order:

    1. `mix brando.gen.migrations` copies Brando's missing migrations. It
       writes source files, so the run stops: review and commit them.
    2. `mix brando.migrations.check` checks the pending copies against
       Brando's templates, then `mix brando.migrate` runs every pending
       migration, after asking.
    3. `mix brando.check.legacy_conversion` checks the Villain → blocks
       conversion, when Brando's migrations were pending or Blueprint
       migrations are due. It stops the run while anything is missing.
    4. `mix brando.gen.blueprint_migration --all --reconcile` writes the
       Blueprint migrations, fitted to this database (see "Legacy snapshots"
       in the guide). The run stops: review each migration, run it down and
       up on a scratch copy, and commit it with its snapshot. The next run
       applies them with `mix brando.migrate`, after asking.
    5. After asking: `mix brando.entries.resave --yes`,
       `mix brando.identifiers.sync`, `mix brando.images.adopt --dry-run`,
       then, after asking again, `mix brando.images.adopt`;
       `mix brando.check.image_texts`; and a rebuild of the search index (what
       Configuration → Utilities → Search index runs).

  The derived data in step 5 counts as repaired once the search index has
  been rebuilt after the last migration ran. A rebuild from the admin counts
  too: after one, run the step 5 tasks by hand if they have not run. A run
  that finds nothing to do says so.

  Every step the run took, skipped (and why) or left for a later run is
  listed at the end.

  Options:

    * `--dry-run` - prints the state and the plan; runs nothing.
    * `--yes` - answers yes to every question, its own and the source tasks'
      (they still stop for review). Without it and without a terminal to
      answer on, the run stops before the first step that asks.
    * `--skip-conversion-check` - leaves out step 3, when what it lists is
      expected (content edited since the conversion, say).

  It refuses to run in an application with named environments (tenancy
  mode `:single` or `:multi`): their content and migrations live in one
  schema per environment, which `--reconcile` and the derived-data tasks
  here do not cover. Follow the guide by hand there.
  """

  @switches [yes: :boolean, dry_run: :boolean, skip_conversion_check: :boolean]
  @aliases [y: :yes, n: :dry_run]

  @confirm %{
    migrate: :migrate,
    resave: :derived,
    adopt: :adopt
  }

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches, aliases: @aliases)

    if invalid != [] or positional != [] do
      Mix.raise("Unknown arguments: #{Enum.map_join(positional ++ Enum.map(invalid, &elem(&1, 0)), ", ", & &1)}")
    end

    Mix.Task.run("app.config")

    if Brando.Tenant.enabled?(), do: Mix.raise(stop_message(:tenancy, %{}))

    state = read_state()
    print_state(state)
    plan = Database.plan(state, opts)

    if opts[:dry_run] do
      print_plan(plan, state)
    else
      execute(plan, state, opts)
    end
  end

  defp configured_repo! do
    repo = Brando.repo()

    if is_atom(repo) and not is_nil(repo) and Code.ensure_loaded?(repo),
      do: repo,
      else: Mix.raise("No repo is configured. Set config :brando, repo: MyApp.Repo.")
  end

  # The Blueprints are the modules of the loaded :otp_app.
  defp load_application! do
    app = Brando.RuntimeConfig.get(:otp_app)

    unless is_atom(app) and not is_nil(app) and Application.load(app) in [:ok, {:error, {:already_loaded, app}}],
      do: Mix.raise("Could not list the application's Blueprints. Set config :brando, otp_app: :my_app.")
  end

  defp read_state do
    repo = configured_repo!()
    load_application!()
    migrations_path = Path.join(Mix.EctoSQL.source_repo_priv(repo), "migrations")

    # Reading the state is not what the run is about: keep its queries quiet.
    level = Logger.level()
    Logger.configure(level: :warning)

    result =
      try do
        Ecto.Migrator.with_repo(repo, fn repo ->
          Database.state(repo,
            migrations_path: migrations_path,
            blueprints: Brando.Blueprint.list_blueprints(),
            tenancy: Brando.Tenant.mode(),
            database: repo.config()[:database]
          )
        end)
      after
        Logger.configure(level: level)
      end

    case result do
      {:ok, state, _apps} -> state
      {:error, reason} -> Mix.raise("#{inspect(repo)} did not start: #{inspect(reason)}")
    end
  end

  ## Executing a plan

  @doc """
  Runs `plan` for `state`. `opts` takes the task's options, and `:runner`, a
  function of a step and the options that runs it and returns `:ok`,
  `{:ok, note}`, `{:declined, note}` or `{:error, message}`
  (`run_step/2` by default). Returns the `{status, step, note}` log.
  """
  def execute(plan, state, opts) do
    runner = Keyword.get(opts, :runner, &run_step/2)
    {log, stop} = walk(plan, [], %{runner: runner, opts: opts, state: state})
    log = Enum.reverse(log)
    print_summary(log)

    case stop do
      {:no_answer, message} ->
        Mix.raise(message)

      {:failed, reason} ->
        Mix.shell().error("\n" <> stop_message(reason, state))
        exit({:shutdown, 1})

      reason ->
        Mix.shell().info("\n" <> stop_message(reason, state))
        log
    end
  end

  defp walk([], log, _ctx), do: {log, :done}

  defp walk([{:stop, reason} | rest], log, _ctx) do
    {later(rest, "waits for the review", log), reason}
  end

  defp walk([{:skip, step, why} | rest], log, ctx), do: walk(rest, [{:skipped, step, why} | log], ctx)
  defp walk([{:later, step, why} | rest], log, ctx), do: walk(rest, [{:later, step, why} | log], ctx)

  defp walk([{:run, step} | rest], log, ctx) do
    case confirm(step, ctx) do
      :yes ->
        Mix.shell().info([:cyan, "\n==> #{Database.command(step)}\n"])
        run_and_continue(step, rest, log, ctx)

      :no when step == :adopt ->
        walk(rest, [{:skipped, step, "you answered no"} | log], ctx)

      :no ->
        {later(rest, "waits", [{:declined, step, "you answered no"} | log]), :declined}

      {:no_answer, message} ->
        {later(rest, "waits", [{:declined, step, "nobody answered"} | log]), {:no_answer, message}}
    end
  end

  defp run_and_continue(step, rest, log, ctx) do
    case ctx.runner.(step, ctx.opts) do
      :ok ->
        walk(rest, [{:ran, step, nil} | log], ctx)

      {:ok, note} ->
        walk(rest, [{:ran, step, note} | log], ctx)

      {:declined, note} ->
        {later(rest, "the step before it wrote nothing", [{:declined, step, note} | log]), :declined}

      {:error, message} ->
        {later(rest, "#{Database.command(step)} failed", [{:failed, step, message} | log]), {:failed, failure(step)}}
    end
  end

  defp failure(:migrations_check), do: :outdated_copies
  defp failure(:legacy_check), do: :conversion_check
  defp failure(step), do: {:step, step}

  defp later(entries, why, log) do
    Enum.reduce(entries, log, fn
      {:run, step}, log -> [{:later, step, why} | log]
      {:later, step, reason}, log -> [{:later, step, reason} | log]
      {:skip, step, reason}, log -> [{:skipped, step, reason} | log]
      {:stop, _reason}, log -> log
    end)
  end

  # Database steps ask first. `:resave` asks for the whole derived-data stretch
  # but the adoption, which asks again once the dry run has shown its counts.
  defp confirm(step, ctx) do
    case Map.fetch(@confirm, step) do
      {:ok, question} -> ask(question(question, ctx.state), ctx.opts)
      :error -> :yes
    end
  end

  defp ask(question, opts) do
    if Mix.Brando.confirm?(question, opts), do: :yes, else: :no
  rescue
    error in Mix.Error -> {:no_answer, Exception.message(error)}
  end

  defp question(:migrate, state) do
    {brando, others} = Enum.split_with(state.pending, &Database.brando_migration?/1)

    """

    Run #{count(state.pending, "pending migration")} on #{database(state)} \
    (#{length(brando)} of Brando's, #{length(others)} of the application's)?
    This changes the database: run it on a copy of production first.\
    """
  end

  defp question(:derived, state) do
    """

    Resave every entry, sync identifiers and rebuild the search index on #{database(state)}?
    mix ecto.rollback does not undo them: run them on staging or a copy first.\
    """
  end

  defp question(:adopt, _state) do
    "\nRecord the config of the images that already match it (counted above)?"
  end

  @doc """
  The task and arguments a step runs. `yes?` passes `--yes` on to the tasks
  that write source files, which otherwise ask before writing.
  """
  def task(:gen_migrations, yes?), do: {"brando.gen.migrations", yes(yes?)}
  def task(:migrations_check, _yes?), do: {"brando.migrations.check", []}
  def task(:migrate, _yes?), do: {"brando.migrate", []}
  def task(:legacy_check, _yes?), do: {"brando.check.legacy_conversion", []}
  def task(:gen_blueprint, yes?), do: {"brando.gen.blueprint_migration", ["--all", "--reconcile" | yes(yes?)]}
  def task(:resave, _yes?), do: {"brando.entries.resave", ["--yes"]}
  def task(:identifiers, _yes?), do: {"brando.identifiers.sync", []}
  def task(:adopt_dry_run, _yes?), do: {"brando.images.adopt", ["--dry-run"]}
  def task(:adopt, _yes?), do: {"brando.images.adopt", []}
  def task(:image_texts, _yes?), do: {"brando.check.image_texts", []}

  defp yes(true), do: ["--yes"]
  defp yes(_), do: []

  @doc """
  Runs a step: its task (`task/2`) through `run_task/2`, or, for the search
  index, `Brando.Search.rebuild/1`, which Utilities' rebuild runs. Returns
  what `execute/3` expects of a runner.
  """
  def run_step(:search_index, _opts) do
    Mix.Brando.start_quietly()

    case Brando.Search.rebuild() do
      {:ok, written} -> {:ok, "#{written} documents written"}
      {:error, reason} -> {:error, "the rebuild failed: #{inspect(reason)}"}
    end
  end

  def run_step(step, opts) when step in [:gen_migrations, :gen_blueprint] do
    {task, args} = task(step, opts[:yes] == true)

    case run_task(task, args) do
      {:ok, :changes_aborted} -> {:declined, "nothing was written"}
      {:ok, :issues} -> {:error, "it reported issues (above); nothing was written"}
      {:ok, _result} -> :ok
      error -> error
    end
  end

  # Without the media, adopting stops: every image would differ for want of
  # its files. That is the media's state, not a failed upgrade, so the run
  # carries on to the steps after it.
  def run_step(step, opts) when step in [:adopt_dry_run, :adopt] do
    Mix.Brando.start_quietly()

    case Mix.Tasks.Brando.Images.Adopt.unsynced(Brando.Doctor.Context.new(mode: :mix).environments) do
      [] ->
        {task, args} = task(step, opts[:yes] == true)

        case run_task(task, args) do
          {:ok, _result} -> :ok
          error -> error
        end

      roots ->
        {:ok, "skipped: no image files under #{Enum.join(roots, ", ")}; run mix brando.images.adopt where the media is"}
    end
  end

  def run_step(step, opts) do
    # The data tasks start the application themselves, some through `mix run`,
    # which would start the web server and Oban's queues.
    if step in [:resave, :identifiers, :image_texts], do: Mix.Brando.start_quietly()
    {task, args} = task(step, opts[:yes] == true)

    case run_task(task, args) do
      {:ok, _result} -> :ok
      error -> error
    end
  end

  @doc """
  Runs a Mix task again (`Mix.Task.rerun/2`) and returns `{:ok, result}`.
  A task's failure, whether an exit status, a Mix error or an exception,
  becomes `{:error, message}` so the run can report it and stop.
  """
  def run_task(task, args) do
    # `mix brando.migrate` runs `ecto.migrate` through `Mix.Task.run/2`, which
    # runs a task once per VM.
    if task == "brando.migrate", do: Mix.Task.reenable("ecto.migrate")
    {:ok, Mix.Task.rerun(task, args)}
  rescue
    error in Mix.Error ->
      {:error, Exception.message(error)}

    error in RuntimeError ->
      if error.message =~ "No input detected",
        do: {:error, "stdin is closed, so nothing was written. Pass --yes to go ahead without asking."},
        else: {:error, Exception.message(error)}

    error ->
      Mix.shell().error(Exception.format(:error, error, __STACKTRACE__))
      {:error, "it raised #{inspect(error.__struct__)}: #{Exception.message(error)}"}
  catch
    :exit, {:shutdown, 0} -> {:ok, nil}
    :exit, {:shutdown, status} when is_integer(status) -> {:error, "it exited with status #{status}"}
  end

  ## Output

  defp print_state(state) do
    Mix.shell().info([:cyan, "==> Database phase of the upgrade, on #{database(state)}\n"])

    templates =
      case state.missing_templates do
        [] ->
          "all copied"

        [only] ->
          "1 not copied yet (#{only})"

        [first | _] = missing ->
          "#{length(missing)} not copied yet, from #{first}"
      end

    {brando, others} = Enum.split_with(state.pending, &Database.brando_migration?/1)

    pending =
      if state.pending == [],
        do: "none",
        else: "#{length(state.pending)} (#{length(brando)} of Brando's, #{length(others)} of the application's)"

    Mix.shell().info("  Brando migration templates: #{templates}")
    Mix.shell().info("  Migrations not run: #{pending}")
    Enum.each(blueprint_lines(state.blueprints), &Mix.shell().info(&1))
    Mix.shell().info("  Derived data: #{derived_line(state)}")
  end

  defp blueprint_lines({:error, message}), do: ["  Blueprint migrations: could not be planned: #{message}"]

  defp blueprint_lines({:ok, %{changed: changed, up_to_date: up_to_date, left_out: left_out}}) do
    main =
      case changed do
        [] -> "  Blueprint migrations: every Blueprint (#{length(up_to_date)}) matches its latest snapshot"
        changed -> "  Blueprint migrations due: #{Enum.map_join(changed, ", ", &inspect/1)}"
      end

    extra =
      if left_out == [],
        do: [],
        else: ["    left out, as --all does (fixed schema prefix): #{Enum.map_join(left_out, ", ", &inspect/1)}"]

    [main | extra]
  end

  defp derived_line(state) do
    case Database.derived_reason(state) do
      nil ->
        "repaired (the search index was rebuilt at #{format_time(state.search.rebuilt_at)}, " <>
          "after the last migration at #{format_time(state.search.migrated_at)})"

      reason ->
        "to repair (#{reason})"
    end
  end

  defp print_plan(plan, state) do
    Mix.shell().info("\nPlan:")

    Enum.each(plan, fn
      {:run, step} -> Mix.shell().info("  run    #{Database.command(step)}#{asks(step)}")
      {:skip, step, why} -> Mix.shell().info("  skip   #{Database.command(step)}: #{why}")
      {:later, step, why} -> Mix.shell().info("  later  #{Database.command(step)}: #{why}")
      {:stop, reason} -> Mix.shell().info("  stop   #{stop_title(reason)}")
    end)

    Mix.shell().info("\nDry run: nothing was run.")

    Enum.find_value(plan, fn
      {:stop, reason} -> Mix.shell().info("\nWhere it stops: " <> stop_message(reason, state))
      _entry -> nil
    end)
  end

  defp asks(step) when is_map_key(@confirm, step), do: " (asks first)"
  defp asks(_step), do: ""

  defp print_summary(log) do
    Mix.shell().info([:cyan, "\n==> Summary\n"])

    Enum.each(log, fn {status, step, note} ->
      note = if note, do: ": #{note}", else: ""
      Mix.shell().info("  #{status_label(status)} #{Database.command(step)}#{note}")
    end)
  end

  defp status_label(:ran), do: "ran     "
  defp status_label(:failed), do: "FAILED  "
  defp status_label(:declined), do: "declined"
  defp status_label(:skipped), do: "skipped "
  defp status_label(:later), do: "not run "

  defp stop_title(:tenancy), do: "named environments: run the steps by hand"
  defp stop_title(:review_migrations), do: "review and commit the copied migrations"
  defp stop_title(:review_blueprint_migrations), do: "review, test and commit the Blueprint migrations"
  defp stop_title(:blueprint_error), do: "the Blueprints could not be planned"
  defp stop_title(:done), do: "done"

  @doc "What a stop tells the developer to review or do, and how to go on."
  def stop_message(:tenancy, _state) do
    """
    This application has named environments (tenancy_mode :single or :multi).
    mix brando.upgrade.database covers the public schema only: --reconcile is
    refused there, and Blueprint migrations and derived data live in one schema
    per environment. Follow sections 3 and 4 of guides/migrating_from_053.md by
    hand, with mix brando.migrate followed by mix brando.migrate --tenants.
    """
  end

  def stop_message(:review_migrations, _state) do
    """
    Stopped for review. Read the copied migrations (git status priv/repo/migrations),
    then commit them. Then run mix brando.upgrade.database again: it checks the
    copies against Brando's templates and runs them after asking.
    """
  end

  def stop_message(:review_blueprint_migrations, _state) do
    """
    Stopped for review of the Blueprint migrations it wrote (listed above):

      1. Read each up/0 and down/0. --reconcile compares names only: check types,
         defaults and nullability against \\d <table>.
      2. Resolve data prerequisites, such as duplicate values for a new unique
         index.
      3. On a scratch copy of the database, run them forward, back and forward:
         mix brando.migrate, mix ecto.rollback -n <how many it wrote>, mix brando.migrate.
      4. Commit each migration together with its Blueprint snapshot.

    Then run mix brando.upgrade.database again: it applies them here after asking.
    """
  end

  def stop_message(:blueprint_error, state) do
    {:error, message} = state.blueprints

    """
    Stopped: the Blueprint migrations could not be planned:

      #{message}

    Run mix brando.gen.blueprint_migration --all --reconcile --dry-run for the
    details, fix it, then run mix brando.upgrade.database again.
    """
  end

  def stop_message(:outdated_copies, _state) do
    """
    Stopped: copies of Brando's migrations that have not run differ from
    Brando's templates (listed above). Run mix brando.migrations.check --update,
    review the diff (a copy may have been edited on purpose) and commit, then run
    mix brando.upgrade.database again.
    """
  end

  def stop_message(:conversion_check, _state) do
    """
    Stopped: mix brando.check.legacy_conversion found content that did not come
    through the Villain → blocks conversion (listed above). Resolve it before
    generating Blueprint migrations; the Villain columns are the only record of
    what the conversion started from. If what it lists is expected (content
    edited since the conversion), run mix brando.upgrade.database
    --skip-conversion-check.
    """
  end

  def stop_message({:step, step}, _state) do
    """
    Stopped: #{Database.command(step)} failed (see above). Fix it, then run
    mix brando.upgrade.database again; the steps that ran do not run again
    unless they still need to.
    """
  end

  def stop_message(:declined, _state) do
    "Stopped: nothing more was done. Run mix brando.upgrade.database again when ready."
  end

  def stop_message(:done, _state) do
    """
    The database phase is done. Still by hand (section 4 of
    guides/migrating_from_053.md, which mix brando.doctor checks): the Oban
    queues of an application that configures Oban itself, and the
    Notifications permission for group authorization. Then reconcile the
    Gettext catalogs (section 5).
    """
  end

  defp database(%{database: database}) when is_binary(database), do: "database #{database}"
  defp database(_state), do: "the configured database"

  defp count([_], noun), do: "1 #{noun}"
  defp count(list, noun), do: "#{length(list)} #{noun}s"

  defp format_time(nil), do: "(none)"
  defp format_time(%DateTime{} = time), do: time |> DateTime.truncate(:second) |> Calendar.strftime("%Y-%m-%d %H:%M UTC")

  defp format_time(%NaiveDateTime{} = time),
    do: time |> NaiveDateTime.truncate(:second) |> Calendar.strftime("%Y-%m-%d %H:%M UTC")
end
