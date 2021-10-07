defmodule Brando.ConfigEntry do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "Config",
    singular: "config",
    plural: "configs",
    gettext_module: Brando.Gettext

  data_layer :embedded
  identifier "{{ entry.key }}"

  attributes do
    attribute :key, :string, required: true
    attribute :value, :string, required: true
  end
end
