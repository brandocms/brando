defmodule Brando.Worker.NotFoundPurger do
  @moduledoc """
  Deletes 404 log rows older than `Brando.Sites.FourOhFour.retention_days/0`,
  in every active environment.
  """
  use Oban.Worker, queue: :default, max_attempts: 2

  require Logger

  alias Brando.Sites.FourOhFour
  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(_) do
    purged =
      :all
      |> TenantJob.each_active_environment(fn -> FourOhFour.purge() end)
      |> Enum.sum()

    Logger.info("==> [CRON] Deleted #{purged} 404 log rows older than #{FourOhFour.retention_days()} days")
    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
