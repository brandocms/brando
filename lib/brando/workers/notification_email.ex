defmodule Brando.Worker.NotificationEmail do
  @moduledoc """
  Sends a mention email or an email summary that `Brando.Worker.NoteMentions`
  queued, in the site it was queued from. The job carries what to send (the
  mentions and routed notifications), not the email: each attempt builds
  the email again, leaving out what the user may no longer see, so an email
  retried later never shows them an entry they lost access to meanwhile
  (`Brando.Notifications.Digest.send_queued/1`). Tries again when the mail
  provider fails. When the last attempt fails, its notifications are marked
  failed, to be sent again from the delivery log, and its mentions go with
  the next email (`Brando.Notifications.Digest.give_up/2`).
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Brando.Notifications.Digest
  alias Brando.Notifications.Recipient
  alias Brando.Tenant.Job, as: TenantJob

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    final? = final?(job)

    # On the last attempt, what cannot be checked is left out (`Recipient`)
    result =
      Recipient.final_attempt(final?, fn ->
        TenantJob.run_current(job, fn -> Digest.send_queued(args) end)
      end)

    case result do
      {:error, reason} when final? ->
        give_up(job, "mail_failed", "the mail provider refused it: " <> inspect(reason))
        result

      _ ->
        result
    end
  rescue
    error ->
      if final?(job), do: give_up(job, "email_failed", Exception.message(error))
      reraise error, __STACKTRACE__
  end

  defp final?(job), do: job.attempt >= job.max_attempts

  # Its last attempt failed: what it took goes back (`Digest.give_up/2`)
  defp give_up(job, error, detail) do
    Logger.error("[Brando.Notifications] Email job ##{job.id} gave up: " <> detail)
    TenantJob.run_current(job, fn -> Digest.give_up(job.args, error) end)
  rescue
    error -> Logger.error("[Brando.Notifications] Email job ##{job.id} could not give back: " <> Exception.message(error))
  end
end
