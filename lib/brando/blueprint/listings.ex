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
      |> Enum.reject(&(&1.default in [nil, false, ""]))
      |> Map.new(&{String.to_atom(&1.key), &1.default})

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
end
