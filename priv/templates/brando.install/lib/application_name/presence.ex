defmodule <%= application_module %>.Presence do
  use BrandoAdmin.Presence,
    otp_app: :<%= application_name %>,
    pubsub_server: <%= application_module %>.PubSub,
    presence: __MODULE__
end
