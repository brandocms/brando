defmodule Brando.Worker.PasswordReset do
  @moduledoc """
  Sends a password reset link: one asked for with
  `Brando.Users.request_password_reset/1`, if the email belongs to an active
  account, or one an administrator sent with
  `Brando.Users.send_password_reset/2`. Looking the account up here, rather
  than in the request, keeps the request the same whether or not it exists.

  The job carries the email address or the user's id, never the link: the
  token is made and the email sent when the job runs, so the raw token is
  kept in no job row.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email" => email}} = job) when is_binary(email) do
    TenantJob.run_current(job, fn -> email |> Brando.Users.deliver_password_reset() |> result() end)
  end

  def perform(%Oban.Job{args: %{"user_id" => user_id, "reason" => "admin"}} = job) when is_integer(user_id) do
    TenantJob.run_current(job, fn -> user_id |> Brando.Users.deliver_admin_password_reset() |> result() end)
  end

  # Without a mailer or sender, another attempt cannot do better
  defp result({:error, reason}) when reason in [:no_mailer, :no_sender], do: {:cancel, reason}
  defp result(result), do: result
end
