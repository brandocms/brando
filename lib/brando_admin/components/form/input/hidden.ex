defmodule BrandoAdmin.Components.Form.Input.Hidden do
  use BrandoAdmin, :component
  use Phoenix.HTML

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
    <%= hidden_input @form, @field %>
    """
  end
end
