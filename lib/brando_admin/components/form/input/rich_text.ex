defmodule BrandoAdmin.Components.Form.Input.RichText do
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

  data initial_props, :map

  def v(form, field), do: Ecto.Changeset.get_field(form.source, field)

  def render(assigns) do
    assigns =
      assigns
      |> assign(
        class: assigns.opts[:class],
        compact: assigns.opts[:compact],
        debounce: assigns.opts[:debounce] || 750
      )
      |> assign_new(:initial_props, fn ->
        Jason.encode!(%{content: v(assigns.form, assigns.field)})
      end)

    ~F"""
    <FieldBase
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      {hidden_input @form, @field, class: "tiptap-text", phx_debounce: 750}
      <div class="tiptap-wrapper" id={"#{@form.id}-#{@field}-rich-text-wrapper"}>
        <div
          id={"#{@form.id}-#{@field}-rich-text"}
          phx-hook="Brando.TipTap"
          data-name="TipTap"
          data-props={@initial_props}>
          <div
            id={"#{@form.id}-#{@field}-rich-text-target-wrapper"}
            class="tiptap-target-wrapper"
            phx-update="ignore">
            <div
              id={"#{@form.id}-#{@field}-rich-text-target"}
              class="tiptap-target">
            </div>
          </div>
        </div>
      </div>
    </FieldBase>
    """
  end
end
