defmodule Brando.Worker.RevisionPurger do
  use Oban.Worker, queue: :default, max_attempts: 2
  require Logger

  @impl Oban.Worker
  def perform(_) do
    Logger.info("==> [CRON] Cleaning up revisions")
    {purged_revisions, _} = Brando.Revisions.purge_revisions()
    Logger.info("==> [CRON] Deleted #{purged_revisions} unprotected/inactive revisions")
    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(10)
end
