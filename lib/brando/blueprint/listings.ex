defmodule Brando.Blueprint.Listings do
  @moduledoc """
  # Listings

  ### Listing/row component

  Import the lightweight row components explicitly, adding the opt-in cover or
  children modules only when the row uses them:

      import Brando.Blueprint.Listings.Components.Core
      import Brando.Blueprint.Listings.Components.Cover, only: [cover: 1]

      listings do
        listing do
          component &__MODULE__.listing_row/1
          # ...
        end
      end

  The compatibility facade `Brando.Blueprint.Listings.Components` still exposes
  every component, but granular imports keep ordinary listing rows independent
  from cover-image and child-listing admin trees.

      def listing_row(assigns) do
        ~H\"""
        <.cover image={@entry.cover} columns={2} size={:smallest} padded />
        <.update_link entry={@entry} columns={6}>
          <%= @entry.title %>
          <:outside>
            <%= if @entry.category do %>
              <br />
              <small class="badge"><%= @entry.category.name %></small>
            <% end %>
          </:outside>
        </.update_link>
        <.url entry={@entry} />
        \"""
      end

  ### Custom query params

  To set preloads or ordering for your listing you can call

      listings do
        listing do
          query %{preload: [fragments: :creator], order: [{:asc, :sequence}]}
          # ...
        end
      end

  This merges the query map into the starting point for listing queries.

  """

  @doc """
  Merges configured filter defaults into listing query options.

  Defaults only fill missing filter keys; explicit values from the listing
  query take precedence.
  """
  @spec merge_filter_defaults(map(), Brando.Blueprint.Listings.Listing.t() | map()) :: map()
  def merge_filter_defaults(query, listing) do
    defaults =
      listing.filters
      |> Enum.map(&{&1, resting_value(&1)})
      |> Enum.reject(fn {_filter, value} -> value in [nil, ""] end)
      |> Map.new(fn {filter, value} -> {String.to_atom(filter.key), value} end)

    case defaults do
      empty when map_size(empty) == 0 ->
        query

      _defaults ->
        Map.update(query, :filter, defaults, fn
          filters when is_map(filters) -> Map.merge(defaults, filters)
          _invalid_filters -> defaults
        end)
    end
  end

  @doc """
  The value a filter holds when nobody has touched it, as the context filter
  receives it; `nil` when it does not apply.

  A :boolean filter rests at `"true"` with `default: true`, at `"false"` with
  `off: false`, and otherwise does not apply.
  """
  def resting_value(%{type: :boolean, default: default}) when default in [true, "true"], do: "true"
  def resting_value(%{type: :boolean, off: false}), do: "false"
  def resting_value(%{type: :boolean}), do: nil
  def resting_value(%{default: default}) when default in [nil, false, ""], do: nil
  def resting_value(%{default: default}), do: default

  @doc """
  The value a :boolean filter switched off sends: `"false"` with `off: false`.
  With `off: :all` the filter stops applying: an empty value drops it from the
  URL, and `"off"` does so over a `default: true` (see `drop_switched_off/2`).
  """
  def off_value(%{off: false}), do: "false"
  def off_value(%{default: default}) when default in [true, "true"], do: "off"
  def off_value(_filter), do: ""

  @doc """
  Drops the :boolean filters switched off over a `default: true`, so the
  context never receives `"off"`.
  """
  def drop_switched_off(%{filter: filters} = list_opts, listing) when is_map(filters) do
    off =
      for %{type: :boolean, key: key} <- listing.filters,
          Map.get(filters, String.to_atom(key)) == "off",
          do: String.to_atom(key)

    %{list_opts | filter: Map.drop(filters, off)}
  end

  def drop_switched_off(list_opts, _listing), do: list_opts
end
