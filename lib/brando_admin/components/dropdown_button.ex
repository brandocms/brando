defmodule BrandoAdmin.Components.Button do
  use BrandoAdmin, :component

  def dropdown(assigns) do
    [_, %{event: event_name}] = List.first(assigns.event.ops)

    assigns =
      assigns
      |> assign(:event_name, event_name)
      |> assign_new(:loading, fn -> false end)
      |> assign_new(:confirm, fn -> false end)

    ~H"""
      <li>
        <%= if @confirm do %>
          <button
            type="button"
            id={"dropdown-button-#{@event_name}"}
            phx-hook="Brando.ConfirmClick"
            phx-confirm-click-message={@confirm}
            phx-confirm-click={@event}
            value={@value}
            phx-page-loading={@loading}>
            <%= render_slot @inner_block %>
          </button>
        <% else %>
          <button
            type="button"
            id={"dropdown-button-#{@event_name}"}
            phx-click={@event}
            value={@value}
            phx-page-loading={@loading}>
            <%= render_slot @inner_block %>
          </button>
        <% end %>
      </li>
    """
  end
end
