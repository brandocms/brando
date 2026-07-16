defmodule Brando.Blueprint.Listings do
  @moduledoc """
  # Listings

  ### Listing/row component

  Import the reusable row components explicitly, then set your own component
  for rendering a listing row:

      import Brando.Blueprint.Listings.Components

      listings do
        listing do
          component &__MODULE__.list_row/1
          # ...
        end
      end

  The explicit import keeps Blueprints without custom listing rows independent
  from the admin component tree.

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
end
