defmodule BrandoAdmin.Components.CircleDropdown do
  use BrandoAdmin, :component

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:id, "circle_dropdown_#{assigns.id}")}
  end

  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="circle-dropdown wrapper"
      phx-hook="Brando.CircleDropdown">
      <button
        class="circle-dropdown-button"
        data-testid="circle-dropdown-button"
        type="button">
        <svg width="40" height="40" viewBox="0 0 40 40" fill="none" xmlns="http://www.w3.org/2000/svg">
          <circle cx="20" cy="20" r="19.5" fill="#0047FF" class="main-circle"></circle>
          <line x1="12" y1="12.5" x2="28" y2="12.5" stroke="white"></line>
          <line x1="18" y1="26.5" x2="28" y2="26.5" stroke="white"></line>
          <line x1="12" y1="19.5" x2="28" y2="19.5" stroke="white"></line>
          <circle cx="13.5" cy="26.5" r="1.5" fill="white"></circle>
        </svg>
      </button>
      <ul data-testid="circle-dropdown-content" class="dropdown-content">
        <%= render_slot @inner_block, @id %>
      </ul>
    </div>
    """
  end
end
