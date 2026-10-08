defmodule Brando.Worker.NotificationDispatch do
  @moduledoc """
  Hands a given-up job to the `failed_job` notification routes of the site
  and environment it belonged to (`Brando.Notifications.JobFailures`).
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    TenantJob.run_current(job, fn ->
      Brando.Notifications.Routing.job_failed(%{
        "worker" => args["failed_worker"],
        "queue" => args["queue"],
        "attempt" => args["attempt"],
        "max_attempts" => args["max_attempts"],
        "error" => args["error"],
        "id" => args["job_id"]
      })
    end)
  end
end
