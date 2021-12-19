defmodule BrandoAdmin.Components.Form.Input.Color do
  use BrandoAdmin, :component
  use Phoenix.HTML
  import Brando.Gettext
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
    assigns = prepare_input_component(assigns)

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <div
        id={"#{@form.id}-#{@field}-color-picker"}
        phx-hook="Brando.ColorPicker"
        data-input={"##{@form.id}_#{@field}"}
        data-color={input_value(@form, @field) || gettext("No color selected")}>
        <div class="picker">

          <%= hidden_input @form, @field, phx_debounce: @debounce %>
          <div phx-update="ignore" class="picker-target">
            <div class="circle-and-hex">
              <span class="circle tiny"></span>
              <span class="color-hex"></span>
            </div>
          </div>
        </div>
      </div>
    </FieldBase.render>
    """
  end
end
