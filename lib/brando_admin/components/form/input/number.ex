defmodule BrandoAdmin.Components.Form.Input.Number do
  use Surface.Component
  # use Phoenix.LiveComponent
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase

  prop form, :form
  prop field, :any
  prop blueprint, :any
  prop input, :any
  prop label, :string
  prop placeholder, :string
  prop instructions, :string

  def render(%{blueprint: _, input: %{name: name, opts: opts}} = assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      field={name}
      class={opts[:class]}
      form={@form}>
      {number_input @form, name, class: "text"}
    </FieldBase>
    """
  end

  def render(assigns) do
    ~F"""
    <FieldBase
      label={@label}
      placeholder={@placeholder}
      instructions={@instructions}
      field={@field}
      form={@form}>
      {number_input @form, @field, class: "text"}
    </FieldBase>
    """
  end
end
