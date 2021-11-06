defmodule BrandoAdmin.Components.Form.Input.Password do
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

  def render(assigns) do
    assigns =
      assigns
      |> prepare_input_component()
      |> assign(:value, input_value(assigns.form, assigns.field))

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <%= password_input @form, @field,
        placeholder: @placeholder,
        disabled: @disabled,
        phx_debounce: @debounce,
        value: @value,
        class: "text#{@monospace && " monospace" || ""}" %>
    </FieldBase.render>
    """
  end
end
