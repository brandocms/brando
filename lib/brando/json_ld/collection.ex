defmodule Brando.JSONLD.Collection do
  @moduledoc """
  Builds JSON-LD for a collection of entries a template has just rendered.

  A datasource block resolves its entries inside the render and caches the
  output in `rendered_<field>`, so the usual controller-side
  `put_json_ld(conn, :entities, …)` never sees them. Emitting the markup inline,
  from the same list, keeps it in lockstep with the HTML: both are refreshed by
  the same render, and neither can be fresher than the other.

  Reached through the `json_ld` Liquex filter and the `<.json_ld>` HEEx
  component; both delegate here.

      Brando.JSONLD.Collection.from_entries(entries, type: "CreativeWork")
      #=> %Brando.JSONLD.Schema.ItemList{…}

      Brando.JSONLD.Collection.from_entries(entries,
        type: "Article",
        page: %{url: "/articles", language: "no", name: "Articles"}
      )
      #=> %Brando.JSONLD.Schema.CollectionPage{mainEntity: %ItemList{…}}

  Entries without a page of their own — no `absolute_url` on the blueprint, a
  resolver that returns `nil` or raises, a bare map from a `select:` query — are
  skipped rather than given a fabricated URL. An empty result builds nothing.
  """

  require Logger

  alias Brando.JSONLD
  alias Brando.JSONLD.Schema.CollectionPage
  alias Brando.JSONLD.Schema.ItemList
  alias Brando.Utils

  @type option ::
          {:type, String.t() | nil}
          | {:name, String.t() | nil}
          | {:id, String.t() | nil}
          | {:page, map() | nil}

  @doc """
  Builds an `ItemList` (or a `CollectionPage` wrapping one) from `entries`.

  ## Options

    * `:type` - the schema.org `@type` of each item, e.g. `"CreativeWork"` for a
      portfolio or `"Article"` for a listing. Omit for plain list items.
    * `:name` - list name.
    * `:id` - list `@id`.
    * `:page` - a map with `:url`, `:language` and optionally `:name`. When
      given, the result is a `CollectionPage` whose `mainEntity` is the list,
      joined to the site's `#website` and `#identity` nodes by reference.
  """
  @spec from_entries([term()], [option()]) :: %ItemList{} | %CollectionPage{} | nil
  def from_entries(entries, opts \\ [])

  def from_entries(entries, opts) when is_list(entries) do
    type = Keyword.get(opts, :type)

    case Enum.flat_map(entries, &item(&1, type)) do
      [] ->
        nil

      items ->
        list = ItemList.build(items, id: Keyword.get(opts, :id), name: Keyword.get(opts, :name))
        wrap(list, Keyword.get(opts, :page))
    end
  end

  def from_entries(_entries, _opts), do: nil

  @doc """
  Renders a node as an inline `<script type="application/ld+json">` tag.

  Returns an empty safe string for `nil`, so callers can pass the result of
  `from_entries/2` straight through.
  """
  @spec script(struct() | nil) :: Phoenix.HTML.safe()
  def script(nil), do: {:safe, ""}

  def script(node) do
    {:safe, [~s(<script type="application/ld+json">), JSONLD.to_json(node), "</script>"]}
  end

  defp wrap(list, nil), do: list

  defp wrap(list, page) when is_map(page) do
    hostname = Utils.hostname()

    CollectionPage.build(%{
      id: page |> Map.get(:url) |> absolute() |> then(&(&1 && "#{&1}/#collectionpage")),
      name: Map.get(page, :name),
      url: page |> Map.get(:url) |> absolute(),
      language: page |> Map.get(:language) |> presence(),
      is_part_of: "#{hostname}/#website",
      publisher: "#{hostname}/#identity",
      main_entity: list
    })
  end

  defp item(%{__struct__: schema} = entry, type) do
    with true <- function_exported?(schema, :__has_absolute_url__, 0),
         true <- schema.__has_absolute_url__(),
         url when is_binary(url) and url != "" <- resolve_url(schema, entry),
         name when is_binary(name) and name != "" <- name(schema, entry) do
      [element(name, absolute(url), type)]
    else
      _ -> []
    end
  end

  defp item(_entry, _type), do: []

  defp element(name, url, nil), do: {name, url}
  defp element(name, url, type), do: {name, url, type}

  defp resolve_url(schema, entry) do
    schema.__absolute_url__(entry)
  rescue
    error ->
      Logger.warning(
        "JSON-LD collection skipped #{inspect(schema)} ##{Map.get(entry, :id)}: " <>
          Exception.message(error)
      )

      nil
  end

  defp name(schema, entry) do
    if function_exported?(schema, :__has_identifier__, 0) and schema.__has_identifier__() do
      entry |> schema.__identifier__(skip_cover: true) |> Map.get(:title)
    else
      Map.get(entry, :title) || Map.get(entry, :name)
    end
  rescue
    _ -> Map.get(entry, :title) || Map.get(entry, :name)
  end

  defp absolute(nil), do: nil
  defp absolute("http://" <> _ = url), do: url
  defp absolute("https://" <> _ = url), do: url
  defp absolute(path), do: Utils.hostname(path)

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value), do: to_string(value)
end
