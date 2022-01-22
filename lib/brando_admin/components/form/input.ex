defmodule BrandoAdmin.Components.Form.Input do
  use BrandoAdmin, :component
  use BrandoAdmin.Translator, "forms"
  use Phoenix.HTML

  import Brando.Gettext
  import BrandoAdmin.Components.Content.List.Row, only: [status_circle: 1]

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.FieldBase

  # prop current_user, :any
  # prop form, :any
  # prop field, :any
  # prop label, :any
  # prop placeholder, :any
  # prop instructions, :any
  # prop opts, :list, default: []
  # prop uploads, :any
  # prop type, :any

  # data component_module, :any
  # data component_opts, :any
  # data component_id, :string

  ##
  ## Form inputs (function components)

  def checkbox(assigns) do
    assigns = prepare_input_component(assigns)

    assigns =
      assign(assigns,
        text: assigns.opts[:text]
      )

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <div
        class={render_classes(["check-wrapper", small: @compact])}>
        <%= checkbox @form, @field %>
        <%= label @form, @field, @text, class: "control-label#{if @compact, do: " small", else: ""}" %>
      </div>
    </FieldBase.render>
    """
  end

  def code(assigns) do
    assigns = prepare_input_component(assigns)

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <div
        id={"#{@form.id}-#{@field}-code"}
        class="code-editor"
        phx-hook="Brando.CodeEditor">
        <%= textarea @form, @field, phx_debounce: 750 %>
        <div phx-update="ignore">
          <div class="editor"></div>
        </div>
      </div>
    </FieldBase.render>
    """
  end

  def color(assigns) do
    assigns = prepare_input_component(assigns)

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <div
        id={"#{@form.id}-#{@field}-color-picker"}
        phx-hook="Brando.ColorPicker"
        data-input={"##{@form.id}_#{@field}"}
        data-color={input_value(@form, @field) || gettext("No color selected")}>
        <div class="picker">

          <%= hidden_input @form, @field, phx_debounce: @debounce %>
          <div phx-update="ignore" class="picker-target">
            <div class="circle-and-hex">
              <span class="circle tiny"></span>
              <span class="color-hex"></span>
            </div>
          </div>
        </div>
      </div>
    </FieldBase.render>
    """
  end

  defp get_default(opts) do
    case Keyword.get(opts, :default) do
      default_fn when is_function(default_fn, 0) -> default_fn.()
      default_val -> default_val
    end
  end

  def date(assigns) do
    value = input_value(assigns.form, assigns.field) || get_default(assigns.opts)
    assigns = prepare_input_component(assigns)

    assigns =
      assign(assigns,
        value: value
      )

    ~H"""
    <FieldBase.render
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
              <%= gettext "Clear" %>
            </button>
            <%= hidden_input @form, @field, value: @value, class: "flatpickr" %>
          </div>
      </div>
    </FieldBase.render>
    """
  end

  def datetime(assigns) do
    assigns = prepare_input_component(assigns)

    assigns =
      assign(assigns,
        value: input_value(assigns.form, assigns.field) || get_default(assigns.opts),
        class: assigns.opts[:class],
        locale: Gettext.get_locale()
      )

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <div
        id={"#{@form.id}-#{@field}-datetimepicker"}
        class="datetime-wrapper"
        phx-hook="Brando.DateTimePicker"
        data-locale={@locale}>
          <div phx-update="ignore">
            <button
              type="button"
              class="clear-datetime">
              <%= gettext "Clear" %>
            </button>
            <%= hidden_input @form, @field, value: @value, class: "flatpickr" %>
            <div class="timezone">&mdash; <%= gettext "Your timezone is" %>: <span>Unknown</span></div>
          </div>
      </div>
    </FieldBase.render>
    """
  end

  def email(assigns) do
    assigns = prepare_input_component(assigns)

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <%= email_input @form, @field,
        placeholder: @placeholder,
        disabled: @disabled,
        phx_debounce: @debounce,
        class: "text#{@monospace && " monospace" || ""}" %>
    </FieldBase.render>
    """
  end

  def hidden(assigns) do
    assigns = prepare_input_component(assigns)

    ~H"""
    <%= hidden_input @form, @field %>
    """
  end

  def number(assigns) do
    assigns = prepare_input_component(assigns)

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <%= number_input @form, @field,
        placeholder: @placeholder,
        disabled: @disabled,
        phx_debounce: @debounce,
        class: "text#{@monospace && " monospace" || ""}" %>
    </FieldBase.render>
    """
  end

  def password(assigns) do
    assigns =
      assigns
      |> prepare_input_component()
      |> assign(:value, input_value(assigns.form, assigns.field))

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <%= password_input @form, @field,
        placeholder: @placeholder,
        disabled: @disabled,
        phx_debounce: @debounce,
        value: @value,
        class: "text#{@monospace && " monospace" || ""}" %>
    </FieldBase.render>
    """
  end

  def phone(assigns) do
    assigns = prepare_input_component(assigns)

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <%= telephone_input @form, @field,
        placeholder: @placeholder,
        disabled: @disabled,
        phx_debounce: @debounce,
        class: "text#{@monospace && " monospace" || ""}" %>
    </FieldBase.render>
    """
  end

  def radios(assigns) do
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

    assigns =
      assigns
      |> prepare_input_component()
      |> assign(:input_options, input_options)

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <%= if @input_options != [] do %>
        <div class="radios-wrapper">
          <%= for opt <- @input_options do %>
            <div class="form-check">
              <label class="form-check-label">
                <%= radio_button @form, @field, opt.value, class: "form-check-input" %>
                <span class="label-text">
                  <%= g(@form.source.data.__struct__, to_string(opt.label)) %>
                </span>
              </label>
            </div>
          <% end %>
        </div>
      <% end %>
    </FieldBase.render>
    """
  end

  def rich_text(assigns) do
    assigns =
      assigns
      |> prepare_input_component()
      |> assign_new(:initial_props, fn ->
        Jason.encode!(%{content: Ecto.Changeset.get_field(assigns.form.source, assigns.field)})
      end)

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <%= hidden_input @form, @field, class: "tiptap-text", phx_debounce: 750 %>
      <div class="tiptap-wrapper" id={"#{@form.id}-#{@field}-rich-text-wrapper"}>
        <div
          id={"#{@form.id}-#{@field}-rich-text"}
          phx-hook="Brando.TipTap"
          data-name="TipTap"
          data-props={@initial_props}>
          <div
            id={"#{@form.id}-#{@field}-rich-text-target-wrapper"}
            class="tiptap-target-wrapper"
            phx-update="ignore">
            <div
              id={"#{@form.id}-#{@field}-rich-text-target"}
              class="tiptap-target">
            </div>
          </div>
        </div>
      </div>
    </FieldBase.render>
    """
  end

  def slug(assigns) do
    assigns =
      assigns
      |> prepare_input_component()
      |> assign(:slug_for, assigns.opts[:for])
      |> assign_new(:url, fn -> nil end)
      |> assign_new(:data_slug_for, fn -> prepare_slug_for(assigns.form, assigns.opts[:for]) end)
      |> assign_new(:data_slug_type, fn ->
        (Keyword.get(assigns.opts, :camel_case) && "camel") || "standard"
      end)
      |> maybe_assign_url(assigns.opts[:show_url])

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <%= text_input @form, @field,
        class: "text monospace",
        phx_hook: "Brando.Slug",
        phx_debounce: 750,
        data_slug_for: @data_slug_for,
        data_slug_type: @data_slug_type,
        autocorrect: "off",
        spellcheck: "false" %>
      <%= if @url do %>
      <div class="badge no-case no-border">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z"/><path d="M6.235 6.453a8 8 0 0 0 8.817 12.944c.115-.75-.137-1.47-.24-1.722-.23-.56-.988-1.517-2.253-2.844-.338-.355-.316-.628-.195-1.437l.013-.091c.082-.554.22-.882 2.085-1.178.948-.15 1.197.228 1.542.753l.116.172c.328.48.571.59.938.756.165.075.37.17.645.325.652.373.652.794.652 1.716v.105c0 .391-.038.735-.098 1.034a8.002 8.002 0 0 0-3.105-12.341c-.553.373-1.312.902-1.577 1.265-.135.185-.327 1.132-.95 1.21-.162.02-.381.006-.613-.009-.622-.04-1.472-.095-1.744.644-.173.468-.203 1.74.356 2.4.09.105.107.3.046.519-.08.287-.241.462-.292.498-.096-.056-.288-.279-.419-.43-.313-.365-.705-.82-1.211-.96-.184-.051-.386-.093-.583-.135-.549-.115-1.17-.246-1.315-.554-.106-.226-.105-.537-.105-.865 0-.417 0-.888-.204-1.345a1.276 1.276 0 0 0-.306-.43zM12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10z"/></svg> <%= @url %>
      </div>
      <% end %>
    </FieldBase.render>
    """
  end

  defp maybe_assign_url(assigns, true) do
    entry = Ecto.Changeset.apply_changes(assigns.form.source)
    schema = entry.__struct__
    url = schema.__absolute_url__(entry)
    assign(assigns, :url, url)
  end

  defp maybe_assign_url(assigns, _) do
    assigns
  end

  defp prepare_slug_for(form, slug_for) when is_list(slug_for) do
    Enum.reduce(slug_for, [], fn sf, acc ->
      acc ++ List.wrap("#{form.id}_#{sf}")
    end)
    |> Enum.join(",")
  end

  defp prepare_slug_for(form, slug_for) do
    "#{form.id}_#{slug_for}"
  end

  def status(assigns) do
    assigns =
      assigns
      |> prepare_input_component()
      |> assign_new(:statuses, fn ->
        [
          %{value: "draft", label: gettext("Draft")},
          %{value: "pending", label: gettext("Pending")},
          %{value: "published", label: gettext("Published")},
          %{value: "disabled", label: gettext("Deactivated")}
        ]
      end)

    if assigns.compact do
      status_compact(assigns)
    else
      ~H"""
      <FieldBase.render
        form={@form}
        field={@field}
        label={@label}
        instructions={@instructions}
        class={@class}
        compact={@compact}>
        <div class="radios-wrapper status">
          <%= for status <- @statuses do %>
            <div class="form-check">
              <label class="form-check-label">
                <%= radio_button @form, @field, status.value, class: "form-check-input" %>
                <span class={render_classes(["label-text", status.value])}>
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
                  <%= status.label %>
                </span>
              </label>
            </div>
          <% end %>
        </div>
      </FieldBase.render>
      """
    end
  end

  def status_compact(assigns) do
    assigns =
      assigns
      |> prepare_input_component()
      |> assign(:current_status, input_value(assigns.form, assigns.field))
      |> assign(:id, "status-dropdown-#{assigns.form.id}-#{assigns.form.index}-#{assigns.field}")

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <div class="radios-wrapper status compact" phx-click={toggle_dropdown("##{@id}")}>
        <.status_circle status={@current_status} publish_at={nil} />
        <div class="status-dropdown hidden" id={@id}>
        <%= for status <- @statuses do %>
          <div class="form-check">
            <label class="form-check-label">
              <%= radio_button @form, @field, status.value, class: "form-check-input" %>
              <span class={render_classes(["label-text", status.value])}>
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
                <%= status.label %>
              </span>
            </label>
          </div>
        <% end %>
        </div>
      </div>
    </FieldBase.render>
    """
  end

  def text(assigns) do
    assigns = prepare_input_component(assigns)

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <%= text_input @form, @field,
        placeholder: @placeholder,
        disabled: @disabled,
        phx_debounce: @debounce,
        class: "text#{@monospace && " monospace" || ""}" %>
    </FieldBase.render>
    """
  end

  def textarea(assigns) do
    assigns = prepare_input_component(assigns)

    assigns =
      assign(assigns,
        rows: assigns.opts[:rows] || 3
      )

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <%= textarea @form, @field,
        class: "text",
        placeholder: @placeholder,
        rows: @rows,
        disabled: @disabled,
        phx_debounce: @debounce,
        id: make_uid(@form, @field, @uid)
      %>
    </FieldBase.render>
    """
  end

  def toggle(assigns) do
    assigns =
      assigns
      |> prepare_input_component()
      |> assign_new(:inner_block, fn -> nil end)

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <Form.label
        form={@form}
        field={@field}
        class={render_classes(["switch", small: @compact])}>
        <%= if @inner_block do %>
          <%= render_slot @inner_block %>
        <% else %>
          <%= checkbox @form, @field %>
        <% end %>
        <div class="slider round"></div>
      </Form.label>
    </FieldBase.render>
    """
  end
end
