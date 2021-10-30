defmodule BrandoAdmin.Components.Form.Input.Status do
  use Surface.Component
  use Phoenix.HTML
  import Brando.Gettext
  alias BrandoAdmin.Components.Form.FieldBase

  prop form, :form
  prop field, :atom
  prop label, :string
  prop placeholder, :string
  prop instructions, :string
  prop opts, :list, default: []
  prop current_user, :map
  prop uploads, :map

  data statuses, :list
  data class, :string
  data monospace, :boolean
  data disabled, :boolean
  data debounce, :integer
  data compact, :boolean

  slot default

  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:class, fn -> assigns.opts[:class] end)
      |> assign_new(:statuses, fn ->
        [
          %{value: "draft", label: gettext("Draft")},
          %{value: "pending", label: gettext("Pending")},
          %{value: "published", label: gettext("Published")},
          %{value: "disabled", label: gettext("Deactivated")}
        ]
      end)
      |> assign(
        class: assigns.opts[:class],
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
      <div class="radios-wrapper status">
        <div
          :for={status <- @statuses}
          class="form-check">
          <label class="form-check-label">
            {radio_button @form, @field, status.value, class: "form-check-input"}
            <span class={"label-text", status.value}>
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="12"
                height="12"
                viewBox="0 0 12 12">
                <circle
                  class={status.value}
                  r="6"
                  cy="6"
                  cx="6" />
              </svg>
              {status.label}
            </span>
          </label>
        </div>
      </div>
    </FieldBase>
    """
  end
end
