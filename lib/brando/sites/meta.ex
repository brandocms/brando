defmodule Brando.Meta do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "Meta",
    singular: "meta",
    plural: "metas"

  data_layer :embedded
  identifier "{{ entry.key }}"

  attributes do
    attribute :key, :string, required: true
    attribute :value, :string, required: true
  end
end
