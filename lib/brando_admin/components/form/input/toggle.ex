defmodule BrandoAdmin.Components.Form.Input.Toggle do
  use Surface.Component
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase
  alias BrandoAdmin.Components.Form.Label

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

  slot default

  def render(assigns) do
    assigns =
      assign(assigns,
        class: assigns.opts[:class],
        monospace: assigns.opts[:monospace] || false,
        disabled: assigns.opts[:disabled] || false,
        debounce: assigns.opts[:debounce] || 750,
        compact: assigns.opts[:compact]
      )

    ~F"""
    <FieldBase
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <Label form={@form} field={@field} class={"switch", small: @compact}>
        {#if slot_assigned?(:default)}
          <#slot />
        {#else}
          {checkbox @form, @field}
        {/if}
        <div class="slider round"></div>
      </Label>
    </FieldBase>
    """
  end
end
