defmodule BrandoAdmin.Components.Form.Input.Code do
  use Surface.LiveComponent
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

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       class: assigns.opts[:class],
       debounce: assigns.opts[:debounce] || 750,
       compact: assigns.opts[:compact]
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
      <div
        id={"#{@form.id}-#{@field}-code"}
        class="code-editor"
        phx-hook="Brando.CodeEditor">
        {textarea @form, @field, phx_debounce: 750}
        <div phx-update="ignore">
          <div class="editor"></div>
        </div>
      </div>
    </FieldBase>
    """
  end
end
