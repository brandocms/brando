defmodule Brando.Meta do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "Meta",
    singular: "meta",
    plural: "metas",
    gettext_module: Brando.Gettext

  data_layer :embedded

  identifier false
  persist_identifier false

  attributes do
    attribute :key, :string, required: true
    attribute :value, :string, required: true
  end
end
