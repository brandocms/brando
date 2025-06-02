defmodule BrandoAdmin.Components.Tab do
  @moduledoc false
  use BrandoAdmin, :component
  alias Phoenix.LiveView.JS

  attr :tabs, :list, required: true
  attr :active_tab, :string, default: nil
  attr :target, :any, default: nil

  def tabs(assigns) do
    # Set first tab as active if no active tab is specified
    assigns = assign_new(assigns, :active_tab, fn ->
      case assigns.tabs do
        [first_tab | _] -> first_tab.id
        [] -> nil
      end
    end)

    ~H"""
    <div class="tab-container">
      <div class="tab-header">
        <button
          :for={tab <- @tabs}
          type="button"
          class={["tab-button", @active_tab == tab.id && "active"]}
          phx-click={JS.push("select_tab", value: %{tab: tab.id}, target: @target)}
        >
          {tab.label}
        </button>
      </div>
      <div class="tab-content">
        <%= for tab <- @tabs do %>
          <div 
            :if={@active_tab == tab.id} 
            class="tab-panel" 
            id={"tab-panel-#{tab.id}"}
          >
            {tab.content}
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end