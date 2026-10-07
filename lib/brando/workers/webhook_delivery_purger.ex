defmodule Brando.Worker.WebhookDeliveryPurger do
  @moduledoc """
  Deletes webhook deliveries older than `Brando.Webhooks.retention_days/0`
  (default 30), in every active environment.
  """
  use Oban.Worker, queue: :default, max_attempts: 2

  require Logger

  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Webhooks

  @impl Oban.Worker
  def perform(_) do
    purged =
      :all
      |> TenantJob.each_active_environment(fn -> Webhooks.purge_deliveries() end)
      |> Enum.sum()

    Logger.info("==> [CRON] Deleted #{purged} webhook deliveries older than #{Webhooks.retention_days()} days")
    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
