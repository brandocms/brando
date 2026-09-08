defmodule BrandoAdmin.Components.SplitDropdown do
  @moduledoc false
  use BrandoAdmin, :component

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:id, "split-dropdown-#{assigns.id}")}
  end

  attr :id, :string, required: true
  attr :label, :string, default: nil
  slot :inner_block, required: true

  def render(assigns) do
    ~H"""
    <div class="split-dropdown-wrapper">
      <button
        class="split-dropdown-button"
        data-testid="split-dropdown-button"
        type="button"
        aria-label={@label}
        title={@label}
        phx-click={toggle_dropdown("##{@id}")}
        phx-click-away={hide_dropdown("##{@id}")}
      >
        <.dd_icon />
      </button>
      <ul data-testid="split-dropdown-content" class="dropdown-content hidden" id={@id}>
        {render_slot(@inner_block, @id)}
      </ul>
    </div>
    """
  end

  def dd_icon(assigns) do
    ~H"""
    <.icon name="hero-chevron-down" class="dropdown-chevron" />
    """
  end
end
