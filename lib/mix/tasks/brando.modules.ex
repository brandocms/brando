defmodule Mix.Tasks.Brando.Modules do
  @shortdoc "Export, plan and import module-definition DSL files"
  @moduledoc """
  Exports and imports complete module definitions, including refs, vars, children,
  table templates and adjacent HEEx/Liquid source.

      mix brando.modules export --out priv/modules --user 1
      mix brando.modules import --from priv/modules --user 1 --dry-run
      mix brando.modules import --from priv/modules --user 1
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
    apply: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, command} = OptionParser.parse!(args, strict: @switches)

    unless command in [["export"], ["import"], ["refresh"], ["resolve"]],
      do: Mix.raise("Expected export, import, refresh or resolve")

    user_id = opts[:user] || Mix.raise("--user ID is required")
    Mix.Task.run("app.start")
    user = Brando.Repo.get(Brando.Users.User, user_id)
    unless user && user.active && is_nil(user.deleted_at), do: Mix.raise("--user must identify an active account")
    prefix = context!(opts)
    Tenant.with_prefix(prefix, fn -> execute(hd(command), opts, user) end)
  end

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

    if opts[:dry_run] do
      Mix.shell().info("Dry run: no definitions or files changed")
    else
      result = unwrap!(Definitions.apply(plan, user))

      case Definitions.write_baseline(directory, result) do
        {:ok, :ok} ->
          :ok

        {:error, reason} ->
          Mix.raise(
            "Definitions committed, but the baseline could not be saved: #{inspect(reason)}. Export the target to a new directory before the next edit."
          )
      end

      Mix.shell().info("Applied #{length(result.changes)} definition changes; baseline saved")
      report_refresh!(result.refresh)
    end
  end

  defp execute("refresh", opts, user) do
    uids = Keyword.get_values(opts, :uid)
    if uids == [], do: Mix.raise("refresh requires --uid UID")
    if opts[:dry_run], do: Mix.raise("--dry-run is supported by import")
    Definitions.refresh(uids, user) |> unwrap!() |> report_refresh!()
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
        result =
          report.module
          |> StaleBlocks.apply(resolutions, user, expect: plan.fingerprint)
          |> unwrap_resolve!()

        {revisioned, unrevisioned} = Enum.split_with(result.entries, & &1.revisioned?)

        Mix.shell().info(
          "Resolved #{length(result.changed)} blocks; #{length(result.stamped)} are now on version #{report.version}, " <>
            "#{length(result.remaining)} remain. A revision of #{length(revisioned)} of the #{length(result.entries)} " <>
            "changed entries was stored first." <> no_revisions(unrevisioned)
        )
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

  defp report_refresh!(results) do
    Enum.each(results, fn result ->
      if result.status == :failed do
        Mix.shell().error("Refresh failed for #{result.uid}: #{result.error}")
      else
        Mix.shell().info("Refresh requested for #{result.uid}; #{length(result.stale_block_ids)} stale blocks remain")
        explain_stale(result)
      end
    end)

    if Enum.any?(results, &(&1.status == :failed)),
      do: Mix.raise("Definitions are committed. Retry refresh for the reported UIDs.")
  end

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
