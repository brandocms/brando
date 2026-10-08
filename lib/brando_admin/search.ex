defmodule BrandoAdmin.Search do
  @moduledoc """
  The search page's queries (`BrandoAdmin.SearchLive`): its filters, read
  from the URL against fixed lists, and its results from `Brando.Search`.

  A user finds only the content types and entries they may read, in the
  current site and environment, through the same authorization filtering as
  the command palette (`BrandoAdmin.CommandPalette`): the read policy of
  every content type narrows the index in the query (with groups, entry by
  entry), so the counts hold only what they may read as well. A row links to
  the entry's editor when the user may also edit it.
  """
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Blueprint
  alias Brando.ContentEvents.Event
  alias Brando.Repo
  alias Brando.Search.Document
  alias BrandoAdmin.CommandPalette

  @page_size 20
  @max_page 500
  @statuses ~w(published pending draft disabled)
  @sorts ~w(relevance updated)

  @type filters :: %{
          q: String.t(),
          type: String.t() | nil,
          language: String.t() | nil,
          status: String.t() | nil,
          sort: String.t(),
          page: pos_integer()
        }

  @doc "Results per page."
  def page_size, do: @page_size

  @doc """
  The content types the user may read, by name: `%{key, schema, label,
  icon}`, `key` being the type's public name (`"pages.page"`).
  """
  def types(user) do
    permissions = CommandPalette.permissions(user)

    Brando.Search.searchable_schemas()
    |> Enum.filter(&CommandPalette.allowed?(permissions, :read, &1))
    |> Enum.map(fn schema ->
      %{
        key: Event.entry_type(schema),
        schema: schema,
        label: Blueprint.get_plural(schema),
        icon: Blueprint.get_icon(schema)
      }
    end)
    |> Enum.reject(&is_nil(&1.key))
    |> Enum.sort_by(&String.downcase(&1.label))
  end

  @doc "The site's languages, `{code, name}`."
  def languages do
    (Brando.config(:languages) || [])
    |> Enum.map(fn language -> {to_string(language[:value]), to_string(language[:text] || language[:value])} end)
    |> Enum.reject(fn {code, _} -> code == "" end)
  end

  @doc "The statuses to filter by."
  def statuses, do: @statuses

  @doc "The orders to sort by."
  def sorts, do: @sorts

  @doc """
  The filters in `params`. Anything not in the lists (types the user may
  read, the site's languages, the statuses, the orders, a page number) is
  dropped.
  """
  @spec filters(map(), [map()]) :: filters()
  def filters(params, types) do
    %{
      q: params |> Map.get("q") |> text(),
      type: allowed(params["type"], Enum.map(types, & &1.key)),
      language: allowed(params["language"], Enum.map(languages(), &elem(&1, 0))),
      status: allowed(params["status"], @statuses),
      sort: allowed(params["sort"], @sorts) || "relevance",
      page: page(params["page"])
    }
  end

  defp text(value) when is_binary(value), do: value |> String.trim() |> String.slice(0, 200)
  defp text(_), do: ""

  defp allowed(value, list) when is_binary(value), do: if(value in list, do: value)
  defp allowed(_value, _list), do: nil

  defp page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page >= 1 -> min(page, @max_page)
      _ -> 1
    end
  end

  defp page(_), do: 1

  @doc "The URL query for `filters`, leaving out what is as it starts."
  @spec query_string(filters()) :: String.t()
  def query_string(filters) do
    [
      {"q", filters.q},
      {"type", filters.type},
      {"language", filters.language},
      {"status", filters.status},
      {"sort", if(filters.sort != "relevance", do: filters.sort)},
      {"page", if(filters.page > 1, do: filters.page)}
    ]
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> URI.encode_query()
  end

  @doc """
  The results for `filters`: `%{rows, total, facets}`, where `facets` maps a
  type's key to its number of matches before the type filter.
  """
  def results(user, types, filters) do
    CommandPalette.in_scope(user, fn ->
      schemas = Enum.map(types, & &1.schema)
      type = Enum.find(types, &(&1.key == filters.type))

      result =
        Brando.Search.Query.run(scope(schemas), filters.q,
          schemas: type && [type.schema],
          language: filters.language,
          status: filters.status && String.to_existing_atom(filters.status),
          sort: String.to_existing_atom(filters.sort),
          limit: @page_size,
          offset: (filters.page - 1) * @page_size
        )

      keys = Map.new(types, &{&1.schema, &1.key})

      %{
        rows: rows(user, result.rows),
        total: result.total,
        facets: Map.new(result.facets, fn {schema, count} -> {keys[schema], count} end)
      }
    end)
  rescue
    error in Postgrex.Error ->
      if error.postgres[:code] == :undefined_table,
        do: %{rows: [], total: 0, facets: %{}, unavailable: true},
        else: reraise(error, __STACKTRACE__)
  end

  # The documents of the types the user may read, narrowed entry by entry by
  # each type's read policy, as the palette narrows identifiers.
  defp scope(schemas), do: Boundary.identifiers(from(d in Document, where: d.schema in ^schemas))

  # Each row links to the entry's editor when the user may edit it, as a
  # palette row would. The entries are loaded one query per content type.
  defp rows(_user, []), do: []

  defp rows(user, documents) do
    permissions = CommandPalette.permissions(user)

    entries =
      documents
      |> Enum.group_by(& &1.schema, & &1.entry_id)
      |> Map.new(fn {schema, ids} ->
        {schema, Map.new(Repo.all(from(e in schema, where: e.id in ^ids)), &{&1.id, &1})}
      end)

    Enum.flat_map(documents, fn document ->
      case get_in(entries, [document.schema, document.entry_id]) do
        nil ->
          []

        %{deleted_at: %{}} ->
          []

        entry ->
          editable? =
            CommandPalette.allowed?(permissions, :read, entry) and CommandPalette.allowed?(permissions, :update, entry)

          [row(document, entry, editable?)]
      end
    end)
  end

  defp row(document, entry, editable?) do
    %{
      id: "search-result-#{document.id}",
      title: present(document.title) || gettext("Untitled"),
      url: if(editable?, do: document.schema.__admin_route__(:update, [entry.id])),
      cover: document.cover,
      icon: Blueprint.get_icon(document.schema),
      type: Blueprint.get_singular(document.schema),
      language: present(document.language) && String.upcase(document.language),
      status: document.status,
      snippet: document.snippet
    }
  end

  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value
end
