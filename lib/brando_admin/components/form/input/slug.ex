defmodule BrandoAdmin.Components.Form.Input.Slug do
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
  data slug_for, :boolean

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       class: assigns.opts[:class],
       monospace: assigns.opts[:monospace] || false,
       disabled: assigns.opts[:disabled] || false,
       debounce: assigns.opts[:debounce] || 750,
       compact: assigns.opts[:compact],
       slug_for: assigns.opts[:for]
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
      {text_input @form, @field,
        class: "text monospace",
        phx_hook: "Brando.Slug",
        phx_debounce: 750,
        data_slug_for: "#{@form.id}_#{@slug_for}",
        autocorrect: "off",
        spellcheck: "false"}
    </FieldBase>
    """
  end
end
