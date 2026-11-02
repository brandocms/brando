defmodule Brando.Worker.SoftDeletePurger do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 2

  require Logger

  alias Brando.SoftDelete.Query
  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(_) do
    Logger.info("==> [CRON] Cleaning up soft deleted entries...")
    # One run for every environment: a provider one of them could not reach
    # is not asked again by the others, within the timeout below.
    Query.as_one_run(fn -> TenantJob.each_active_environment(:all, &Query.clean_up_soft_deletions/0) end)
    Logger.info("==> [CRON] Cleaning up soft deleted entries... done")
    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
