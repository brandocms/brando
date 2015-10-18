defmodule <%= application_module %>.Gettext do
  use Gettext, otp_app: :<%= application_name %>, priv: "priv/gettext/frontend"
end

defmodule <%= application_module %>.Backend.Gettext do
  use Gettext, otp_app: :<%= application_name %>, priv: "priv/gettext/backend"
end