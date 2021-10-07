defmodule BrandoAdmin.Components.Form.Input.Text do
  use Surface.Component
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase

  prop form, :form
  prop field, :any
  prop blueprint, :any
  prop input, :any
  prop label, :string
  prop value, :any
  prop placeholder, :string
  prop instructions, :string
  prop class, :string
  prop monospace, :boolean, default: false
  prop disabled, :boolean
  prop debounce, :integer

  def update(%{blueprint: blueprint, input: %{name: name, opts: opts}} = assigns, socket) do
    translations = get_in(blueprint.translations, [:fields, name]) || []
    placeholder = Keyword.get(translations, :placeholder, assigns[:placeholder])
    value = assigns[:value]

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       placeholder: placeholder,
       value: value,
       class: opts[:class],
       monospace: opts[:monospace] || false,
       disabled: assigns[:disabled] || false,
       debounce: assigns[:debounce] || 750
     )}
  end

  def update(%{form: _form, field: _field} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       class: assigns.class,
       monospace: assigns.monospace || false,
       debounce: assigns[:debounce] || 750
     )}
  end

  def update(assigns, socket) do
    value = assigns[:value]

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       value: value,
       class: assigns.class,
       monospace: assigns.monospace || false,
       debounce: assigns[:debounce] || 750
     )}
  end

  def render(%{blueprint: _, input: %{name: name}} = assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      field={name}
      class={@class}
      form={@form}>
      {text_input @form, name,
        placeholder: @placeholder,
        disabled: @disabled,
        phx_debounce: @debounce,
        class: "text#{@monospace && " monospace" || ""}"}
    </FieldBase>
    """
  end

  def render(%{form: _form, field: _field} = assigns) do
    ~F"""
    <FieldBase
      label={@label}
      placeholder={@placeholder}
      instructions={@instructions}
      field={@field}
      form={@form}>
      {text_input @form, @field,
        placeholder: @placeholder,
        disabled: @disabled,
        phx_debounce: @debounce,
        class: "text#{@monospace && " monospace" || ""}"}
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
      {text_input @form, @field,
        value: @value,
        placeholder: @placeholder,
        disabled: @disabled,
        phx_debounce: @debounce,
        class: "text#{@monospace && " monospace" || ""}"}
    </FieldBase>
    """
  end
end
