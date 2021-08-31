defmodule BrandoAdmin.Components.Content.List.Row.EntryMenu do
  use Surface.Component

  prop entry, :any, required: true
  prop listing, :any, required: true

  data language, :any

  def update(assigns, socket) do
    language = Map.get(assigns.entry, :language)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:language, language)}
  end

  def render(assigns) do
    ~F"""
    {#if !Enum.empty?(@listing.actions)}
      <div
        id={"entry_dropdown_#{@entry.id}"}
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
          {#for action <- @listing.actions}
            <li>
              {#if action[:confirm]}
                <button
                  id={"action_#{action[:event]}_#{@entry.id}"}
                  phx-hook="Brando.ConfirmClick"
                  phx-confirm-click-message={action[:confirm]}
                  phx-confirm-click={action[:event]}
                  phx-value-language={@language}
                  phx-value-id={@entry.id}>
                  {action[:label]}
                </button>
              {#else}
                <button
                  id={"action_#{action[:event]}_#{@entry.id}"}
                  phx-value-id={@entry.id}
                  phx-value-language={@language}
                  :on-click={action[:event], target: :live_view}>
                  {action[:label]}
                </button>
              {/if}
            </li>
          {/for}
        </ul>
      </div>
    {/if}
    """
  end
end
