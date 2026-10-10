defmodule Brando.Worker.NotificationEmail do
  @moduledoc """
  Sends a mention email or an email summary that `Brando.Worker.NoteMentions`
  queued, in the site it was queued from. The job carries what to send (the
  mentions and routed notifications), not the email: each attempt builds
  the email again, leaving out what the user may no longer see, so an email
  retried later never shows them an entry they lost access to meanwhile
  (`Brando.Notifications.Digest.send_queued/1`). Tries again when the mail
  provider fails.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Brando.Notifications.Recipient
  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    # On the last attempt, what cannot be checked is left out (`Recipient`)
    Recipient.final_attempt(job.attempt >= job.max_attempts, fn ->
      TenantJob.run_current(job, fn -> Brando.Notifications.Digest.send_queued(args) end)
    end)
  end
end
