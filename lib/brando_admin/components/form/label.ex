defmodule BrandoAdmin.Components.Form.Label do
  use BrandoAdmin, :component
  import Brando.HTML, only: [render_classes: 1]

  # prop form, :form
  # prop field, :any
  # prop class, :css_class
  # prop opts, :keyword, default: []

  @doc """
  The text for the label
  """

  # slot default

  # data input_id, :string

  def render(assigns) do
    assigns =
      assign_new(assigns, :input_id, fn ->
        Phoenix.HTML.Form.input_id(assigns.form, assigns.field)
      end)

    ~H"""
    <label class={render_classes(List.wrap(@class))} for={@input_id}>
      <%= render_slot @inner_block %>
    </label>
    """
  end
end
