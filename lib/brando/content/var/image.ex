# TODO: DELETE
defmodule Brando.Content.OldVar.Image do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "VarImage",
    singular: "var_image",
    plural: "var_images",
    gettext_module: Brando.Gettext

  data_layer :embedded
  @primary_key false

  identifier "{{ entry.label }}"

  attributes do
    attribute :type, :string, required: true
    attribute :label, :string, required: true
    attribute :key, :string, required: true
    attribute :important, :boolean, default: false
    attribute :placeholder, :string
    attribute :instructions, :string
  end

  relations do
    relation :value, :belongs_to, module: Brando.Images.Image
  end
end
