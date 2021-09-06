defmodule BrandoAdmin.Components.Form.Input.Datetime do
  use Surface.Component
  # use Phoenix.LiveComponent
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase
  alias Surface.Components.Form.HiddenInput

  prop form, :form
  prop field, :any
  prop blueprint, :any
  prop input, :any
  prop label, :string
  prop value, :any
  prop class, :css_class
  prop placeholder, :string
  prop instructions, :string

  def update(%{form: form, input: %{name: name, opts: opts}} = assigns, socket) do
    value = input_value(form, name) || get_default(opts)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(value: value)}
  end

  def update(%{form: form, field: field} = assigns, socket) do
    value = input_value(form, field)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(value: value)}
  end

  defp get_default(opts) do
    case Keyword.get(opts, :default) do
      default_fn when is_function(default_fn, 0) ->
        default_fn.()

      default_datetime ->
        default_datetime
    end
  end

  def render(%{blueprint: _, input: %{name: name, opts: opts}} = assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      field={name}
      class={opts[:class]}
      form={@form}>
      <div
        id={"#{@form.id}-#{name}-datetimepicker"}
        class="datetime-wrapper"
        phx-hook="Brando.DateTimePicker">
          <div phx-update="ignore">
            <button
              type="button"
              class="clear-datetime">
              Clear
            </button>
            <HiddenInput
              form={@form}
              field={name}
              value={@value}
              class="flatpickr" />
            <div class="timezone">&mdash; Your timezone is: <span>Unknown</span></div>
          </div>
      </div>
    </FieldBase>
    """
  end

  def render(assigns) do
    ~F"""
    <FieldBase
      label={@label}
      field={@field}
      class={@class}
      form={@form}>
      <div
        id={"#{@form.id}-#{@field}-datetimepicker"}
        class="datetime-wrapper"
        phx-hook="Brando.DateTimePicker">
          <div phx-update="ignore">
            <button
              type="button"
              class="clear-datetime">
              Clear
            </button>
            <HiddenInput
              form={@form}
              field={@field}
              value={@value}
              class="flatpickr" />
            <div class="timezone">&mdash; Your timezone is: <span>Unknown</span></div>
          </div>
      </div>
    </FieldBase>
    """
  end
end
