defmodule BrandoAdmin.Components.Button do
  use BrandoAdmin, :component

  def dropdown(assigns) do
    ~H"""
      <li>
        <%= if @confirm do %>
          <button
            type="button"
            id={"dropdown-button-#{@event.name}"}
            phx-hook="Brando.ConfirmClick"
            phx-confirm-click-message={@confirm}
            phx-confirm-click={@event.name}
            phx-target={@event.target.cid}
            value={@value}
            phx-page-loading={@loading}>
            <%= render_slot @inner_block %>
          </button>
        <% else %>
          <button
            type="button"
            id={"dropdown-button-#{@event.name}"}
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
