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

  def render(assigns) do
    assigns =
      assign_new(assigns, :input_id, fn ->
        Phoenix.HTML.Form.input_id(assigns.form, assigns.field)
      end)

    ~F"""
    <label class={@class} for={@input_id}>
      <#slot />
    </label>
    """
  end
end
