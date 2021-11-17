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
        phx-click={show_dropdown("##{@id}")}
        phx-click-away={hide_dropdown("##{@id}")}>
        <.icon />
      </button>
      <ul data-testid="circle-dropdown-content" class="dropdown-content hidden" id={@id}>
        <%= render_slot @inner_block, @id %>
      </ul>
    </div>
    """
  end

  def icon(assigns) do
    ~H"""
    <svg width="40" height="40" viewBox="0 0 40 40" fill="none" xmlns="http://www.w3.org/2000/svg">
      <circle cx="20" cy="20" r="19.5" fill="#0047FF" class="main-circle"></circle>
      <line x1="12" y1="12.5" x2="28" y2="12.5" stroke="white"></line>
      <line x1="18" y1="26.5" x2="28" y2="26.5" stroke="white"></line>
      <line x1="12" y1="19.5" x2="28" y2="19.5" stroke="white"></line>
      <circle cx="13.5" cy="26.5" r="1.5" fill="white"></circle>
    </svg>
    """
  end
end
