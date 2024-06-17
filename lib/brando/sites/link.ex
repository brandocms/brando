defmodule Brando.Link do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "Link",
    singular: "link",
    plural: "links",
    gettext_module: Brando.Gettext

  data_layer :embedded
  identifier false
  absolute_url "{{ entry.url }}"

  attributes do
    attribute :name, :string, required: true
    attribute :url, :string, required: true
  end

  defimpl Phoenix.HTML.Safe do
    def to_iodata(link) do
      link.url
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end
  end
end
