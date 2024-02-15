defmodule BrandoAdmin.Components.CircleDropdown do
  use BrandoAdmin, :component

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
        phx-click={toggle_dropdown("##{@id}")}
        phx-click-away={hide_dropdown("##{@id}")}
      >
        <.icon name="brando-dropdown" />
      </button>
      <ul data-testid="circle-dropdown-content" class="dropdown-content hidden" id={@id}>
        <%= render_slot(@inner_block, @id) %>
      </ul>
    </div>
    """
  end
end
