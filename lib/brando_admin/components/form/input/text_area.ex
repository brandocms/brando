defmodule BrandoAdmin.Components.Form.Input.Textarea do
  use BrandoAdmin, :component
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
    assigns = prepare_input_component(assigns)

    assigns =
      assign(assigns,
        rows: assigns.opts[:rows] || 3
      )

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <%= textarea @form, @field,
        class: "text",
        placeholder: @placeholder,
        rows: @rows,
        disabled: @disabled,
        phx_debounce: @debounce %>
    </FieldBase.render>
    """
  end
end
