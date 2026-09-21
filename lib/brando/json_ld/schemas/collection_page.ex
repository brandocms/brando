defmodule Brando.JSONLD.Schema.CollectionPage do
  @moduledoc """
  CollectionPage schema

  A page whose purpose is to present a collection — a project index, an article
  listing. Pairs with `Brando.JSONLD.Schema.ItemList` as its `mainEntity`.

  Sits alongside the `WebPage` node rather than replacing it: the WebPage
  describes the document, the CollectionPage describes what it collects.
  """

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@type": "CollectionPage",
            "@id": nil,
            name: nil,
            url: nil,
            inLanguage: nil,
            isPartOf: nil,
            about: nil,
            publisher: nil,
            mainEntity: nil

  @doc """
  Builds a CollectionPage.

  `is_part_of`, `about` and `publisher` accept strings, which are wrapped as
  `@id` references so the node joins the graph.
  """
  @spec build(map()) :: %__MODULE__{}
  def build(attrs) when is_map(attrs) do
    %__MODULE__{
      "@id": Map.get(attrs, :id),
      name: Map.get(attrs, :name),
      url: Map.get(attrs, :url),
      inLanguage: Map.get(attrs, :language),
      isPartOf: attrs |> Map.get(:is_part_of) |> reference(),
      about: attrs |> Map.get(:about) |> reference(),
      publisher: attrs |> Map.get(:publisher) |> reference(),
      mainEntity: Map.get(attrs, :main_entity)
    }
  end

  defp reference(nil), do: nil
  defp reference(%{} = node), do: node
  defp reference(id) when is_binary(id), do: %{"@id": id}
end
