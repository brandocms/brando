defmodule BrandoAdmin.Components.Form.Input.Textarea do
  use Surface.Component
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase

  prop form, :form
  prop field, :any
  prop blueprint, :any
  prop input, :any
  prop label, :string
  prop rows, :string
  prop placeholder, :string
  prop instructions, :string
  prop debounce, :any

  def update(%{blueprint: blueprint, input: %{name: name, opts: opts}} = assigns, socket) do
    translations = get_in(blueprint.translations, [:fields, name]) || []
    placeholder = Keyword.get(translations, :placeholder, assigns[:placeholder])

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       placeholder: placeholder,
       class: opts[:class],
       monospace: opts[:monospace] || false,
       rows: opts[:rows] || 3,
       disabled: assigns[:disabled] || false,
       debounce: assigns[:debounce] || 750
     )}
  end

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
      {textarea @form, name,
        class: "text",
        placeholder: @placeholder,
        rows: @rows,
        phx_debounce: @debounce}
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
      {textarea @form, @field,
        class: "text",
        rows: @rows,
        phx_debounce: @debounce}
    </FieldBase>
    """
  end
end
