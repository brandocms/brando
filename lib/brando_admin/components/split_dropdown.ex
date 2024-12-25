defmodule BrandoAdmin.Components.SplitDropdown do
  use BrandoAdmin, :component

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:id, "split-dropdown-#{assigns.id}")}
  end

  def render(assigns) do
    ~H"""
    <div class="split-dropdown-wrapper">
      <button
        class="split-dropdown-button"
        data-testid="split-dropdown-button"
        type="button"
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
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18">
      <path fill="none" d="M0 0h24v24H0z" /><path d="M12 15l-4.243-4.243 1.415-1.414L12 12.172l2.828-2.829 1.415 1.414z" />
    </svg>
    """
  end
end
