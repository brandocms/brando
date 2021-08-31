defmodule BrandoAdmin.Components.Form.Input.Phone do
  use Surface.Component
  # use Phoenix.LiveComponent
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase

  prop form, :form
  prop blueprint, :any

  def render(%{input: %{name: name, opts: opts}} = assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      form={@form}
      class={opts[:class]}
      field={name}>
      {telephone_input @form, name, class: "text"}
    </FieldBase>
    """
  end
end
