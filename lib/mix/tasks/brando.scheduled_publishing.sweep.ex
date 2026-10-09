defmodule Mix.Tasks.Brando.ScheduledPublishing.Sweep do
  use Mix.Task

  @shortdoc "Lists (or makes) the publishing and expiries whose dates passed with no job"

  @moduledoc """
  Shows what `Brando.Worker.ScheduledPublishingSweep` would do, in every
  environment of every active site: pending entries whose `publish_at` has
  passed, which it publishes, and published or pending entries whose
  `unpublish_at` has passed, which it deactivates. Only dates from the last
  seven days count (`config :brando, Brando.Publisher, sweep_days: 7`).

      mix brando.scheduled_publishing.sweep          # list, change nothing
      mix brando.scheduled_publishing.sweep --apply  # do it now

  Run it before the first deploy with the sweep, to see what it will publish.
  See `Brando.Publisher.sweep/1`.
  """

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [apply: :boolean])
    apply? = Keyword.get(opts, :apply, false)

    Application.put_env(:logger, :level, :error)
    Mix.Tasks.Run.run([])

    results =
      :all
      |> Brando.Tenant.Job.each_active_environment(fn ->
        prefix = Brando.Tenant.current_prefix() || "public"
        Enum.map(Brando.Publisher.sweep(dry_run: not apply?), &Map.put(&1, :environment, prefix))
      end)
      |> List.flatten()

    report(results, apply?)
  end

  @doc false
  def report([], _apply?), do: Mix.shell().info("Nothing to publish or deactivate.")

  def report(results, apply?) do
    for result <- results do
      Mix.shell().info(
        "#{result.environment}  #{verb(result.action, apply?)}  #{inspect(result.schema)} ##{result.id} " <>
          "#{inspect(result.title)} (#{DateTime.to_iso8601(result.at)})#{outcome(result.result)}"
      )
    end

    unless apply?, do: Mix.shell().info("\n#{length(results)} entries. Nothing changed; run with --apply to do it.")
  end

  defp verb(:publish, false), do: "would publish   "
  defp verb(:unpublish, false), do: "would deactivate"
  defp verb(:publish, true), do: "published       "
  defp verb(:unpublish, true), do: "deactivated     "

  defp outcome({:error, reason}), do: "  FAILED: #{inspect(reason)}"
  defp outcome(_), do: ""
end
