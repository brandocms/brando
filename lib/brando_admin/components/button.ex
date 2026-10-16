defmodule BrandoAdmin.Components.Button do
  @moduledoc false
  use BrandoAdmin, :component

  attr :value, :any, required: true
  attr :event, Phoenix.LiveView.JS, required: true
  attr :confirm, :any, default: false
  attr :danger, :boolean, default: false, doc: "a row that destroys something (`menu-item--danger`)"
  slot :inner_block, required: true

  def dropdown(assigns) do
    [_, %{event: event_name}] = List.first(assigns.event.ops)

    assigns = assign(assigns, :event_name, event_name)

    ~H"""
    <li>
      <%= if @confirm do %>
        <button
          type="button"
          id={"dropdown-button-#{@event_name}-#{@value}"}
          class={["menu-item", @danger && "menu-item--danger"]}
          phx-hook="Brando.ConfirmClick"
          phx-confirm-click-message={@confirm}
          phx-confirm-click={@event}
        >
          {render_slot(@inner_block)}
        </button>
      <% else %>
        <button
          type="button"
          id={"dropdown-button-#{@event_name}-#{@value}"}
          class={["menu-item", @danger && "menu-item--danger"]}
          phx-click={@event}
        >
          {render_slot(@inner_block)}
        </button>
      <% end %>
    </li>
    """
  end
end
