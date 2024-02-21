defmodule Brando.Content.Var.File do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "VarFile",
    singular: "var_file",
    plural: "var_files",
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
    relation :value, :belongs_to, module: Brando.Files.File
  end
end
