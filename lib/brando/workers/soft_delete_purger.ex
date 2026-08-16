defmodule Brando.Worker.SoftDeletePurger do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 2

  require Logger

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(_) do
    Logger.info("==> [CRON] Cleaning up soft deleted entries...")
    TenantJob.each_active_environment(:all, &Brando.SoftDelete.Query.clean_up_soft_deletions/0)
    Logger.info("==> [CRON] Cleaning up soft deleted entries... done")
    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
