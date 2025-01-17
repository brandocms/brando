defmodule Brando.Content.Var.Option do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "VarSelectOption",
    singular: "var_select_option",
    plural: "var_select_options",
    gettext_module: Brando.Gettext

  @primary_key false
  data_layer :embedded

  identifier false
  persist_identifier false

  attributes do
    attribute :label, :text, required: true
    attribute :value, :text, required: true
  end
end
