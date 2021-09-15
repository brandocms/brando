defmodule BrandoAdmin.Components.Form.Input.Date do
  use Surface.LiveComponent
  # use Phoenix.LiveComponent
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase

  prop form, :form
  prop field, :any
  prop blueprint, :any
  prop input, :any
  prop label, :string
  prop value, :any
  prop placeholder, :string
  prop instructions, :string

  def update(%{form: form, input: %{name: name, opts: opts}} = assigns, socket) do
    value = input_value(form, name) || get_default(opts)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(value: value)}
  end

  defp get_default(opts) do
    case Keyword.get(opts, :default) do
      default_fn when is_function(default_fn, 0) ->
        default_fn.()

      default_date ->
        default_date
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
        id={"#{@form.id}-#{name}-datepicker"}
        class="datetime-wrapper"
        phx-hook="Brando.DatePicker">
          <div phx-update="ignore">
            <button
              type="button"
              class="clear-datetime">
              Clear
            </button>
            {hidden_input @form, name, value: @value, class: "flatpickr"}
          </div>
      </div>
    </FieldBase>
    """
  end
end
