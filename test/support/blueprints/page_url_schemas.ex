defmodule Brando.PageURLTest.Unloaded do
  @moduledoc false
  # Its URL template renders an association, which raises
  # Protocol.UndefinedError when the association is not preloaded.
  use Brando.Blueprint,
    application: "Brando",
    domain: "PageURLTest",
    schema: "Unloaded",
    singular: "unloaded",
    plural: "unloadeds",
    gettext_module: Brando.Gettext

  alias Brando.JSONLD

  identifier ~H"{@entry.title}"
  absolute_url ~H"/unloaded/{@entry.writer}"

  attributes do
    attribute :title, :string, required: true
  end

  relations do
    relation :writer, :belongs_to, module: Brando.JSONLDTest.Person
  end

  json_ld_schema JSONLD.Schema.Article do
    field :headline, :string, & &1.title
    field :url, :current_url
  end
end
