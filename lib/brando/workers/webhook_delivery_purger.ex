defmodule Brando.Worker.WebhookDeliveryPurger do
  @moduledoc """
  Deletes webhook deliveries and notification deliveries older than
  `Brando.Webhooks.retention_days/0` (default 30), in every active
  environment. Notifications still waiting for a digest stay.
  """
  use Oban.Worker, queue: :default, max_attempts: 2

  require Logger

  alias Brando.Notifications.Routing
  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Webhooks

  @impl Oban.Worker
  def perform(_) do
    {webhooks, notifications} =
      :all
      |> TenantJob.each_active_environment(fn -> {Webhooks.purge_deliveries(), Routing.purge_deliveries()} end)
      |> Enum.reduce({0, 0}, fn {w, n}, {ws, ns} -> {ws + w, ns + n} end)

    Logger.info(
      "==> [CRON] Deleted #{webhooks} webhook deliveries and #{notifications} notification deliveries " <>
        "older than #{Webhooks.retention_days()} days"
    )

    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
