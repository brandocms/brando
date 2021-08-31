defmodule BrandoAdmin.Components.Form.Input.Radios do
  use Surface.Component
  # use Phoenix.LiveComponent
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase

  prop blueprint, :any
  prop form, :form
  prop field, :any
  prop label, :string
  prop instructions, :string
  prop class, :string
  prop options, :any

  def update(%{input: %{name: name, opts: opts}, blueprint: blueprint} = assigns, socket) do
    input_options =
      case Keyword.get(opts, :options) do
        :languages ->
          languages = Brando.config(:languages)
          Enum.map(languages, fn [{:value, val}, {:text, text}] -> %{label: text, value: val} end)

        nil ->
          []

        options ->
          options
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:input_options, input_options)}
  end

  def update(%{options: input_options} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)}
  end

  def render(%{input: %{name: name, opts: opts}, blueprint: blueprint} = assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      form={@form}
      class={opts[:class]}
      field={name}>
      <div
        :if={Enum.count(@input_options)}
        class="radios-wrapper">
        <div
          :for={opt <- @input_options}
          class="form-check">
          <label class="form-check-label">
            {radio_button @form, name, opt.value, class: "form-check-input"}
            <span class="label-text">{opt.label}</span>
          </label>
        </div>
      </div>
    </FieldBase>
    """
  end

  def render(assigns) do
    ~F"""
    <FieldBase
      label={@label}
      instructions={@instructions}
      form={@form}
      class={@class}
      field={@field}>
      <div
        :if={@options}
        class="radios-wrapper">
        <div
          :for={opt <- @options}
          class="form-check">
          <label class="form-check-label">
            {radio_button @form, @field, opt.value, class: "form-check-input"}
            <span class="label-text">{opt.label}</span>
          </label>
        </div>
      </div>
    </FieldBase>
    """
  end
end
