defmodule Brando.Config do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "Config",
    singular: "config",
    plural: "configs",
    gettext_module: Brando.Gettext

  identifier false
  persist_identifier false

  attributes do
    attribute :lockdown_enabled, :boolean, default: false
    attribute :lockdown_password, :string
  end
end
