defmodule BrandoAdmin.Components.Form.Input.Text do
  use Surface.Component
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase
  alias Surface.Components.Form.TextInput

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
       disabled: assigns[:disabled] || false
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
       monospace: assigns.monospace || false
     )}
  end

  def render(%{blueprint: _, input: %{name: name, opts: opts}} = assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      field={name}
      class={@class}
      form={@form}>
      <TextInput
        form={@form}
        field={name}
        value={@value}
        opts={placeholder: @placeholder, disabled: @disabled}
        class={"text", monospace: @monospace} />
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
      <TextInput
        form={@form}
        field={@field}
        value={@value}
        opts={disabled: @disabled}
        class={"text", monospace: @monospace} />
    </FieldBase>
    """
  end
end
