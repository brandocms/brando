defmodule BrandoAdmin.Components.Form.FieldBase do
  use Surface.Component
  use Phoenix.HTML
  import Phoenix.HTML.Form, only: [input_id: 2]
  alias BrandoAdmin.Components.Form.ErrorTag

  prop form, :form
  prop field, :any, required: true
  prop label, :string
  prop instructions, :string
  prop class, :string
  prop compact, :boolean, default: false

  data failed, :boolean

  slot default
  slot meta
  slot header

  def mount(socket) do
    {:ok, socket |> assign(:failed, false)}
  end

  def update(assigns, socket) do
    failed = assigns.form && has_error(assigns.form, assigns.field)
    label = assigns.label || assigns.field |> to_string |> Brando.Utils.humanize()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:failed, failed)
     |> assign(:label, label)}
  end

  def render(assigns) do
    ~F"""
    <div
      class={"field-wrapper", @class}
      id={"#{@form.id}-#{@field}-field-wrapper"}>
      <div :if={@field} class="label-wrapper">
        <label
          for={input_id(@form, @field)}
          class={"control-label", failed: @failed}>
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
      <div class="field-base" id={"#{@form.id}-#{@field}-field-base"}>
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
