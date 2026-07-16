defmodule Brando.Blueprint.Listings.Components.Children do
  @moduledoc """
  Opt-in child-listing action for hierarchical Blueprint listing rows.
  """
  use Phoenix.Component

  alias BrandoAdmin.Components.ChildListingButton

  attr :class, :any, default: nil
  attr :entry, :map, required: true
  attr :fields, :list, required: true
  attr :columns, :integer, default: 1
  attr :offset, :integer, default: nil

  @doc "Renders the child-listing action for an entry."
  def children_button(assigns) do
    assigns = assign(assigns, :target, "#list-row-#{assigns.entry.id}")

    ~H"""
    <div class={[
      @class,
      @columns && "col-#{@columns}",
      @offset && "offset-#{@offset}"
    ]}>
      <ChildListingButton.children_button entry={@entry} fields={@fields} target={@target} />
    </div>
    """
  end
end
