defmodule Brando.Navigation.Item do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Navigation",
    schema: "Item",
    singular: "item",
    plural: "items",
    gettext_module: Brando.Gettext

  data_layer :embedded
  identifier "{{ entry.title }}"

  attributes do
    attribute :status, :status, required: true
    attribute :title, :string, required: true
    attribute :key, :string, required: true
    attribute :url, :string, required: true
    attribute :open_in_new_window, :boolean, default: false, required: true
  end

  relations do
    relation :items, :embeds_many, module: __MODULE__, on_replace: :delete
  end
end
