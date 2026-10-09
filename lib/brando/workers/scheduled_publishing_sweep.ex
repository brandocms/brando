defmodule Brando.Worker.ScheduledPublishingSweep do
  @moduledoc """
  Publishes and deactivates entries whose `publish_at` or `unpublish_at` has
  passed with no job to do it, in every active environment
  (`Brando.Publisher.sweep/1`). Dates come without jobs when an environment
  is cloned or an archive restored. An environment that fails is logged and
  the others carry on.
  """
  use Oban.Worker, queue: :default, max_attempts: 2, unique: [period: 300]

  require Logger

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(_job) do
    results = :all |> TenantJob.each_active_environment(&sweep_environment/0) |> List.flatten()
    changed = Enum.count(results, &(&1.result == :ok))
    failed = Enum.count(results, &match?({:error, _}, &1.result))

    if changed + failed > 0,
      do: Logger.info("==> [CRON] Swept scheduled publishing: #{changed} entries changed, #{failed} failed")

    :ok
  end

  defp sweep_environment do
    Brando.Publisher.sweep()
  rescue
    error ->
      Logger.error(
        "[Brando.Worker.ScheduledPublishingSweep] #{Brando.Tenant.current_prefix() || "public"}: " <>
          Exception.message(error)
      )

      []
  end

  # Every environment in one run, each a few queries when nothing is due
  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)
end
