defmodule BrandoAdmin.Components.Form.Label do
  use Surface.Component

  prop form, :form
  prop field, :any
  prop class, :css_class
  prop opts, :keyword, default: []

  @doc """
  The text for the label
  """
  slot default

  data input_id, :string

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:input_id, Phoenix.HTML.Form.input_id(assigns.form, assigns.field))}
  end

  def render(assigns) do
    ~F"""
    <label class={@class} for={@input_id}>
      <#slot />
    </label>
    """
  end
end
