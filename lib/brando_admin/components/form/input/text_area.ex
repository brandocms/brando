defmodule BrandoAdmin.Components.Form.Input.Textarea do
  use Surface.Component
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase

  prop form, :form
  prop field, :any
  prop blueprint, :any
  prop input, :any
  prop label, :string
  prop placeholder, :string
  prop instructions, :string
  prop debounce, :any

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign(:debounce, assigns[:debounce])}
  end

  def render(%{blueprint: _, input: %{name: name, opts: opts}} = assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      field={name}
      class={opts[:class]}
      form={@form}>
      {textarea @form, name, class: "text", phx_debounce: @debounce}
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
      {textarea @form, @field, class: "text", phx_debounce: @debounce}
    </FieldBase>
    """
  end
end
