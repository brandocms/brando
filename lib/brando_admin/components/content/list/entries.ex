defmodule BrandoAdmin.Components.Content.List.Entries do
  use Surface.Component

  @doc "The list of items to be rendered"
  prop entries, :list, required: true
  prop listing_name, :string, required: true
  prop target, :any, required: true

  @doc "The list of columns defining the Grid"
  slot default, args: [entry: ^entries]

  def render(assigns) do
    ~F"""
    <div
      id={"sortable-#{@listing_name}"}
      data-target={@target}
      class="sort-container"
      phx-hook="Brando.Sortable"
      data-sortable-id={"content_listing_#{@listing_name}"}
      data-sortable-handle=".sequence-handle"
      data-sortable-selector=".list-row">
      {#for entry <- @entries}
        {#for {_, index} <- Enum.with_index(@default)}
          <#slot name="default" index={index} :args={entry: entry} />
        {/for}
      {/for}
    </div>
    """
  end
end
