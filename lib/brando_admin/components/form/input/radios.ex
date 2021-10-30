defmodule BrandoAdmin.Components.Form.Input.Radios do
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
  data input_options, :list
  data compact, :boolean

  def update(assigns, socket) do
    input_options =
      case Keyword.get(assigns.opts, :options) do
        :languages ->
          languages = Brando.config(:languages)
          Enum.map(languages, fn [{:value, val}, {:text, text}] -> %{label: text, value: val} end)

        :admin_languages ->
          admin_languages = Brando.config(:admin_languages)

          Enum.map(admin_languages, fn [{:value, val}, {:text, text}] ->
            %{label: text, value: val}
          end)

        nil ->
          []

        options ->
          options
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:input_options, input_options)
     |> assign(
       class: assigns.opts[:class],
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
        :if={Enum.count(@input_options)}
        class="radios-wrapper">
        <div
          :for={opt <- @input_options}
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
