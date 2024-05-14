# TODO: DELETE
defmodule Brando.Content.OldVar.Text do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "VarText",
    singular: "var_text",
    plural: "var_texts",
    gettext_module: Brando.Gettext

  data_layer :embedded
  @primary_key false

  identifier "{{ entry.label }}"

  attributes do
    attribute :type, :string, required: true
    attribute :label, :string, required: true
    attribute :key, :string, required: true
    attribute :value, :text
    attribute :important, :boolean, default: false
    attribute :placeholder, :string
    attribute :instructions, :string
  end
end
