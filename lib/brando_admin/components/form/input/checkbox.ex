defmodule BrandoAdmin.Components.Form.Input.Checkbox do
  use Surface.Component
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase

  prop form, :form
  prop blueprint, :any

  data name, :any
  data class, :string
  data text, :string
  data small, :boolean

  def update(%{input: %{name: name, opts: opts}} = assigns, socket) do
    {:ok,
     socket
     |> assign(:class, opts[:class])
     |> assign(:text, opts[:text])
     |> assign(:small, Keyword.get(opts, :small, false))
     |> assign(:name, name)
     |> assign(assigns)}
  end

  def render(assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      field={@name}
      class={@class}
      form={@form}>
      <div
        class={"check-wrapper", small: @small}>
        {checkbox @form, @name}
        {label @form, @name, @text, class: "control-label#{if @small, do: " small", else: ""}"}
      </div>
    </FieldBase>
    """
  end
end
