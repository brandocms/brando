defmodule BrandoAdmin.Components.Form.Input.Date do
  use Surface.LiveComponent
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

  data value, :any
  data class, :string
  data monospace, :boolean
  data disabled, :boolean
  data debounce, :integer
  data compact, :boolean

  def update(assigns, socket) do
    value = input_value(assigns.form, assigns.field) || get_default(assigns.opts)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       value: value,
       class: assigns.opts[:class],
       monospace: assigns.opts[:monospace] || false,
       disabled: assigns.opts[:disabled] || false,
       debounce: assigns.opts[:debounce] || 750,
       compact: assigns.opts[:compact]
     )}
  end

  defp get_default(opts) do
    case Keyword.get(opts, :default) do
      default_fn when is_function(default_fn, 0) ->
        default_fn.()

      default_date ->
        default_date
    end
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
        id={"#{@form.id}-#{@field}-datepicker"}
        class="datetime-wrapper"
        phx-hook="Brando.DatePicker">
          <div phx-update="ignore">
            <button
              type="button"
              class="clear-datetime">
              {gettext "Clear"}
            </button>
            {hidden_input @form, @field, value: @value, class: "flatpickr"}
          </div>
      </div>
    </FieldBase>
    """
  end
end
