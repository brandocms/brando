defmodule BrandoAdmin.Components.Form.Label do
  use Surface.Component

  @doc "The form identifier"
  prop form, :form

  @doc "The field name"
  prop field, :any

  @doc "The CSS class for the underlying tag"
  prop class, :css_class

  @doc "Options list"
  prop opts, :keyword, default: []

  @doc """
  The text for the label
  """
  slot default

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
