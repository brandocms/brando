defmodule Brando.Content.Var.Boolean do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "VarBoolean",
    singular: "var_boolean",
    plural: "var_booleans",
    gettext_module: Brando.Gettext

  data_layer :embedded
  @primary_key false

  identifier "{{ entry.label }}"

  attributes do
    attribute :type, :string, required: true
    attribute :label, :string, required: true
    attribute :key, :string, required: true
    attribute :value, :boolean, required: true, default: false
    attribute :important, :boolean, default: false
  end
end
