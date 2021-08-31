defmodule BrandoAdmin.Components.DropdownButton do
  use Surface.Component

  prop confirm, :string
  prop event, :event
  prop value, :any
  prop loading, :boolean

  slot default

  def render(assigns) do
    ~F"""
      <li>
        {#if @confirm}
          <Context get={dropdown_id: id}>
            <button
              type="button"
              id={"#{id}-dropdown-button-#{@event.name}"}
              phx-hook="Brando.ConfirmClick"
              phx-confirm-click-message={@confirm}
              phx-confirm-click={@event.name}
              phx-target={@event.target.cid}
              value={@value}
              phx-page-loading={@loading}>
              <#slot />
            </button>
          </Context>
        {#else}
          <Context get={dropdown_id: id}>
            <button
              type="button"
              id={"#{id}-dropdown-button-#{@event.name}"}
              :on-click={@event}
              value={@value}
              phx-page-loading={@loading}>
              <#slot />
            </button>
          </Context>
        {/if}
      </li>
    """
  end
end
