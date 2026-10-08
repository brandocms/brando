defmodule Brando.ListingViews.Params do
  @moduledoc """
  The URL parameters a listing view keeps, checked against the listing as it
  is declared now.

  A listing keeps its state in its URL: `filter:<key>` for each filter,
  `status`, `sort` or `order` for the sort, `limit` for the page size and
  `page`. A view keeps the filters, status, sort and page size, not the page.
  The sort is kept by its key (`sort`), whichever way the URL gave it.

  `sanitize/3` drops what the listing no longer has: a filter, a select
  option, a sort or a status that is gone, or a value that does not parse.
  The listing turns parameter names into atoms, so a stale view must never
  reach it unchecked.
  """

  alias Brando.Trait.SoftDelete
  alias Brando.Trait.Status

  @boolean_values ~w(true false off)
  @statuses ~w(published disabled draft pending)
  @text_max 200

  @doc """
  The parameters a view saves from the listing's current URL query, decoded
  flat as `URI.decode_query/1` gives it. `active_sort` is the sort the
  listing shows; it is saved only when the URL chose one.
  """
  def from_query(query, listing, schema, active_sort \\ nil) when is_map(query) do
    sort =
      if active_sort && Enum.any?(Map.keys(query), &sort_param?/1),
        do: %{"sort" => to_string(active_sort.key)},
        else: %{}

    query
    |> Map.reject(fn {key, _value} -> sort_param?(key) end)
    |> Map.merge(sort)
    |> sanitize(listing, schema)
  end

  @doc "The parameters that still apply to `listing` of `schema`; the rest are dropped."
  def sanitize(params, listing, schema) when is_map(params) do
    params
    |> Enum.filter(&valid?(&1, listing, schema))
    |> Map.new()
  end

  def sanitize(_params, _listing, _schema), do: %{}

  defp sort_param?(key), do: key in ["sort", "order"] or String.starts_with?(key, "order[")

  defp valid?({key, value}, _listing, _schema) when not is_binary(key) or not is_binary(value), do: false
  defp valid?({_key, ""}, _listing, _schema), do: false

  defp valid?({"filter:" <> key, value}, listing, _schema) do
    case Enum.find(listing.filters, &(to_string(&1.key) == key)) do
      nil -> false
      %{type: :boolean} -> value in @boolean_values
      %{type: :select, options: options} when is_list(options) and options != [] -> option?(options, value)
      _filter -> String.length(value) <= @text_max
    end
  end

  defp valid?({"status", value}, _listing, schema), do: value in statuses(schema)
  defp valid?({"sort", key}, listing, _schema), do: Enum.any?(listing.sorts, &(to_string(&1.key) == key))

  defp valid?({"limit", value}, _listing, _schema) do
    case Integer.parse(value) do
      {limit, ""} -> limit >= 0
      _ -> false
    end
  end

  defp valid?(_param, _listing, _schema), do: false

  defp option?(options, value) do
    Enum.any?(options, fn
      %{value: option} -> to_string(option) == value
      {_label, option} -> to_string(option) == value
      _ -> false
    end)
  end

  defp statuses(schema) do
    cond do
      not schema.has_trait(Status) -> []
      schema.has_trait(SoftDelete) -> @statuses ++ ["deleted"]
      true -> @statuses
    end
  end
end
