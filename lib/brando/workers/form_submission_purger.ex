defmodule Brando.Worker.FormSubmissionPurger do
  @moduledoc """
  Deletes form submissions older than their form's `retention_days`, in every
  active environment. A form without it keeps its submissions.
  """
  use Oban.Worker, queue: :default, max_attempts: 2

  require Logger

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(_) do
    purged =
      :all
      |> TenantJob.each_active_environment(fn -> Brando.Forms.purge_submissions() end)
      |> Enum.sum()

    Logger.info("==> [CRON] Deleted #{purged} form submissions past their form's retention")
    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
