defmodule Brando.JSONLD.Schema.ItemList do
  @moduledoc """
  ItemList schema

  An ordered list of entities — a portfolio, a set of featured entries, a
  curated selection. Gives crawlers the collection as a structure instead of
  leaving them to infer it from a grid of links.
  """

  alias Brando.JSONLD.Schema.ListItem

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@type": "ItemList",
            "@id": nil,
            name: nil,
            numberOfItems: nil,
            itemListElement: []

  @doc """
  Builds an ItemList from `items`, numbering positions from 1.

  Each item is `{name, url}`, or `{name, url, type}` to describe what the
  entries are — `"CreativeWork"` for a portfolio, say — rather than leaving
  them as bare list items.
  """
  @spec build([tuple()], keyword()) :: %__MODULE__{}
  def build(items, opts \\ []) when is_list(items) do
    elements =
      items
      |> Enum.with_index(1)
      |> Enum.map(fn {item, position} -> build_element(item, position) end)

    %__MODULE__{
      "@id": Keyword.get(opts, :id),
      name: Keyword.get(opts, :name),
      numberOfItems: length(elements),
      itemListElement: elements
    }
  end

  defp build_element({name, url}, position), do: ListItem.build(position, name, url)

  defp build_element({name, url, type}, position) do
    %{
      "@type": "ListItem",
      position: position,
      item: %{
        "@type": type,
        "@id": "#{url}/#" <> String.downcase(type),
        name: name,
        url: url
      }
    }
  end
end
