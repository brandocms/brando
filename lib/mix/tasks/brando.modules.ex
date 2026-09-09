defmodule Mix.Tasks.Brando.Modules do
  @shortdoc "Export, plan and import module-definition DSL files"
  @moduledoc """
  Exports and imports complete module definitions, including refs, vars, children,
  table templates and adjacent HEEx/Liquid source.

      mix brando.modules export --out priv/modules --user 1
      mix brando.modules import --from priv/modules --user 1 --dry-run
      mix brando.modules import --from priv/modules --user 1
      mix brando.modules refresh --uid hero-uid --user 1

  Tenant applications must select `--site KEY --environment KEY`. Standalone
  applications omit both. Every command requires an active `--user ID` and uses
  the account's normal authorization. Export accepts repeatable `--uid UID` to
  select complete trees. Import accepts `--references FILE`, a JSON object mapping
  exported asset tokens to destination record IDs.

  Export requires a new output directory. Import prints a plan, refuses conflicts
  and structural migrations, and updates only the baseline lockfile after a
  successful apply. `--dry-run` performs no database or file writes.

  See the [module definitions guide](module_definitions.md).
  """
  use Mix.Task

  alias Brando.Content.Definitions
  alias Brando.Content.Definition.Plan
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
    dry_run: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, command} = OptionParser.parse!(args, strict: @switches)
    unless command in [["export"], ["import"], ["refresh"]], do: Mix.raise("Expected export, import or refresh")
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

  defp report_refresh!(results) do
    Enum.each(results, fn result ->
      if result.status == :failed do
        Mix.shell().error("Refresh failed for #{result.uid}: #{result.error}")
      else
        Mix.shell().info("Refresh requested for #{result.uid}; #{length(result.stale_block_ids)} stale blocks remain")
      end
    end)

    if Enum.any?(results, &(&1.status == :failed)),
      do: Mix.raise("Definitions are committed. Retry refresh for the reported UIDs.")
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
