defmodule BrandoAdmin.Components.Form.Input.Textarea do
  use Phoenix.Component
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase

  # prop form, :form
  # prop field, :atom
  # prop label, :string
  # prop placeholder, :string
  # prop instructions, :string
  # prop opts, :list, default: []
  # prop current_user, :map
  # prop uploads, :map

  # data class, :string
  # data monospace, :boolean
  # data disabled, :boolean
  # data debounce, :integer
  # data compact, :boolean
  # data rows, :integer

  # slot default

  def render(assigns) do
    assigns =
      assign(assigns,
        class: assigns.opts[:class],
        monospace: assigns.opts[:monospace] || false,
        disabled: assigns.opts[:disabled] || false,
        debounce: assigns.opts[:debounce] || 750,
        compact: assigns.opts[:compact],
        rows: assigns.opts[:rows] || 3
      )

    ~H"""
    <FieldBase
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      {textarea @form, @field,
        class: "text",
        placeholder: @placeholder,
        rows: @rows,
        disabled: @disabled,
        phx_debounce: @debounce}
    </FieldBase>
    """
  end
end
