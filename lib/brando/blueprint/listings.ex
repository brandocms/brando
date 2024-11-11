defmodule Brando.Blueprint.Listings do
  @moduledoc """
  # Listings

  ### Listing/row component

  Set your own component for rendering a listing row:

      listings do
        listing do
          component &__MODULE__.list_row/1
          # ...
        end
      end

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
          listing_query %{preload: [fragments: :creator], order: [{:asc, :sequence}]}
          # ...
        end
      end

  This will merge in your listing_query as the starting point for your queries

  """
end
