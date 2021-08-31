defmodule BrandoAdmin.Components.Form.FieldBase do
  use Surface.Component
  use Phoenix.HTML
  import Phoenix.HTML.Form, only: [input_id: 2]
  alias BrandoAdmin.Components.Form.ErrorTag

  prop compact, :boolean, default: false
  prop form, :form
  prop field, :any, required: true
  prop class, :string
  prop blueprint, :any
  prop label, :string
  prop placeholder, :string
  prop instructions, :string

  data failed, :boolean

  slot default
  slot meta
  slot header

  def mount(socket) do
    {:ok, socket |> assign(:failed, false)}
  end

  def update(assigns, socket) do
    translations =
      (assigns.blueprint && get_in(assigns.blueprint.translations, [:fields, assigns.field])) ||
        []

    label =
      Keyword.get(
        translations,
        :label,
        assigns.label || Phoenix.Naming.humanize(assigns.field)
      )

    instructions =
      case Keyword.get(translations, :instructions, assigns.instructions) do
        nil -> nil
        val -> raw(val)
      end

    failed = assigns.form && has_error(assigns.form, assigns.field)

    {:ok,
     socket
     |> assign(Map.delete(assigns, :blueprint))
     |> assign(:label, label)
     |> assign(:instructions, instructions)
     |> assign(:failed, failed)}
  end

  def render(assigns) do
    ~F"""
    <div class={"field-wrapper", @class}>
      <div :if={@field} class="label-wrapper">
        <label
          for={input_id(@form, @field)}
          class={"control-label", failed: assigns[:failed]}>
          <span>{@label}</span>
        </label>
        {#if @form}
          <ErrorTag
            form={@form}
            field={@field}
          />
        {/if}
        {#if slot_assigned?(:header)}
          <div class="field-wrapper-header">
            <#slot name="header"></#slot>
          </div>
        {/if}
      </div>
      <div class="field-base">
        <#slot></#slot>
      </div>
      {#if @instructions || slot_assigned?(:meta)}
        <div class="meta">
          {#if @instructions}
            <div class="help-text">
              ↳ <span>{@instructions}</span>
            </div>
            {#if slot_assigned?(:meta)}
              <div class="extra">
                <#slot name="meta"></#slot>
              </div>
            {/if}
          {/if}
        </div>
      {/if}
    </div>
    """
  end

  defp has_error(form, field) do
    case Keyword.get_values(form.errors, field) do
      [] -> false
      _ -> true
    end
  end
end
