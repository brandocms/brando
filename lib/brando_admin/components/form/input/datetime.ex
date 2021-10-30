defmodule BrandoAdmin.Components.Form.Input.Datetime do
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

  data value, :any
  data class, :string
  data monospace, :boolean
  data disabled, :boolean
  data debounce, :integer
  data compact, :boolean

  defp get_default(opts) do
    case Keyword.get(opts, :default) do
      default_fn when is_function(default_fn, 0) ->
        default_fn.()

      default_datetime ->
        default_datetime
    end
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        value: input_value(assigns.form, assigns.field) || get_default(assigns.opts),
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
      <div
        id={"#{@form.id}-#{@field}-datetimepicker"}
        class="datetime-wrapper"
        phx-hook="Brando.DateTimePicker">
          <div phx-update="ignore">
            <button
              type="button"
              class="clear-datetime">
              {gettext "Clear"}
            </button>
            {hidden_input @form, @field, value: @value, class: "flatpickr"}
            <div class="timezone">&mdash; {gettext "Your timezone is"}: <span>Unknown</span></div>
          </div>
      </div>
    </FieldBase>
    """
  end
end
