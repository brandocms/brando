defmodule Brando.Worker.PasswordReset do
  @moduledoc """
  Sends a password reset link asked for with
  `Brando.Users.request_password_reset/1`, if the email belongs to an active
  account. Looking the account up here, rather than in the request, keeps the
  request the same whether or not it exists.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email" => email}} = job) when is_binary(email) do
    TenantJob.run_current(job, fn -> Brando.Users.deliver_password_reset(email) end)
  end
end
