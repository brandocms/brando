defmodule Brando.Content.Var.Color do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "VarColor",
    singular: "var_color",
    plural: "var_colors",
    gettext_module: Brando.Gettext

  data_layer :embedded
  @primary_key false

  identifier "{{ entry.label }}"

  attributes do
    attribute :type, :string, required: true
    attribute :label, :string, required: true
    attribute :key, :string, required: true
    attribute :value, :string
    attribute :important, :boolean, default: false
  end
end
