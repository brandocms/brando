defmodule Brando.Worker.SoftDeletePurger do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 2

  require Logger

  alias Brando.SoftDelete.Query
  alias Brando.Tenant.Job, as: TenantJob

  # Every schema in every environment is attempted. A failure in one is
  # logged where it happened, and the job then fails, so it shows.
  @impl Oban.Worker
  def perform(_) do
    Logger.info("==> [CRON] Cleaning up soft deleted entries...")
    # One run for every environment: a provider one of them could not reach
    # is not asked again by the others, within the timeout below.
    failed =
      fn -> TenantJob.each_active_environment(:all, &purge_environment/0) end
      |> Query.as_one_run()
      |> Enum.sum()

    Logger.info("==> [CRON] Cleaning up soft deleted entries... done")

    if failed == 0, do: :ok, else: {:error, "the trash purge failed #{failed} time(s): see the log"}
  end

  # How many schemas failed in the current environment, or 1 when it failed
  # before or between them
  defp purge_environment do
    Enum.count(Query.clean_up_soft_deletions(), &(not purged?(&1)))
  rescue
    error ->
      Logger.error("[Brando.SoftDelete] Purging the trash#{Query.environment()} failed: #{Query.describe_error(error)}")

      1
  end

  # A schema's result: `{:ok, {count, nil}}`, or `{count, nil}` for videos.
  # Anything else failed, and `Query.clean_up_soft_deletions/0` logged it.
  defp purged?({:ok, _result}), do: true
  defp purged?({count, _}) when is_integer(count), do: true
  defp purged?(_result), do: false

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
