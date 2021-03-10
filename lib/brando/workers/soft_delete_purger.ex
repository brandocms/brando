defmodule Brando.Worker.SoftDeletePurger do
  use Oban.Worker, queue: :default, max_attempts: 2
  require Logger

  @impl Oban.Worker
  def perform(_) do
    Logger.info("==> [CRON] Cleaning up soft deleted entries...")
    Brando.SoftDelete.Query.clean_up_soft_deletions()
    Logger.info("==> [CRON] Cleaning up soft deleted entries... done")
    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
