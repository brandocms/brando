defmodule BrandoAdmin.Components.Form.Input do
  use BrandoAdmin, :component
  use BrandoAdmin.Translator, "forms"
  # use Phoenix.HTML

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
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}
    >
      <div class={["check-wrapper", @compact && "small"]}>
        <.input type={:checkbox} field={@field} />
        <Form.label
          field={@field}
          class={[
            "control-label",
            @compact && "small"
          ]}
        >
          <%= @text %>
        </Form.label>
      </div>
    </Form.field_base>
    """
  end

  def code(assigns) do
    assigns = prepare_input_component(assigns)

    ~H"""
    <Form.field_base
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}
    >
      <div id={"#{@field.id}-code"} class="code-editor" phx-hook="Brando.CodeEditor">
        <.input type={:textarea} field={@field} phx-debounce={750} />
        <div id={"#{@field.id}-code-editor"} phx-update="ignore">
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
        if assigns.palette_id not in [nil, ""] do
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
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}
    >
      <div
        id={"#{@field.id}-color-picker"}
        phx-hook="Brando.ColorPicker"
        data-input={"##{@field.id}"}
        data-color={@field.value || gettext("No color selected")}
        data-opacity={@opacity}
        data-picker={@picker}
        data-palette={@palette_colors}
      >
        <div class="picker">
          <.input type={:hidden} field={@field} />
          <div id={"#{@field.id}-color-picker-target"} phx-update="ignore" class="picker-target">
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
    assigns = prepare_input_component(assigns)

    assigns =
      assign(assigns,
        value: assigns.field.value || get_default(assigns.opts),
        locale: Gettext.get_locale()
      )

    ~H"""
    <Form.field_base
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}
    >
      <div
        id={"#{@field.id}-datepicker"}
        class="datetime-wrapper"
        phx-hook="Brando.DatePicker"
        data-locale={@locale}
      >
        <div id={"#{@field.id}-datepicker-flatpickr"} phx-update="ignore">
          <button type="button" class="clear-datetime">
            <%= gettext("Clear") %>
          </button>
          <.input type={:hidden} field={@field} value={@value} class="flatpickr" />
        </div>
      </div>
    </Form.field_base>
    """
  end

  def datetime(assigns) do
    assigns = prepare_input_component(assigns)

    assigns =
      assign(assigns,
        value: assigns.field.value || get_default(assigns.opts),
        class: assigns.opts[:class],
        locale: Gettext.get_locale()
      )

    ~H"""
    <Form.field_base
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}
    >
      <div
        id={"#{@field.id}-datetimepicker"}
        class="datetime-wrapper"
        phx-hook="Brando.DateTimePicker"
        data-locale={@locale}
      >
        <div id={"#{@field.id}-datetimepicker-flatpickr"} phx-update="ignore">
          <button type="button" class="clear-datetime">
            <%= gettext("Clear") %>
          </button>
          <.input type={:hidden} field={@field} value={@value} class="flatpickr" />
          <div class="timezone">&mdash; <%= gettext("Your timezone is") %>: <span>Unknown</span></div>
        </div>
      </div>
    </Form.field_base>
    """
  end

  def email(assigns) do
    assigns = prepare_input_component(assigns)

    ~H"""
    <Form.field_base
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}
    >
      <.input
        type={:email}
        field={@field}
        placeholder={@placeholder}
        disabled={@disabled}
        phx-debounce={@debounce}
        class={["text", @monospace && "monospace"]}
      />
    </Form.field_base>
    """
  end

  def number(assigns) do
    assigns = prepare_input_component(assigns)

    ~H"""
    <Form.field_base
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}
    >
      <.input
        type={:number}
        field={@field}
        placeholder={@placeholder}
        disabled={@disabled}
        phx-debounce={@debounce}
        class={["text", @monospace && "monospace"]}
      />
    </Form.field_base>
    """
  end

  def password(assigns) do
    value = assigns.field.value
    confirmation_field_atom = :"#{assigns.field.field}_confirmation"
    confirmation_field = assigns.field.form[confirmation_field_atom]
    confirmation_value = confirmation_field.value || value

    assigns =
      assigns
      |> prepare_input_component()
      |> assign(:value, value)
      |> assign(:confirmation, Keyword.get(assigns.opts, :confirmation))
      |> assign(:confirmation_field, Map.put(confirmation_field, :value, confirmation_value))
      |> assign(:confirmation_value, confirmation_value)

    ~H"""
    <Form.field_base
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}
    >
      <.input
        type={:password}
        field={@field}
        placeholder={@placeholder}
        disabled={@disabled}
        phx-debounce={@debounce}
        class={["text", @monospace && "monospace"]}
      />
    </Form.field_base>
    <%= if @confirmation do %>
      <Form.field_base
        field={@confirmation_field}
        label={"#{@label} [#{gettext("confirm")}]"}
        instructions={@instructions}
        class={@class}
        compact={@compact}
      >
        <.input
          type={:password}
          field={@confirmation_field}
          placeholder={@placeholder}
          disabled={@disabled}
          phx-debounce={@debounce}
          class={["text", @monospace && "monospace"]}
        />
      </Form.field_base>
    <% end %>
    """
  end

  def phone(assigns) do
    assigns = prepare_input_component(assigns)

    ~H"""
    <Form.field_base
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}
    >
      <.input
        type={:phone}
        field={@field}
        placeholder={@placeholder}
        disabled={@disabled}
        phx-debounce={@debounce}
        class={["text", @monospace && "monospace"]}
      />
    </Form.field_base>
    """
  end

  attr :id, :any, default: nil
  attr :opts, :any, default: []
  attr :label, :string
  attr :uid, :string
  attr :id_prefix, :string
  attr :field, Phoenix.HTML.FormField

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
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}
    >
      <div :if={@input_options != []} class="radios-wrapper">
        <div :for={opt <- @input_options} class="form-check">
          <.radio_opt id={@id} opt={opt} field={@field} />
        </div>
      </div>
    </Form.field_base>
    """
  end

  def radio_opt(assigns) do
    id =
      (assigns.id && assigns.id <> "-#{Brando.Utils.slugify(to_string(assigns.opt.value))}") ||
        assigns.field.id <> "-#{Brando.Utils.slugify(to_string(assigns.opt.value))}"

    label = g(assigns.field.form.source.data.__struct__, to_string(assigns.opt.label))

    assigns =
      assigns
      |> assign(:id, id)
      |> assign(:checked, to_string(assigns.opt.value) == to_string(assigns.field.value))
      |> assign(:label, label)

    ~H"""
    <label class="form-check-label">
      <input
        type="radio"
        id={@id}
        name={@field.name}
        class="form-check-input"
        value={@opt.value}
        checked={@checked}
      />
      <span class="label-text">
        <%= @label %>
      </span>
    </label>
    """
  end

  def rich_text(assigns) do
    assigns = prepare_input_component(assigns)

    ~H"""
    <Form.field_base
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}
    >
      <div class="tiptap-wrapper" id={"#{@field.id}-rich-text-wrapper"}>
        <div id={"#{@field.id}-rich-text"} phx-hook="Brando.TipTap" data-name="TipTap">
          <div
            id={"#{@field.id}-rich-text-target-wrapper"}
            class="tiptap-target-wrapper"
            phx-update="ignore"
          >
            <div id={"#{@field.id}-rich-text-target"} class="tiptap-target"></div>
          </div>
          <.input type={:hidden} field={@field} class="tiptap-text" phx-debounce={750} />
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
      |> assign_new(:data_slug_for, fn -> prepare_slug_for(assigns.field, assigns.opts[:for]) end)
      |> assign_new(:data_slug_type, fn ->
        (Keyword.get(assigns.opts, :camel_case) && "camel") || "standard"
      end)
      |> maybe_assign_url(assigns.opts[:show_url])

    ~H"""
    <Form.field_base
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}
    >
      <.input
        type={:text}
        field={@field}
        class="text monospace"
        phx-hook="Brando.Slug"
        phx-debounce={750}
        data-slug-for={@data_slug_for}
        data-slug-type={@data_slug_type}
        autocorrect="off"
        spellcheck="false"
      />
      <%= if @url do %>
        <div class="badge no-case no-border">
          <a href={@url} target="_blank">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12">
              <path fill="none" d="M0 0h24v24H0z" /><path d="M6.235 6.453a8 8 0 0 0 8.817 12.944c.115-.75-.137-1.47-.24-1.722-.23-.56-.988-1.517-2.253-2.844-.338-.355-.316-.628-.195-1.437l.013-.091c.082-.554.22-.882 2.085-1.178.948-.15 1.197.228 1.542.753l.116.172c.328.48.571.59.938.756.165.075.37.17.645.325.652.373.652.794.652 1.716v.105c0 .391-.038.735-.098 1.034a8.002 8.002 0 0 0-3.105-12.341c-.553.373-1.312.902-1.577 1.265-.135.185-.327 1.132-.95 1.21-.162.02-.381.006-.613-.009-.622-.04-1.472-.095-1.744.644-.173.468-.203 1.74.356 2.4.09.105.107.3.046.519-.08.287-.241.462-.292.498-.096-.056-.288-.279-.419-.43-.313-.365-.705-.82-1.211-.96-.184-.051-.386-.093-.583-.135-.549-.115-1.17-.246-1.315-.554-.106-.226-.105-.537-.105-.865 0-.417 0-.888-.204-1.345a1.276 1.276 0 0 0-.306-.43zM12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10z" />
            </svg>
          </a>
          <%= @url %>
        </div>
      <% end %>
    </Form.field_base>
    """
  end

  def hidden(assigns) do
    ~H"""
    <.input type={:hidden} field={@field} />
    """
  end

  attr :id, :any, default: nil
  attr :name, :any, default: nil
  attr :type, :atom, default: :text
  attr :value, :any
  attr :disabled, :boolean
  attr :label, :string
  attr :uid, :string
  attr :id_prefix, :string
  attr :publish, :boolean, default: false

  attr :rest, :global,
    include:
      ~w(class phx-hook phx-debounce rows phx-update data-slug-for data-slug-type data-autosize autocorrect spellcheck)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :hidden_input, :boolean, default: true

  def input(%{type: :checkbox} = assigns) do
    assigns =
      assigns
      |> assign_new(:value, fn -> nil end)
      |> assign_new(:checked_value, fn -> "true" end)
      |> assign_new(:unchecked_value, fn -> "false" end)
      |> process_input_id()

    assigns =
      assign(
        assigns,
        :checked,
        Phoenix.HTML.Form.normalize_value("checkbox", assigns.field.value)
      )

    if assigns.hidden_input do
      ~H"""
      <input type={:hidden} name={@field.name} id={"#{@id}-unchecked"} value={@unchecked_value} {@rest} />
      <input
        type={@type}
        name={@field.name}
        id={"#{@id}"}
        value={@checked_value}
        checked={@checked}
        {@rest}
      />
      """
    else
      ~H"""
      <input type={@type} name={@field.name} id={"#{@id}"} value={@checked_value} {@rest} />
      """
    end
  end

  def input(%{type: :textarea} = assigns) do
    assigns =
      if assigns[:value] do
        assigns
      else
        assign(
          assigns,
          :value,
          Phoenix.HTML.Form.normalize_value("textarea", assigns.field.value)
        )
      end

    assigns =
      assigns
      |> assign(:id, assigns.id || assigns.field.id)
      |> assign(:name, assigns.name || assigns.field.name)
      |> process_input_id()

    ~H"""
    <textarea type={@type} name={@name} id={@id} {@rest}><%= @value %></textarea>
    """
  end

  def input(assigns) do
    assigns =
      assign_new(
        assigns,
        :value,
        fn -> maybe_html_escape(assigns.field.value) end
      )

    assigns =
      assigns
      |> assign(:id, assigns.id || assigns.field.id)
      |> assign(:name, assigns.name || assigns.field.name)
      |> assign(:hook, (assigns.publish && "Brando.PublishInput") || nil)
      |> process_input_id()

    ~H"""
    <input type={@type} name={@name} id={@id} value={@value} phx-hook={@hook} {@rest} />
    """
  end

  defp process_input_id(%{uid: nil, id_prefix: _id_prefix} = assigns),
    do: assign(assigns, :id, assigns.field.id)

  defp process_input_id(%{uid: uid, id_prefix: id_prefix} = assigns),
    do: assign(assigns, :id, "f-#{uid}-#{id_prefix}-#{assigns.field.id}")

  defp process_input_id(%{id: nil} = assigns), do: assign(assigns, :id, assigns.field.id)
  defp process_input_id(%{id: ""} = assigns), do: assign(assigns, :id, assigns.field.id)
  defp process_input_id(%{id: id} = assigns), do: assign(assigns, :id, id)
  defp process_input_id(assigns), do: assign(assigns, :id, assigns.field.id)

  defp maybe_html_escape(nil), do: nil
  defp maybe_html_escape(true), do: "true"
  defp maybe_html_escape(false), do: "false"
  defp maybe_html_escape(value), do: value

  defp maybe_assign_url(assigns, true) do
    entry = Ecto.Changeset.apply_changes(assigns.field.form.source)
    schema = entry.__struct__
    url = schema.__absolute_url__(entry)
    assign(assigns, :url, url)
  end

  defp maybe_assign_url(assigns, _) do
    assigns
  end

  defp prepare_slug_for(%{form: form}, slug_for) when is_list(slug_for) do
    slug_for
    |> Enum.reduce([], fn sf, acc -> acc ++ List.wrap("#{form.name}[#{sf}]") end)
    |> Enum.join(",")
  end

  defp prepare_slug_for(_form, nil), do: false
  defp prepare_slug_for(%{form: form}, slug_for), do: "#{form.name}[#{slug_for}]"

  def status(assigns) do
    assigns =
      assigns
      |> prepare_input_component()
      |> assign_new(:id, fn -> nil end)
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
        field={@field}
        label={@label}
        instructions={@instructions}
        class={@class}
        compact={@compact}
      >
        <div class="radios-wrapper status">
          <div :for={status <- @statuses} class="form-check">
            <label class="form-check-label">
              <input
                type="radio"
                id={(@id || @field.id) <> "-#{status.value}"}
                name={@field.name}
                class="form-check-input"
                value={status.value}
                checked={status.value == to_string(@field.value)}
              />
              <span class={["label-text", status.value]}>
                <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 12 12">
                  <circle class={status.value} r="6" cy="6" cx="6" />
                </svg>
                <%= status.label %>
              </span>
            </label>
          </div>
        </div>
      </Form.field_base>
      """
    end
  end

  def status_compact(assigns) do
    assigns =
      assigns
      |> prepare_input_component()
      |> assign(:current_status, assigns.field.value)
      |> assign(
        :id,
        "status-dropdown-#{assigns.field.id}"
      )

    ~H"""
    <Form.field_base
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}
      fit_content
    >
      <div class="radios-wrapper status compact" phx-click={toggle_dropdown("##{@id}")}>
        <.status_circle status={@current_status} publish_at={nil} />
        <div class="status-dropdown hidden" id={@id}>
          <%= for status <- @statuses do %>
            <div class="form-check">
              <label class="form-check-label">
                <input
                  type="radio"
                  id={(@id || @field.id) <> "-#{status.value}"}
                  name={@field.name}
                  class="form-check-input"
                  value={status.value}
                  checked={status.value == to_string(@field.value)}
                />
                <span class={["label-text", status.value]}>
                  <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 12 12">
                    <circle class={status.value} r="6" cy="6" cx="6" />
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

  attr :field, Phoenix.HTML.FormField
  attr :label, :string
  attr :instructions, :string
  attr :class, :string
  attr :compact, :boolean
  attr :placeholder, :string
  attr :disabled, :boolean
  attr :debounce, :integer
  attr :monospace, :boolean
  attr :change, :any, default: nil

  def text(assigns) do
    assigns = prepare_input_component(assigns)

    ~H"""
    <Form.field_base
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}
    >
      <.input
        type={:text}
        field={@field}
        placeholder={@placeholder}
        disabled={@disabled}
        phx-debounce={@debounce}
        class={["text", @monospace && "monospace"]}
        phx-change={@change}
      />
    </Form.field_base>
    """
  end

  def textarea(assigns) do
    assigns = prepare_input_component(assigns)

    assigns =
      assigns
      |> assign(:rows, assigns.opts[:rows] || 3)
      |> assign(:generated_uid, make_uid(assigns.field, assigns.uid))
      |> assign(:monospace, assigns.opts[:monospace])

    ~H"""
    <Form.field_base
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}
    >
      <.input
        type={:textarea}
        field={@field}
        class={["text", @monospace && "monospace"]}
        placeholder={@placeholder}
        rows={@rows}
        disabled={@disabled}
        phx-debounce={@debounce}
        id={@generated_uid}
      />
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
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}
      left_justify_meta
    >
      <Form.label field={@field} class={["switch", @compact && "small"]}>
        <%= if @inner_block do %>
          <%= render_slot(@inner_block) %>
        <% else %>
          <.input type={:checkbox} field={@field} />
        <% end %>
        <div class="slider round"></div>
      </Form.label>
    </Form.field_base>
    """
  end
end
