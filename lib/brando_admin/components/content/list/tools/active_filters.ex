defmodule BrandoAdmin.Components.Content.List.Tools.ActiveFilters do
  use Surface.Component

  prop active_filters, :any
  prop filters, :any
  prop delete, :event, required: true

  def render(assigns) do
    ~F"""
    <div class="active-filters">
      Active filters &rarr;
      {#for {name, value} <- @active_filters}
        <button
          class="filter"
          :on-click={@delete}
          phx-value-filter={name}>
          &times; {name}: {value}
        </button>
      {/for}
    </div>
    """
  end
end
