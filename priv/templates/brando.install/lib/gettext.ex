defmodule <%= base %>.Gettext do
  use Gettext, otp_app: :<%= application_name %>, priv: "priv/gettext/frontend"
end

defmodule <%= base %>.Backend.Gettext do
  use Gettext, otp_app: :<%= application_name %>, priv: "priv/gettext/backend"
end