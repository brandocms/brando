defmodule Brando.Content.Var.Datetime do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "VarDatetime",
    singular: "var_datetime",
    plural: "var_datetimes",
    gettext_module: Brando.Gettext

  data_layer :embedded
  @primary_key false

  identifier "{{ entry.label }}"

  attributes do
    attribute :type, :string, required: true
    attribute :label, :string, required: true
    attribute :key, :string, required: true
    attribute :value, :datetime
    attribute :important, :boolean, default: false
    attribute :placeholder, :string
    attribute :instructions, :string
  end
end
