defmodule BrandoAdmin.Components.Form.Input.Radios do
  use BrandoAdmin, :component
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase

  # prop form, :form
  # prop field, :atom
  # prop label, :string
  # prop placeholder, :string
  # prop instructions, :string
  # prop opts, :list, default: []
  # prop current_user, :map
  # prop uploads, :map

  # data class, :string
  # data monospace, :boolean
  # data disabled, :boolean
  # data debounce, :integer
  # data input_options, :list
  # data compact, :boolean

  def render(assigns) do
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

    assigns = prepare_input_component(assigns)

    assigns =
      assigns
      |> assign(:input_options, input_options)

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <%= if Enum.count(@input_options) do %>
        <div class="radios-wrapper">
          <%= for opt <- @input_options do %>
            <div class="form-check">
              <label class="form-check-label">
                <%= radio_button @form, @field, opt.value, class: "form-check-input" %>
                <span class="label-text">
                  <%= opt.label %>
                </span>
              </label>
            </div>
          <% end %>
        </div>
      <% end %>
    </FieldBase.render>
    """
  end
end
