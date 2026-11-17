defmodule Mix.Tasks.Brando.Modules do
  @shortdoc "Export, plan and import module-definition DSL files"
  @default_timeout :timer.minutes(10)
  @moduledoc """
  Exports and imports complete module definitions, including refs, vars, children,
  table templates and adjacent HEEx/Liquid source.

      mix brando.modules export --out priv/modules --user 1
      mix brando.modules import --from priv/modules --user 1 --dry-run
      mix brando.modules import --from priv/modules --user 1
      mix brando.modules import --from priv/modules --user 1 --no-wait
      mix brando.modules refresh --uid hero-uid --user 1
      mix brando.modules resolve --uid hero-uid --user 1
      mix brando.modules resolve --uid hero-uid --user 1 --drop link --map title=heading --apply

  Tenant applications must select `--site KEY --environment KEY`. Standalone
  applications omit both. Every command requires an active `--user ID` and uses
  the account's normal authorization. Export accepts repeatable `--uid UID` to
  select complete trees. Import accepts `--references FILE`, a JSON object mapping
  exported asset tokens to destination record IDs.

  Export requires a new output directory. Import prints a plan, refuses conflicts
  and structural migrations, and updates only the baseline lockfile after a
  successful apply. `--dry-run` performs no database or file writes.

  `import`, `refresh` and `resolve --apply` queue the entries that use the
  changed modules for rendering, then wait until each has rendered, on
  whichever node runs the jobs: this task's own queue, or a running server's.
  They exit non-zero, naming the entries, when a render fails or when
  `--timeout SECONDS` (default #{div(@default_timeout, 1000)}) passes first.
  `--no-wait` leaves the renders queued for a running server: the task then
  runs no Oban queues, and says how many it queued. The task stops the
  application before it returns, so a job its queue is running finishes, and
  it never starts the module definition watcher.

  `resolve` lists the blocks still on an older version of the module and the
  refs and vars they hold that the module no longer defines (a dry run).
  `--drop KEY` drops a leftover and `--map OLD=NEW` moves it onto a ref or var
  the module defines now; both are repeatable, and a key can be written
  `ref:KEY` or `var:KEY` when a ref and a var share it. Nothing is written
  without `--apply`. Applying stores a revision of every entry it changes,
  records the change in Activity and moves open editors onto the new rows
  (`Brando.Content.StaleBlocks`).

  See the [module definitions guide](module_definitions.md).
  """
  use Mix.Task

  alias Brando.Content.Definition.Plan
  alias Brando.Content.Definitions
  alias Brando.Content.StaleBlocks
  alias Brando.Tenant
  alias Brando.Tenant.Registry

  @switches [
    out: :string,
    from: :string,
    user: :integer,
    site: :string,
    environment: :string,
    uid: :keep,
    references: :string,
    dry_run: :boolean,
    drop: :keep,
    map: :keep,
    apply: :boolean,
    wait: :boolean,
    timeout: :integer
  ]

  @impl Mix.Task
  def run(args) do
    {opts, command, user_id} = parse!(args)
    started = start!(Keyword.get(opts, :wait, true) and renders?(command, opts))

    try do
      user = Brando.Repo.get(Brando.Users.User, user_id)
      unless user && user.active && is_nil(user.deleted_at), do: Mix.raise("--user must identify an active account")
      prefix = context!(opts)
      Tenant.with_prefix(prefix, fn -> execute(command, opts, user) end)
    after
      # Oban's shutdown grace period lets a job this node's queue is running finish
      if started, do: Application.stop(started)
    end
  end

  defp parse!(args) do
    {opts, command} = OptionParser.parse!(args, strict: @switches)

    unless command in [["export"], ["import"], ["refresh"], ["resolve"]],
      do: Mix.raise("Expected export, import, refresh or resolve")

    user_id = opts[:user] || Mix.raise("--user ID is required")
    if (opts[:timeout] || 0) < 0, do: Mix.raise("--timeout takes a number of seconds")
    {opts, hd(command), user_id}
  end

  # Whether the command queues entry renders
  defp renders?("import", opts), do: !opts[:dry_run]
  defp renders?("refresh", _opts), do: true
  defp renders?("resolve", opts), do: !!opts[:apply]
  defp renders?(_command, _opts), do: false

  # Starts the application, unless it runs already (a test, another task),
  # and returns it when this started it
  defp start!(run_queues?) do
    Mix.Task.run("app.config")
    app = Brando.otp_app()

    if is_nil(app) or not List.keymember?(Application.started_applications(), app, 0) do
      configure_start(run_queues?)
      Mix.Task.run("app.start")
      app
    end
  end

  @doc false
  # The application this task starts runs no module definition watcher, and
  # of Oban's queues only the one entry renders run in, when it waits for
  # them: it fetches no job it would not finish.
  def configure_start(run_queues?) do
    Application.delete_env(:brando, Brando.Content.Definition.Watcher)
    oban = Application.get_env(:brando, Oban) || Brando.Supervisor.oban_config()
    queues = if run_queues?, do: render_queues(oban[:queues]), else: false
    Application.put_env(:brando, Oban, Keyword.put(oban, :queues, queues))
  end

  defp render_queues(queues) when is_list(queues) do
    names =
      Enum.uniq(for worker <- [Brando.Worker.EntryRenderer, Brando.Worker.EntryCascade], do: worker.__opts__()[:queue])

    Keyword.take(queues, names)
  end

  defp render_queues(queues), do: queues

  defp execute("export", opts, user) do
    directory = opts[:out] || Mix.raise("--out DIRECTORY is required")
    if opts[:dry_run], do: Mix.raise("--dry-run is supported by import")

    selection =
      case Keyword.get_values(opts, :uid) do
        [] -> []
        uids -> [uids: uids]
      end

    result = unwrap!(Definitions.export(directory, user, selection))
    Mix.shell().info("Exported #{length(result.bundle["modules"])} modules to #{result.directory}")
  end

  defp execute("import", opts, user) do
    directory = opts[:from] || Mix.raise("--from DIRECTORY is required")
    bundle = unwrap!(Definitions.read(directory))
    references = if opts[:references], do: opts[:references] |> File.read!() |> Jason.decode!(), else: %{}
    unless is_map(references), do: Mix.raise("--references must contain a JSON object")
    plan = unwrap!(Definitions.plan(bundle, user, references: references))

    Enum.each(plan.items, fn item ->
      detail = item.reason || Enum.join(item.fields, ", ")

      Mix.shell().info(
        "#{item.action} #{item.kind} #{item.uid}: #{detail} (#{item.block_count} blocks, #{item.entry_count} entries)"
      )
    end)

    unless Plan.applicable?(plan), do: Mix.raise("Resolve the conflicts or required migrations before importing")

    if opts[:dry_run],
      do: Mix.shell().info("Dry run: no definitions or files changed"),
      else: apply_import!(plan, directory, opts, user)
  end

  defp apply_import!(plan, directory, opts, user) do
    {result, run} = Definitions.track_refresh(fn -> Definitions.apply(plan, user) end)
    result = unwrap!(result)

    case Definitions.write_baseline(directory, result) do
      {:ok, :ok} ->
        :ok

      {:error, reason} ->
        Mix.raise(
          "Definitions committed, but the baseline could not be saved: #{inspect(reason)}. Export the target to a new directory before the next edit."
        )
    end

    Mix.shell().info("Applied #{length(result.changes)} definition changes; baseline saved")
    refreshed? = report_refresh(result.refresh)
    follow_renders!(run, opts)
    unless refreshed?, do: Mix.raise("Definitions are committed. Retry refresh for the reported UIDs.")
  end

  defp execute("refresh", opts, user) do
    uids = Keyword.get_values(opts, :uid)
    if uids == [], do: Mix.raise("refresh requires --uid UID")
    if opts[:dry_run], do: Mix.raise("--dry-run is supported by import")
    {result, run} = Definitions.track_refresh(fn -> Definitions.refresh(uids, user) end)
    refreshed? = result |> unwrap!() |> report_refresh()
    follow_renders!(run, opts)
    unless refreshed?, do: Mix.raise("Retry refresh for the reported UIDs.")
  end

  defp execute("resolve", opts, user) do
    uid =
      case Keyword.get_values(opts, :uid) do
        [uid] -> uid
        _ -> Mix.raise("resolve requires one --uid UID")
      end

    if opts[:dry_run], do: Mix.raise("resolve is a dry run unless --apply is given")
    report = uid |> StaleBlocks.report(user) |> unwrap_resolve!()
    resolutions = resolutions!(report, opts)
    plan = StaleBlocks.plan(report, resolutions)
    print_report(report, plan, resolutions)

    cond do
      report.blocks == [] ->
        :ok

      plan.refused != [] ->
        Enum.each(plan.refused, &Mix.shell().error("Refused in block ##{&1.block_id}: #{StaleBlocks.refusal_line(&1)}"))
        if opts[:apply], do: Mix.raise("Nothing was changed. Choose another target or drop the leftover.")

      !opts[:apply] ->
        Mix.shell().info("Dry run: nothing changed. Add --apply to write.")

      true ->
        {result, run} =
          Definitions.track_refresh(fn ->
            StaleBlocks.apply(report.module, resolutions, user, expect: plan.fingerprint)
          end)

        result = unwrap_resolve!(result)

        {revisioned, unrevisioned} = Enum.split_with(result.entries, & &1.revisioned?)

        Mix.shell().info(
          "Resolved #{length(result.changed)} blocks; #{length(result.stamped)} are now on version #{report.version}, " <>
            "#{length(result.remaining)} remain. A revision of #{length(revisioned)} of the #{length(result.entries)} " <>
            "changed entries was stored first." <> no_revisions(unrevisioned)
        )

        follow_renders!(run, opts)
    end
  end

  defp resolutions!(report, opts) do
    drops =
      for key <- Keyword.get_values(opts, :drop), selector <- selectors!(report, key), into: %{}, do: {selector, :drop}

    maps =
      for pair <- Keyword.get_values(opts, :map), into: %{} do
        case String.split(pair, "=", parts: 2) do
          [old, new] when old != "" and new != "" ->
            [selector] = selectors!(report, old) |> Enum.take(1)
            {selector, {:map, new}}

          _ ->
            Mix.raise("--map expects OLD=NEW, got #{inspect(pair)}")
        end
      end

    Map.merge(drops, maps)
  end

  # `KEY`, `ref:KEY` or `var:KEY`, matched against the leftovers found.
  defp selectors!(report, key) do
    {kinds, key} =
      case String.split(key, ":", parts: 2) do
        ["ref", key] -> {[:ref], key}
        ["var", key] -> {[:var], key}
        _ -> {[:ref, :var], key}
      end

    case for(group <- report.groups, group.kind in kinds, group.key == key, do: {group.kind, key}) do
      [] -> Mix.raise("No block of #{report.module.uid} holds a leftover #{key}")
      selectors -> selectors
    end
  end

  defp print_report(report, plan, resolutions) do
    name = StaleBlocks.module_name(report.module)

    Mix.shell().info(
      "#{name} (#{report.module.uid}) is on version #{report.version}; #{length(report.blocks)} blocks are behind."
    )

    Enum.each(report.blocks, &print_block(&1, resolutions))
    print_groups(report.groups)
    print_lost(plan.lost)
  end

  defp print_block(block, resolutions) do
    shell = Mix.shell()
    where = Enum.map_join(block.entries, ", ", &"#{&1.label} (#{&1.type}#{language(&1)}#{trashed(&1)})")
    where = if where == "", do: "not in any entry", else: where
    shell.info("\n  Block ##{block.id} on version #{block.module_version || "none"}: #{where}")

    if block.leftovers == [] and block.problems == [],
      do: shell.info("    nothing left over; re-syncing brings it up to date")

    Enum.each(block.problems, &shell.info("    #{&1}"))
    Enum.each(block.leftovers, &shell.info("    #{leftover_line(&1)}#{action_line(resolutions, block.id, &1)}"))
  end

  defp print_groups([]), do: :ok

  defp print_groups(groups) do
    Mix.shell().info("\nLeftovers:")

    Enum.each(groups, fn group ->
      targets = for t <- group.targets, t.ok?, do: "#{t.key} (#{t.type})"
      targets = if targets == [], do: "none", else: Enum.join(targets, ", ")
      Mix.shell().info("  #{group.kind} #{group.key} in #{length(group.blocks)} blocks; can map to: #{targets}")
    end)
  end

  defp print_lost([]), do: :ok

  defp print_lost(lost) do
    Mix.shell().info("\nThese values will be lost:")
    Enum.each(lost, &Mix.shell().info("  block ##{&1.block_id} #{&1.kind} #{&1.key}: #{&1.lost || &1.replaces}"))
  end

  defp leftover_line(%{reason: :retyped} = leftover),
    do:
      "#{leftover.kind} #{leftover.key} (#{leftover.type}, the module now has a #{leftover.defined_type}): #{inspect(leftover.preview)}"

  defp leftover_line(leftover), do: "#{leftover.kind} #{leftover.key} (#{leftover.type}): #{inspect(leftover.preview)}"

  defp action_line(resolutions, block_id, %{kind: kind, key: key}) do
    case Map.get(resolutions, {block_id, kind, key}) || Map.get(resolutions, {kind, key}) do
      :drop -> " → drop"
      {:map, target} -> " → map to #{target}"
      _ -> ""
    end
  end

  defp language(%{language: nil}), do: ""
  defp language(%{language: language}), do: ", #{language}"

  defp trashed(%{trashed?: true}), do: ", in the trash"
  defp trashed(_entry), do: ""

  defp no_revisions([]), do: ""

  defp no_revisions(entries),
    do: " History cannot restore what keeps no revisions: #{Enum.map_join(entries, ", ", & &1.label)}."

  defp unwrap_resolve!({:ok, value}), do: value
  defp unwrap_resolve!({:error, reason}), do: Mix.raise("Resolve: #{reason}")

  # Whether every module was refreshed
  defp report_refresh(results) do
    Enum.each(results, fn result ->
      if result.status == :failed do
        Mix.shell().error("Refresh failed for #{result.uid}: #{result.error}")
      else
        Mix.shell().info("Refresh requested for #{result.uid}; #{length(result.stale_block_ids)} stale blocks remain")
        explain_stale(result)
      end
    end)

    not Enum.any?(results, &(&1.status == :failed))
  end

  # Waits for the renders `run` queued (`Brando.Content.Definitions.await_refresh/2`),
  # or, with `--no-wait`, says how many it left queued
  defp follow_renders!(run, opts) do
    if Keyword.get(opts, :wait, true) do
      timeout = if opts[:timeout], do: :timer.seconds(opts[:timeout]), else: @default_timeout
      run |> Definitions.await_refresh(timeout: timeout, on_progress: &progress/1) |> report_renders!(timeout)
    else
      report_queued(Definitions.refresh_status(run))
    end
  end

  defp progress(%{total: 0}), do: :ok

  defp progress(%{done: done, total: total, failed: failed}) do
    failed = if failed > 0, do: " (#{failed} failed)", else: ""
    Mix.shell().info("Rendering entries: #{done} of #{total} done#{failed}")
  end

  defp report_renders!(%{failed: [], pending: [], rendered: rendered}, _timeout) do
    if rendered > 0, do: Mix.shell().info("Rendered #{rendered} entries")
  end

  defp report_renders!(%{failed: failed, pending: pending, rendered: rendered, timed_out: timed_out}, timeout) do
    if rendered > 0, do: Mix.shell().info("Rendered #{rendered} entries")
    Enum.each(failed, &Mix.shell().error("#{failure(&1)} failed for #{entry_name(&1)}: #{first_line(&1.error)}"))
    Enum.each(pending, &Mix.shell().error("Still #{&1.state}: #{job_name(&1)}"))

    if timed_out do
      Mix.raise(
        "Timed out after #{div(timeout, 1000)} seconds with #{length(pending)} jobs left. They stay queued for a " <>
          "node that runs Oban's queues; a render that failed is retried there."
      )
    else
      Mix.raise(
        "#{length(failed)} entries failed to render. Oban retries a failed render on a node that runs its " <>
          "queue; fix the cause, then run refresh for the module."
      )
    end
  end

  defp report_queued(%{pending: pending}) do
    {renders, cascades} = Enum.split_with(pending, &(&1.worker == :render))
    more = if cascades == [], do: "", else: ", and #{length(cascades)} cascade jobs that may queue more"

    Mix.shell().info(
      "#{length(renders)} entry renders are queued for the running server#{more}. " <>
        "Without a server running Oban's queues they wait until one starts."
    )
  end

  defp failure(%{worker: :cascade}), do: "Cascade"
  defp failure(_job), do: "Render"

  defp job_name(%{worker: :cascade} = job), do: "cascade for #{entry_name(job)}"
  defp job_name(job), do: "render of #{entry_name(job)}"

  defp entry_name(%{schema: schema, entry_id: id, tenant_prefix: nil}), do: "#{schema} ##{id}"
  defp entry_name(%{schema: schema, entry_id: id, tenant_prefix: prefix}), do: "#{schema} ##{id} in #{prefix}"

  defp first_line(nil), do: "no error recorded"
  defp first_line(error), do: error |> String.split("\n", parts: 2) |> hd()

  # A refresh re-renders; it cannot bring a block holding content the module
  # no longer defines up to date. Say what holds them back and where to go.
  defp explain_stale(%{stale_block_ids: []}), do: :ok

  defp explain_stale(%{uid: uid}) do
    case StaleBlocks.report(uid, :system) do
      {:ok, %{groups: groups, module: module}} ->
        held = Enum.map_join(groups, ", ", &"#{&1.kind} #{&1.key} (#{length(&1.blocks)} blocks)")

        if held != "",
          do: Mix.shell().info("  They hold refs or vars the module no longer defines: #{held}.")

        Mix.shell().info(
          "  Resolve them with: mix brando.modules resolve --uid #{uid} --user ID\n" <>
            "  or in the admin: /admin/config/content/modules/update/#{module.id}/stale-blocks"
        )

      {:error, _} ->
        :ok
    end
  end

  defp context!(opts) do
    if Tenant.mode() == :none do
      if opts[:site] || opts[:environment], do: Mix.raise("Site/environment options require tenant mode")
      nil
    else
      site_key = opts[:site] || Mix.raise("--site is required")
      environment_key = opts[:environment] || Mix.raise("--environment is required")
      site = Registry.get_site_by_key(site_key) || Mix.raise("Unknown site #{site_key}")

      environment =
        Registry.get_environment_by_key(site, environment_key) || Mix.raise("Unknown environment #{environment_key}")

      Tenant.prefix(site, environment)
    end
  end

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, reason}), do: Mix.raise("Module definitions: #{inspect(reason)}")
end
