defmodule Brando.HTML.Forms do
  @moduledoc """
  Renders a `Brando.Forms.Form` for visitors.

  Without slots it renders the whole form: fields grouped by section, each
  with its label, required marker, help text and errors, linked for screen
  readers. Only structural classes and data attributes are emitted; the site
  styles them.

      <Brando.HTML.Forms.site_form form={@form} />

  ## Layout

  Each field carries `data-width` (`full`, `half`, `third` or `fourth` of a
  12-unit row) and `data-new-row` where the editor started a new row, so a
  grid lays it out as built in the admin:

      .site-form-fields { display: grid; grid-template-columns: repeat(12, 1fr); gap: 1rem; }
      .site-form-field { grid-column: span 12; }
      .site-form-field[data-width="half"] { grid-column: span 6; }
      .site-form-field[data-width="third"] { grid-column: span 4; }
      .site-form-field[data-width="fourth"] { grid-column: span 3; }
      .site-form-field[data-new-row] { grid-column-start: 1; }

  ## Changing the markup

  `classes` adds classes to the parts — `form`, `section`, `legend`, `fields`,
  `field`, `label`, `input`, `help`, `error` and `submit` — for a site that
  only needs its own styling.

  A `:field` slot replaces the markup of a field. Filter it with `key` or
  `type` to replace one field, or one kind of field, and leave the rest as
  they are. The slot receives the field, its input name, id, value and
  errors; `default_field/1` renders the built-in markup, so a slot can wrap it
  rather than replace it:

      <Brando.HTML.Forms.site_form form={@form}>
        <:field :let={f} key="email">
          <div class="email-row">
            <Brando.HTML.Forms.default_field {f} />
            <small>We never share it.</small>
          </div>
        </:field>
        <:field :let={f} type="consent">
          <label class="consent">
            <input type="checkbox" name={f.name} value="true" required />
            I accept the <a href="/privacy">privacy policy</a>
          </label>
        </:field>
        <:submit>Send it</:submit>
      </Brando.HTML.Forms.site_form>

  `:section` replaces a section's heading, `:intro` the text above the
  fields and `:submit` the button's content. `only` and `except` take field
  keys, to render part of a form.

  ## Inputs

  Values are posted as `fields[<key>]` (`fields[<key>][]` for checkboxes).
  `values` and `errors`, keyed by field key, fill the form in again after a
  failed submission.

  ## Submitting

  By default the form posts to Brando's submission route for the current site
  (`Brando.Forms.Delivery`) with the visitor's CSRF token, a honeypot field and,
  when configured, the Turnstile widget (`Brando.Forms.Turnstile`). A small
  inline script submits it with `fetch` and shows errors and the success
  message in place; `enhance={false}` leaves it out, and `nonce` sets a CSP
  nonce on it. `:success` and `:failure` replace the two messages.
  """
  use Phoenix.Component
  use Gettext, backend: Brando.Gettext

  alias Brando.Forms.Field

  @parts ~w(form section legend fields field label input help error submit)a

  attr :form, :any, required: true, doc: "a `Brando.Forms.Form` with its fields loaded"
  attr :id, :string, default: nil, doc: "the form element's id; defaults to `form-<key>`"
  attr :action, :string, default: nil, doc: "where the form posts; defaults to Brando's submission route"

  attr :csrf_token, :any,
    default: :auto,
    doc: "the CSRF token to carry; `:auto` takes the current one, `false` carries none"

  attr :enhance, :boolean,
    default: true,
    doc: "submits with `fetch` and shows errors and the success message in place"

  attr :nonce, :string, default: nil, doc: "a CSP nonce for the inline script and style"
  attr :method, :string, default: "post"
  attr :preview, :boolean, default: false, doc: "renders disabled inputs that cannot be submitted"
  attr :only, :list, default: nil, doc: "field keys to render; the rest are left out"
  attr :except, :list, default: [], doc: "field keys to leave out"
  attr :values, :map, default: %{}, doc: "submitted values by field key"
  attr :errors, :map, default: %{}, doc: "error messages by field key"
  attr :classes, :map, default: %{}, doc: "extra classes by part: #{Enum.join(@parts, ", ")}"
  attr :rest, :global

  slot :intro, doc: "replaces the form's introduction"
  slot :submit, doc: "replaces the submit button's content"
  slot :success, doc: "replaces the message shown once the form has been sent"
  slot :failure, doc: "replaces the message shown when sending failed"

  slot :section, doc: "replaces a section's heading; receives the section field" do
    attr :key, :string
  end

  slot :field, doc: "replaces a field's markup; receives the field assigns" do
    attr :key, :string
    attr :type, :string
  end

  def site_form(assigns) do
    form = assigns.form
    id = assigns.id || "form-#{form.key}"

    assigns =
      assigns
      |> assign(:dom_id, id)
      |> assign(:groups, groups(form, assigns.only, assigns.except))
      |> assign(:hidden_fields, hidden_fields(form, assigns.only, assigns.except))
      |> assign(:token, token(assigns))
      |> then(&assign(&1, :root_attrs, root_attrs(&1)))
      |> assign(:turnstile_key, !assigns.preview && Brando.Forms.Turnstile.site_key())

    # A preview is shown inside another form (the admin's), where a nested
    # <form> would be dropped by the HTML parser.
    ~H"""
    <.dynamic_tag
      tag_name={if @preview, do: "div", else: "form"}
      id={@dom_id}
      class={["site-form", @classes[:form]]}
      data-form-key={@form.key}
      {@root_attrs}
    >
      <div :if={@intro != [] or present?(@form.intro)} class="site-form-intro">
        <%= if @intro != [] do %>
          {render_slot(@intro)}
        <% else %>
          <p>{@form.intro}</p>
        <% end %>
      </div>

      <fieldset :for={group <- @groups} class={["site-form-section", @classes[:section]]} disabled={@preview}>
        <%= if group.section do %>
          <%= if slot = find_section_slot(@section, group.section) do %>
            {render_slot(slot, group.section)}
          <% else %>
            <legend :if={present?(group.section.label)} class={["site-form-legend", @classes[:legend]]}>
              {group.section.label}
            </legend>
            <p :if={present?(group.section.help_text)} class="site-form-section-description">
              {group.section.help_text}
            </p>
          <% end %>
        <% end %>

        <div class={["site-form-fields", @classes[:fields]]}>
          <%= for field <- group.fields do %>
            <% field_assigns = field_assigns(field, @dom_id, @values, @errors, @classes) %>
            <%= if slot = find_field_slot(@field, field) do %>
              {render_slot(slot, field_assigns)}
            <% else %>
              <.default_field {field_assigns} />
            <% end %>
          <% end %>
        </div>
      </fieldset>

      <input
        :for={field <- @hidden_fields}
        type="hidden"
        name={input_name(field)}
        value={Map.get(@values, field.key, field.default_value)}
        disabled={@preview}
      />

      <%= unless @preview do %>
        <input :if={@token} type="hidden" name="_csrf_token" value={@token} />
        <input type="hidden" name="_language" value={@form.language} />
        <input type="hidden" name="_form_id" value={@dom_id} />
        <%!-- Left empty by people, who never see it; filled in by bots that
              fill in every field. --%>
        <div
          class="site-form-hp"
          aria-hidden="true"
          style="position:absolute;left:-10000px;top:auto;width:1px;height:1px;overflow:hidden"
        >
          <label>{field_hint(@form)} <input type="text" name="_hp" value="" tabindex="-1" autocomplete="off" /></label>
        </div>
        <div :if={@turnstile_key} class="cf-turnstile" data-sitekey={@turnstile_key} data-language={@form.language}></div>
      <% end %>

      <div class="site-form-actions">
        <button type="submit" class={["site-form-submit", @classes[:submit]]} disabled={@preview}>
          <%= if @submit != [] do %>
            {render_slot(@submit)}
          <% else %>
            {submit_label(@form)}
          <% end %>
        </button>
      </div>

      <%= unless @preview do %>
        <div id={"#{@dom_id}-sent"} class="site-form-status site-form-sent" role="status" tabindex="-1">
          <%= if @success != [] do %>
            {render_slot(@success)}
          <% else %>
            <p>{Brando.Forms.success_message(@form)}</p>
          <% end %>
        </div>
        <div id={"#{@dom_id}-failed"} class="site-form-status site-form-failed" role="alert" tabindex="-1">
          <%= if @failure != [] do %>
            {render_slot(@failure)}
          <% else %>
            <p>{failure_message(@form)}</p>
          <% end %>
        </div>
      <% end %>
    </.dynamic_tag>
    <script
      :if={@turnstile_key}
      src="https://challenges.cloudflare.com/turnstile/v0/api.js"
      async
      defer
      nonce={@nonce}
    >
    </script>
    <.enhancement :if={!@preview} enhance={@enhance} nonce={@nonce} />
    """
  end

  # Submits with `fetch` and shows the outcome in place: the success message,
  # or each field's errors. It asks for JSON but still accepts HTML, since an
  # application's browser pipeline usually only accepts HTML (`plug :accepts`).
  # Each form reads its own reply, so one copy per
  # page is enough; later copies return at once.
  @enhancement_script """
  (function () {
    if (window.__brandoSiteForms) return; window.__brandoSiteForms = true;
    var show = function (form, outcome) {
      var el = document.getElementById(form.id + '-' + outcome);
      if (el) { el.classList.add('is-shown'); el.focus(); }
    };
    document.addEventListener('submit', function (event) {
      var form = event.target;
      if (!form.matches || !form.matches('form[data-site-form]')) return;
      event.preventDefault();
      var button = form.querySelector('[type=submit]');
      if (button) button.disabled = true;
      form.classList.add('is-sending');
      ['sent', 'failed'].forEach(function (o) { var el = document.getElementById(form.id + '-' + o); if (el) el.classList.remove('is-shown'); });
      form.querySelectorAll('[data-site-form-error]').forEach(function (el) { el.remove(); });
      form.querySelectorAll('[aria-invalid]').forEach(function (el) { el.removeAttribute('aria-invalid'); });
      // A page served from a cache carries the token it was cached with; send the visitor's own.
      var token = form.querySelector('input[name="_csrf_token"]');
      var tokenPath = form.getAttribute('data-site-form-token');
      var accept = { Accept: 'application/json, text/html;q=0.1' };
      var refreshed = token && tokenPath
        ? fetch(tokenPath, { headers: accept, credentials: 'same-origin', cache: 'no-store' })
            .then(function (response) { return response.ok ? response.json() : {}; })
            .then(function (body) { if (body.token) token.value = body.token; })
            .catch(function () {})
        : Promise.resolve();
      refreshed
        .then(function () { return fetch(form.action, { method: 'POST', body: new FormData(form), headers: accept, credentials: 'same-origin' }); })
        .then(function (response) { return response.json().catch(function () { return {}; }).then(function (body) { return { ok: response.ok, body: body }; }); })
        .then(function (result) {
          if (result.ok && result.body.ok) {
            form.classList.add('is-sent');
            form.querySelectorAll('.site-form-section, .site-form-actions, .site-form-intro').forEach(function (el) { el.hidden = true; });
            show(form, 'sent');
            return;
          }
          var errors = result.body.errors || {};
          var first = null;
          Object.keys(errors).forEach(function (key) {
            var wrapper = form.querySelector('.site-form-field[data-key="' + key + '"]');
            if (!wrapper) return;
            var input = wrapper.querySelector('input, select, textarea');
            if (input) { input.setAttribute('aria-invalid', 'true'); first = first || input; }
            var message = document.createElement('p');
            message.className = 'site-form-error';
            message.setAttribute('data-site-form-error', '');
            message.id = form.id + '-' + key + '-error';
            message.textContent = errors[key].join(' ');
            wrapper.appendChild(message);
            if (input) input.setAttribute('aria-describedby', ((input.getAttribute('aria-describedby') || '') + ' ' + message.id).trim());
          });
          if (first) { first.focus(); } else {
            var failed = document.getElementById(form.id + '-failed');
            if (failed && result.body.message) failed.textContent = result.body.message;
            show(form, 'failed');
          }
        })
        .catch(function () { show(form, 'failed'); })
        .then(function () {
          form.classList.remove('is-sending');
          if (button) button.disabled = false;
          if (window.turnstile) form.querySelectorAll('.cf-turnstile').forEach(function (el) { window.turnstile.reset(el); });
        });
    });
  })();
  """

  attr :enhance, :boolean, required: true
  attr :nonce, :string, default: nil

  # Without the script, a plain post lands back on the page at the
  # `#<id>-sent` or `#<id>-failed` anchor, and `:target` reveals the message.
  defp enhancement(assigns) do
    assigns = assign(assigns, :script, @enhancement_script)

    ~H"""
    <style nonce={@nonce}>
      .site-form-status:not(:target):not(.is-shown) { display: none; }
    </style>
    <%!-- HEEx does not interpolate `{…}` inside <script>; EEx tags it does. --%>
    <script :if={@enhance} nonce={@nonce}>
      <%= Phoenix.HTML.raw(@script) %>
    </script>
    """
  end

  attr :field, :any, required: true
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :errors, :list, default: []
  attr :classes, :map, default: %{}

  @doc """
  The built-in markup of one field: its wrapper, label, input, help text
  and errors. Takes the assigns a `:field` slot receives.
  """
  def default_field(assigns) do
    assigns =
      assigns
      |> assign(:help_id, "#{assigns.id}-help")
      |> assign(:error_id, "#{assigns.id}-error")
      |> assign(:required, assigns.field.required == true)
      |> assign(:width, assigns.field.width || :full)

    assigns = assign(assigns, :described_by, described_by(assigns))

    ~H"""
    <div
      class={["site-form-field", "site-form-field--#{@field.type}", @errors != [] && "has-error", @classes[:field]]}
      data-key={@field.key}
      data-width={@width}
      data-new-row={@field.new_row && "true"}
    >
      <.control
        field={@field}
        id={@id}
        name={@name}
        value={@value}
        required={@required}
        described_by={@described_by}
        invalid={@errors != []}
        classes={@classes}
      />
      <p
        :if={present?(@field.help_text) and @field.type != :consent}
        id={@help_id}
        class={["site-form-help", @classes[:help]]}
      >
        {@field.help_text}
      </p>
      <p :if={@errors != []} id={@error_id} class={["site-form-error", @classes[:error]]}>
        {Enum.join(@errors, " ")}
      </p>
    </div>
    """
  end

  attr :field, :any, required: true
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :any
  attr :required, :boolean
  attr :described_by, :string
  attr :invalid, :boolean
  attr :classes, :map

  defp control(%{field: %{type: :textarea}} = assigns) do
    ~H"""
    <.field_label field={@field} for={@id} required={@required} classes={@classes} />
    <textarea
      id={@id}
      name={@name}
      class={["site-form-input", @classes[:input]]}
      placeholder={@field.placeholder}
      required={@required}
      aria-describedby={@described_by}
      aria-invalid={@invalid && "true"}
      rows="5"
    >{@value}</textarea>
    """
  end

  defp control(%{field: %{type: :select}} = assigns) do
    ~H"""
    <.field_label field={@field} for={@id} required={@required} classes={@classes} />
    <select
      id={@id}
      name={@name}
      class={["site-form-input", @classes[:input]]}
      required={@required}
      aria-describedby={@described_by}
      aria-invalid={@invalid && "true"}
    >
      <option value="">{@field.placeholder}</option>
      <option :for={{value, label} <- Field.options(@field)} value={value} selected={to_string(@value) == value}>
        {label}
      </option>
    </select>
    """
  end

  defp control(%{field: %{type: type}} = assigns) when type in [:radio, :checkboxes] do
    assigns =
      assigns
      |> assign(:input_type, if(type == :radio, do: "radio", else: "checkbox"))
      |> assign(:selected, assigns.value |> List.wrap() |> Enum.map(&to_string/1))

    ~H"""
    <fieldset class="site-form-choices" aria-describedby={@described_by}>
      <legend class={["site-form-label", @classes[:label]]}>
        {@field.label}<.required_marker :if={@required} />
      </legend>
      <label :for={{{value, label}, index} <- Enum.with_index(Field.options(@field))} class="site-form-choice">
        <input
          type={@input_type}
          id={"#{@id}-#{index}"}
          name={@name}
          value={value}
          checked={value in @selected}
          required={@required and @input_type == "radio"}
        />
        <span>{label}</span>
      </label>
    </fieldset>
    """
  end

  defp control(%{field: %{type: type}} = assigns) when type in [:checkbox, :consent] do
    ~H"""
    <label class="site-form-choice" for={@id}>
      <input
        type="checkbox"
        id={@id}
        name={@name}
        value="true"
        checked={@value in [true, "true"]}
        required={@required}
        aria-describedby={@described_by}
        aria-invalid={@invalid && "true"}
      />
      <span>
        {@field.label}<.required_marker :if={@required} />
        <span :if={@field.type == :consent and present?(@field.help_text)} class="site-form-consent-text">
          {@field.help_text}
        </span>
      </span>
    </label>
    """
  end

  defp control(assigns) do
    assigns = assign(assigns, :input_type, input_type(assigns.field.type))

    ~H"""
    <.field_label field={@field} for={@id} required={@required} classes={@classes} />
    <input
      type={@input_type}
      id={@id}
      name={@name}
      value={@value}
      class={["site-form-input", @classes[:input]]}
      placeholder={@field.placeholder}
      required={@required}
      autocomplete={autocomplete(@field)}
      aria-describedby={@described_by}
      aria-invalid={@invalid && "true"}
    />
    """
  end

  attr :field, :any, required: true
  attr :for, :string, required: true
  attr :required, :boolean
  attr :classes, :map

  defp field_label(assigns) do
    ~H"""
    <label for={@for} class={["site-form-label", @classes[:label]]}>
      {@field.label}<.required_marker :if={@required} />
    </label>
    """
  end

  defp required_marker(assigns) do
    ~H"""
    <span class="site-form-required" aria-hidden="true">*</span>
    """
  end

  defp root_attrs(%{preview: true, rest: rest}), do: rest

  defp root_attrs(%{form: form, action: action, method: method, enhance: enhance, token: token, rest: rest}) do
    Map.merge(
      %{
        action: action || Brando.Forms.Delivery.action(form.key),
        method: method,
        "data-site-form": enhance,
        "data-site-form-token": token && Brando.Forms.Delivery.token_path()
      },
      rest
    )
  end

  defp token(%{preview: true}), do: nil
  defp token(%{csrf_token: :auto}), do: Brando.Forms.Delivery.csrf_token()
  defp token(%{csrf_token: token}) when is_binary(token), do: token
  defp token(_), do: nil

  defp failure_message(form), do: Brando.Forms.message(:failure_message, form.language)

  defp field_hint(form), do: in_language(form, fn -> gettext("Leave this field empty") end)

  defp in_language(%{language: language}, fun) when not is_nil(language),
    do: Gettext.with_locale(Brando.Gettext, to_string(language), fun)

  defp in_language(_form, fun), do: fun.()

  @doc """
  The fields of a form in sections, as rendered: `%{section: field | nil,
  fields: [field]}`. Hidden fields are left out; they render as hidden
  inputs.
  """
  def groups(form, only \\ nil, except \\ []) do
    form.fields
    |> visible(only, except)
    |> Enum.reject(&(&1.type == :hidden))
    |> Enum.chunk_while(
      %{section: nil, fields: []},
      fn
        %{type: :section} = section, group -> {:cont, finish(group), %{section: section, fields: []}}
        field, group -> {:cont, %{group | fields: group.fields ++ [field]}}
      end,
      fn group -> {:cont, finish(group), nil} end
    )
    |> Enum.reject(&is_nil/1)
  end

  # A leading group without a section exists only when it holds fields.
  defp finish(%{section: nil, fields: []}), do: nil
  defp finish(group), do: group

  defp hidden_fields(form, only, except), do: form.fields |> visible(only, except) |> Enum.filter(&(&1.type == :hidden))

  defp visible(fields, only, except) do
    fields
    |> loaded()
    |> Enum.filter(fn field ->
      field.type == :section or ((only == nil or field.key in only) and field.key not in except)
    end)
  end

  defp loaded(%Ecto.Association.NotLoaded{}), do: []
  defp loaded(fields), do: fields || []

  defp field_assigns(field, form_id, values, errors, classes) do
    %{
      field: field,
      id: "#{form_id}-#{field.key}",
      name: input_name(field),
      value: Map.get(values, field.key, field.default_value),
      errors: errors |> Map.get(field.key, []) |> List.wrap(),
      classes: classes
    }
  end

  @doc "The name a field's input is posted under."
  def input_name(%{type: :checkboxes, key: key}), do: "fields[#{key}][]"
  def input_name(%{key: key}), do: "fields[#{key}]"

  defp find_field_slot(slots, field) do
    Enum.find(slots, fn slot ->
      matches?(slot[:key], field.key) and matches?(slot[:type], field.type)
    end)
  end

  defp find_section_slot(slots, section), do: Enum.find(slots, &matches?(&1[:key], section.key))

  defp matches?(nil, _value), do: true
  defp matches?(filter, value), do: to_string(filter) == to_string(value)

  defp described_by(%{field: field, errors: errors, help_id: help_id, error_id: error_id}) do
    [present?(field.help_text) && field.type != :consent && help_id, errors != [] && error_id]
    |> Enum.filter(& &1)
    |> case do
      [] -> nil
      ids -> Enum.join(ids, " ")
    end
  end

  defp input_type(:email), do: "email"
  defp input_type(:tel), do: "tel"
  defp input_type(:number), do: "number"
  defp input_type(:date), do: "date"
  defp input_type(_), do: "text"

  defp autocomplete(%{type: :email}), do: "email"
  defp autocomplete(%{type: :tel}), do: "tel"
  defp autocomplete(%{key: key}) when key in ["name", "full_name"], do: "name"
  defp autocomplete(_), do: nil

  defp submit_label(%{submit_label: label}) when is_binary(label) and label != "", do: label
  # Rendered when an entry is saved, so the admin's locale is no guide: the
  # site's wording in the form's own language.
  defp submit_label(form), do: Brando.Forms.message(:submit_label, form.language)

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
