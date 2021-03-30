defmodule Brando.Sites.Redirect do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "Redirect",
    singular: "redirect",
    plural: "redirects"

  data_layer :embedded
  identifier "{{ entry.from }} -> {{ entry.to }}"

  attributes do
    attribute :to, :string, required: true
    attribute :from, :string, required: true
    attribute :code, :text, required: true
  end
end
