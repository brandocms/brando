defmodule BrandoAdmin.Components.Content.List.SelectedRows do
  use Surface.Component
  import Brando.Gettext

  prop selected_rows, :list, required: true
  prop selection_actions, :any, required: true
  prop target, :any, required: true

  data encoded_selected_rows, :string
  data selected_rows_count, :integer

  def update(%{selected_rows: selected_rows} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:encoded_selected_rows, Jason.encode!(selected_rows))
     |> assign(:selected_rows_count, Enum.count(selected_rows))}
  end

  def render(assigns) do
    ~F"""
    <div class={"selected-rows", hidden: Enum.empty?(@selected_rows)}">
      <div class="clear-selection">
        <button
          phx-click="clear_selection"
          phx-target={@target}
          type="button"
          class="btn-outline-primary inverted">
          {gettext("Clear selection")}
        </button>
      </div>
      <div class="selection-actions">
        {gettext("With")}
        <div class="circle"><span>{@selected_rows_count}</span></div>
        {gettext("selected, perform action")}: →
        <div
          id="selected_rows_dropdown"
          class="circle-dropdown wrapper"
          phx-hook="Brando.CircleDropdown">
          <button
            class="circle-dropdown-button"
            data-testid="circle-dropdown-button"
            type="button">
            <svg width="40" height="40" viewBox="0 0 40 40" fill="none" xmlns="http://www.w3.org/2000/svg">
              <circle cx="20" cy="20" r="19.5" fill="#0047FF" class="main-circle inverted"></circle>
              <line x1="12" y1="12.5" x2="28" y2="12.5" stroke="white" class="inverted"></line>
              <line x1="18" y1="26.5" x2="28" y2="26.5" stroke="white" class="inverted"></line>
              <line x1="12" y1="19.5" x2="28" y2="19.5" stroke="white" class="inverted"></line>
              <circle cx="13.5" cy="26.5" r="1.5" fill="white" class="inverted"></circle>
            </svg>
          </button>
          <ul data-testid="circle-dropdown-content" class="dropdown-content">
            {#for %{event: event, label: label} <- @selection_actions}
              <li>
                <button
                  :on-click={event, target: :live_view}
                  phx-value-ids={@encoded_selected_rows}>
                  {label}
                </button>
              </li>
            {/for}
          </ul>
        </div>
      </div>
    </div>
    """
  end
end
