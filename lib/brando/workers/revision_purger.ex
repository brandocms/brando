defmodule Brando.Worker.RevisionPurger do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 2

  require Logger

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(_) do
    Logger.info("==> [CRON] Cleaning up revisions")

    purged_revisions =
      TenantJob.each_active_environment(:all, &Brando.Revisions.purge_revisions/0)
      |> Enum.reduce(0, fn {count, _}, total -> total + count end)

    Logger.info("==> [CRON] Deleted #{purged_revisions} unprotected/inactive revisions")
    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(10)
end
