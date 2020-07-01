defmodule <%= application_module %>.Mailer do
  use Swoosh.Mailer, otp_app: :<%= application_name %>
end
