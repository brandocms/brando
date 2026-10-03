defmodule BrandoIntegration.Mailer do
  use Swoosh.Mailer, otp_app: :brando
end

defmodule BrandoIntegration.FailingMailer do
  @moduledoc "A mailer whose provider refuses every email, for tests of what Brando records."
  def deliver(_email), do: {:error, {503, "Service unavailable"}}
end
