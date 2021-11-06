defmodule BrandoAdmin.Components.Form.Input.Checkbox do
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
  # data text, :string

  def render(assigns) do
    assigns = prepare_input_component(assigns)

    assigns =
      assign(assigns,
        text: assigns.opts[:text]
      )

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <div
        class={render_classes(["check-wrapper", small: @compact])}>
        <%= checkbox @form, @field %>
        <%= label @form, @field, @text, class: "control-label#{if @compact, do: " small", else: ""}" %>
      </div>
    </FieldBase.render>
    """
  end
end
