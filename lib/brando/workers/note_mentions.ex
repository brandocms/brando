defmodule Brando.Worker.NoteMentions do
  @moduledoc """
  Emails a user the notes they were mentioned in, in the site they were
  mentioned in. One job per user waits at a time, and a user gets one email
  at most every ten minutes: a job that runs sooner snoozes until then, and
  the email it finally sends collects every mention made meanwhile. See
  `Brando.Notes.deliver_mentions/2`.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [keys: [:tenant_prefix, :user_id], states: [:available, :scheduled, :retryable]]

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}} = job) when is_integer(user_id) do
    TenantJob.run_current(job, fn -> Brando.Notes.deliver_mentions(user_id) end)
  end
end
