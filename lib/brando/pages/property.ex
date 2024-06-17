defmodule Brando.Pages.Property do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Pages",
    schema: "Property",
    singular: "property",
    plural: "properties",
    gettext_module: Brando.Gettext

  alias Brando.Pages.Page

  identifier false

  attributes do
    attribute :type, :string, required: true
    attribute :label, :string, required: true
    attribute :key, :string, required: true
    attribute :data, :map, required: true
  end

  relations do
    relation :page, :belongs_to, module: Page
  end
end
