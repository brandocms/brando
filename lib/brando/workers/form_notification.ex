defmodule Brando.Worker.FormNotification do
  @moduledoc """
  Sends a form submission's notification to the form's recipients, in the
  site it was sent in, and records the outcome on the submission. See
  `Brando.Forms.Notification`.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"submission_id" => id}} = job) do
    TenantJob.run(job, fn -> Brando.Forms.Notification.deliver(id) end)
  end
end
