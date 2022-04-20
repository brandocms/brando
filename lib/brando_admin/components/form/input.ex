defmodule BrandoAdmin.Components.Form.Input do
  use BrandoAdmin, :component
  use BrandoAdmin.Translator, "forms"
  use Phoenix.HTML

  import Brando.Gettext
  import BrandoAdmin.Components.Content.List.Row, only: [status_circle: 1]

  alias BrandoAdmin.Components.Form

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
    <Form.field_base
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <div class={render_classes(["check-wrapper", small: @compact])}>
        <.input type={:checkbox} form={@form} field={@field} />
        <Form.label form={@form} field={@field} class={render_classes(["control-label", small: @compact])}><%= @text %></Form.label>
      </div>
    </Form.field_base>
    """
  end

  def code(assigns) do
    assigns = prepare_input_component(assigns)

    ~H"""
    <Form.field_base
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
        <.input type={:textarea}
          form={@form}
          field={@field}
          phx_debounce={750} />
        <div
          id={"#{@form.id}-#{@field}-code-editor"}
          phx-update="ignore">
          <div class="editor"></div>
        </div>
      </div>
    </Form.field_base>
    """
  end

  def color(assigns) do
    assigns =
      assigns
      |> prepare_input_component()
      |> assign(:opacity, Keyword.get(assigns.opts, :opacity, false))
      |> assign(:picker, Keyword.get(assigns.opts, :picker, true))
      |> assign(:palette_id, Keyword.get(assigns.opts, :palette_id))

    assigns =
      assign_new(assigns, :palette_colors, fn ->
        if assigns.palette_id do
          case Brando.Content.get_palette(assigns.palette_id) do
            {:ok, palette} ->
              palette.colors
              |> Enum.map(& &1.hex_value)
              |> Enum.uniq()
              |> Enum.join(",")
          end
        end
      end)

    ~H"""
    <Form.field_base
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
        data-color={input_value(@form, @field) || gettext("No color selected")}
        data-opacity={@opacity}
        data-picker={@picker}
        data-palette={@palette_colors}>
        <div class="picker">
          <.input type={:hidden} form={@form} field={@field} phx_debounce={@debounce} />
          <div
            id={"#{@form.id}-#{@field}-color-picker-target"}
            phx-update="ignore"
            class="picker-target">
            <div class="circle-and-hex">
              <span class="circle tiny"></span>
              <span class="color-hex"></span>
            </div>
          </div>
        </div>
      </div>
    </Form.field_base>
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
    <Form.field_base
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
          <div
            id={"#{@form.id}-#{@field}-datepicker-flatpickr"}
            phx-update="ignore">
            <button
              type="button"
              class="clear-datetime">
              <%= gettext "Clear" %>
            </button>
            <.input type={:hidden} form={@form} field={@field} value={@value} class="flatpickr" />
          </div>
      </div>
    </Form.field_base>
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
    <Form.field_base
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
          <div
            id={"#{@form.id}-#{@field}-datetimepicker-flatpickr"}
            phx-update="ignore">
            <button
              type="button"
              class="clear-datetime">
              <%= gettext "Clear" %>
            </button>
            <.input type={:hidden} form={@form} field={@field} value={@value} class="flatpickr" />
            <div class="timezone">&mdash; <%= gettext "Your timezone is" %>: <span>Unknown</span></div>
          </div>
      </div>
    </Form.field_base>
    """
  end

  def email(assigns) do
    assigns = prepare_input_component(assigns)

    ~H"""
    <Form.field_base
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
    </Form.field_base>
    """
  end

  def number(assigns) do
    assigns = prepare_input_component(assigns)

    ~H"""
    <Form.field_base
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
    </Form.field_base>
    """
  end

  def password(assigns) do
    assigns =
      assigns
      |> prepare_input_component()
      |> assign(:value, input_value(assigns.form, assigns.field))

    ~H"""
    <Form.field_base
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
    </Form.field_base>
    """
  end

  def phone(assigns) do
    assigns = prepare_input_component(assigns)

    ~H"""
    <Form.field_base
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
    </Form.field_base>
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
    <Form.field_base
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
    </Form.field_base>
    """
  end

  def rich_text(assigns) do
    assigns = prepare_input_component(assigns)

    ~H"""
    <Form.field_base
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <div class="tiptap-wrapper" id={"#{@form.id}-#{@field}-rich-text-wrapper"}>
        <div
          id={"#{@form.id}-#{@field}-rich-text"}
          phx-hook="Brando.TipTap"
          data-name="TipTap">
          <div
            id={"#{@form.id}-#{@field}-rich-text-target-wrapper"}
            class="tiptap-target-wrapper"
            phx-update="ignore">
            <div
              id={"#{@form.id}-#{@field}-rich-text-target"}
              class="tiptap-target">
            </div>
          </div>
          <.input type={:hidden} form={@form} field={@field} class="tiptap-text" phx_debounce={750} />
        </div>
      </div>
    </Form.field_base>
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
    <Form.field_base
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <.input
        type={:text}
        form={@form}
        field={@field}
        class="text monospace"
        phx_hook="Brando.Slug"
        phx_debounce={750}
        data_slug_for={@data_slug_for}
        data_slug_type={@data_slug_type}
        autocorrect="off"
        spellcheck="false" />
      <%= if @url do %>
      <div class="badge no-case no-border">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z"/><path d="M6.235 6.453a8 8 0 0 0 8.817 12.944c.115-.75-.137-1.47-.24-1.722-.23-.56-.988-1.517-2.253-2.844-.338-.355-.316-.628-.195-1.437l.013-.091c.082-.554.22-.882 2.085-1.178.948-.15 1.197.228 1.542.753l.116.172c.328.48.571.59.938.756.165.075.37.17.645.325.652.373.652.794.652 1.716v.105c0 .391-.038.735-.098 1.034a8.002 8.002 0 0 0-3.105-12.341c-.553.373-1.312.902-1.577 1.265-.135.185-.327 1.132-.95 1.21-.162.02-.381.006-.613-.009-.622-.04-1.472-.095-1.744.644-.173.468-.203 1.74.356 2.4.09.105.107.3.046.519-.08.287-.241.462-.292.498-.096-.056-.288-.279-.419-.43-.313-.365-.705-.82-1.211-.96-.184-.051-.386-.093-.583-.135-.549-.115-1.17-.246-1.315-.554-.106-.226-.105-.537-.105-.865 0-.417 0-.888-.204-1.345a1.276 1.276 0 0 0-.306-.43zM12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10z"/></svg> <%= @url %>
      </div>
      <% end %>
    </Form.field_base>
    """
  end

  def hidden(assigns) do
    ~H"""
    <.input
      type={:hidden}
      form={@form}
      field={@field} />
    """
  end

  def input(%{type: :checkbox} = assigns) do
    extra =
      assigns_to_attributes(assigns, [
        :form,
        :field,
        :type,
        :uid,
        :id_prefix
      ])

    assigns = assign(assigns, :extra, extra)

    assigns =
      assigns
      |> assign_new(:value, fn -> maybe_html_escape(input_value(assigns.form, assigns.field)) end)
      |> assign_new(:id, fn -> input_id(assigns.form, assigns.field) end)
      |> assign_new(:name, fn -> input_name(assigns.form, assigns.field) end)
      |> assign_new(:checked_value, fn -> maybe_html_escape(true) end)
      |> assign_new(:unchecked_value, fn -> maybe_html_escape(false) end)
      |> assign_new(:hidden_input, fn -> true end)
      |> process_input_id()

    assigns = assign(assigns, :checked, assigns.value == assigns.checked_value)

    if assigns.hidden_input do
      ~H"""
      <input type={:hidden} name={@name} id={"#{@id}-unchecked"} value={@unchecked_value} {@extra}>
      <input type={@type} name={@name} id={"#{@id}"} value={@checked_value} checked={@checked} {@extra}>
      """
    else
      ~H"""
      <input type={@type} name={@name} id={"#{@id}"} value={@checked_value} {@extra}>
      """
    end
  end

  def input(%{type: :textarea} = assigns) do
    extra =
      assigns_to_attributes(assigns, [
        :form,
        :field,
        :type,
        :uid,
        :id_prefix
      ])

    assigns = assign(assigns, :extra, extra)

    assigns =
      if assigns[:value] do
        assigns
      else
        assign(assigns, :value, maybe_html_escape(input_value(assigns.form, assigns.field)))
      end

    assigns =
      if assigns[:id] do
        assigns
      else
        assign(assigns, :id, input_id(assigns.form, assigns.field))
      end

    assigns =
      if assigns[:name] do
        assigns
      else
        assign(assigns, :name, input_name(assigns.form, assigns.field))
      end

    assigns = process_input_id(assigns)

    ~H"""
    <textarea type={@type} name={@name} id={@id} {@extra}><%= @value %></textarea>
    """
  end

  def input(assigns) do
    extra =
      assigns_to_attributes(assigns, [
        :form,
        :field,
        :type,
        :uid,
        :id_prefix
      ])

    assigns = assign(assigns, :extra, extra)

    assigns =
      if assigns[:value] do
        assigns
      else
        assign(assigns, :value, maybe_html_escape(input_value(assigns.form, assigns.field)))
      end

    assigns =
      if assigns[:id] do
        assigns
      else
        assign(assigns, :id, input_id(assigns.form, assigns.field))
      end

    assigns =
      if assigns[:name] do
        assigns
      else
        assign(assigns, :name, input_name(assigns.form, assigns.field))
      end

    assigns = process_input_id(assigns)

    ~H"""
    <input type={@type} name={@name} id={@id} value={@value} {@extra}>
    """
  end

  defp process_input_id(%{uid: nil, id_prefix: _id_prefix} = assigns),
    do: assigns

  defp process_input_id(%{uid: uid, id_prefix: id_prefix} = assigns),
    do: assign(assigns, :id, "f-#{uid}-#{id_prefix}-#{assigns.field}")

  defp process_input_id(assigns), do: assigns

  defp maybe_html_escape(nil), do: nil
  defp maybe_html_escape(value), do: html_escape(value)

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
      acc ++ List.wrap("#{form.name}[#{sf}]")
    end)
    |> Enum.join(",")
  end

  defp prepare_slug_for(form, slug_for) do
    "#{form.name}[#{slug_for}]"
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
      <Form.field_base
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
      </Form.field_base>
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
    <Form.field_base
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
    </Form.field_base>
    """
  end

  def text(assigns) do
    assigns = prepare_input_component(assigns)

    ~H"""
    <Form.field_base
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <.input
        type={:text}
        form={@form}
        field={@field}
        placeholder={@placeholder}
        disabled={@disabled}
        phx_debounce={@debounce}
        class={"text#{@monospace && " monospace" || ""}"} />
    </Form.field_base>
    """
  end

  def textarea(assigns) do
    assigns = prepare_input_component(assigns)

    assigns =
      assign(assigns,
        rows: assigns.opts[:rows] || 3
      )

    ~H"""
    <Form.field_base
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <.input type={:textarea}
        form={@form}
        field={@field}
        class="text"
        placeholder={@placeholder}
        rows={@rows}
        disabled={@disabled}
        phx_debounce={@debounce}
        id={make_uid(@form, @field, @uid)} />
    </Form.field_base>
    """
  end

  def toggle(assigns) do
    assigns =
      assigns
      |> prepare_input_component()
      |> assign_new(:inner_block, fn -> nil end)

    ~H"""
    <Form.field_base
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}
      left_justify_meta>
      <Form.label
        form={@form}
        field={@field}
        class={render_classes(["switch", small: @compact])}>
        <%= if @inner_block do %>
          <%= render_slot @inner_block %>
        <% else %>
          <.input type={:checkbox} form={@form} field={@field} />
        <% end %>
        <div class="slider round"></div>
      </Form.label>
    </Form.field_base>
    """
  end
end
