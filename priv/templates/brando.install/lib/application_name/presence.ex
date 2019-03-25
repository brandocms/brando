defmodule <%= application_module %>.Presence do
  use Phoenix.Presence, otp_app: :<%= application_name %>, pubsub_server: <%= application_module %>.PubSub
end
