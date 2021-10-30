defmodule BrandoAdmin.Components.Form.Input.Email do
  use Surface.Component
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase

  prop form, :form
  prop field, :atom
  prop label, :string
  prop placeholder, :string
  prop instructions, :string
  prop opts, :list, default: []
  prop current_user, :map
  prop uploads, :map

  data class, :string
  data monospace, :boolean
  data disabled, :boolean
  data debounce, :integer
  data compact, :boolean

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       class: assigns.opts[:class],
       monospace: assigns.opts[:monospace] || false,
       disabled: assigns.opts[:disabled] || false,
       debounce: assigns.opts[:debounce] || 750,
       compact: assigns.opts[:compact]
     )}
  end

  def render(assigns) do
    ~F"""
    <FieldBase
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      {email_input @form, @field,
        placeholder: @placeholder,
        disabled: @disabled,
        phx_debounce: @debounce,
        class: "text#{@monospace && " monospace" || ""}"}
    </FieldBase>
    """
  end
end
