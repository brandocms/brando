defmodule BrandoAdmin.Components.Form.Input.Toggle do
  use BrandoAdmin, :component
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase
  alias BrandoAdmin.Components.Form.Label

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

  # slot default

  def render(assigns) do
    assigns =
      assigns
      |> assign(
        class: assigns.opts[:class],
        monospace: assigns.opts[:monospace] || false,
        disabled: assigns.opts[:disabled] || false,
        debounce: assigns.opts[:debounce] || 750,
        compact: assigns.opts[:compact]
      )
      |> assign_new(:inner_block, fn -> nil end)

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <Label.render form={@form} field={@field} class={["switch", small: @compact]}>
        <%= if @inner_block do %>
          <%= render_slot @inner_block %>
        <% else %>
          <%= checkbox @form, @field %>
        <% end %>
        <div class="slider round"></div>
      </Label.render>
    </FieldBase.render>
    """
  end
end
