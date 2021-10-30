defmodule BrandoAdmin.Components.Form.Input.Checkbox do
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
  data text, :string

  def render(assigns) do
    assigns =
      assign(assigns,
        class: assigns.opts[:class],
        monospace: assigns.opts[:monospace] || false,
        disabled: assigns.opts[:disabled] || false,
        debounce: assigns.opts[:debounce] || 750,
        compact: assigns.opts[:compact],
        text: assigns.opts[:text]
      )

    ~F"""
    <FieldBase
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <div
        class={"check-wrapper", small: @compact}>
        {checkbox @form, @field}
        {label @form, @field, @text, class: "control-label#{if @compact, do: " small", else: ""}"}
      </div>
    </FieldBase>
    """
  end
end
