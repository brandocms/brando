defmodule Brando.Worker.ScheduledPublishingSweep do
  @moduledoc """
  Publishes and deactivates entries whose `publish_at` or `unpublish_at` has
  passed with no job to do it, in every active environment
  (`Brando.Publisher.sweep/1`). Dates come without jobs when an environment
  is cloned or an archive restored.
  """
  use Oban.Worker, queue: :default, max_attempts: 2, unique: [period: 300]

  require Logger

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(_job) do
    swept =
      :all
      |> TenantJob.each_active_environment(fn -> Brando.Publisher.sweep() end)
      |> Enum.sum()

    if swept > 0, do: Logger.info("==> [CRON] Published or deactivated #{swept} entries whose date had passed")
    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(60)
end
