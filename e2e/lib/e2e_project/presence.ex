defmodule E2eProject.Presence do
  use BrandoAdmin.Presence,
    otp_app: :e2e_project,
    pubsub_server: E2eProject.PubSub,
    presence: __MODULE__
end
