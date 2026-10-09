defmodule BrandoAdmin.Components.CircleDropdown do
  @moduledoc false
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:id, "circle-dropdown-#{assigns.id}")}
  end

  def render(assigns) do
    ~H"""
    <div class="circle-dropdown wrapper">
      <button
        class="circle-dropdown-button"
        data-testid="circle-dropdown-button"
        type="button"
        aria-label={assigns[:label] || gettext("Actions")}
        data-tooltip={assigns[:label] || gettext("Actions")}
        aria-haspopup="menu"
        aria-controls={@id}
        phx-click={toggle_dropdown("##{@id}")}
        phx-click-away={hide_dropdown("##{@id}")}
      >
        <.icon name="chevron-down" />
      </button>
      <div data-testid="circle-dropdown-content" class="dropdown-content hidden" id={@id}>
        {render_slot(@inner_block, @id)}
      </div>
    </div>
    """
  end
end
