defmodule BrandoAdmin.UserLoginLive do
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  def render(assigns) do
    ~H"""
    <div class="login" id="application-login">
      <div class="brando-versioning">
        <svg
          version="1.1"
          id="Layer_1"
          xmlns="http://www.w3.org/2000/svg"
          x="0"
          y="0"
          viewBox="0 0 560 559.4"
          xml:space="preserve"
        >
          <path
            d="M280 559.4C125.1 559.5-.9 433.5 0 277.7.9 123.9 126.3-1.6 282-.6c153.7 1 279.2 126.4 278 282.3-1.2 153.3-125.8 277.7-280 277.7zm74.6-289.8c1.2-.2 1.6-.3 2.1-.4l1.5-.3c13.6-2.8 25.7-8.7 35.7-18.4 14.3-13.9 20-31.1 18.5-50.8-1.7-22.7-13.2-38.3-34.3-47-12.6-5.2-25.8-7.3-39.3-7.3-40.8-.2-81.6-.1-122.5-.2-2.8 0-3.7.8-4.4 3.5-19.7 79.4-39.5 158.7-59.3 238.1-1.1 4.5-2.2 9-3.3 13.6h2.3c43.8 0 87.6.1 131.5 0 19.3-.1 38.1-2.8 56.3-9.5 14.8-5.5 28.2-13.2 38.6-25.4 13.2-15.4 18-33.5 15.8-53.5-1.5-13.3-7.4-24.4-18.1-32.7-6.1-4.6-13-7.6-21.1-9.7z"
            fill="#002992"
          /><path
            d="M354.6 269.6c8.1 2.1 15 5 21.1 9.8 10.7 8.3 16.7 19.4 18.1 32.7 2.2 19.9-2.6 38-15.8 53.5-10.4 12.2-23.8 19.9-38.6 25.4-18.2 6.7-37.1 9.4-56.3 9.5-43.8.1-87.6 0-131.5 0h-2.3c1.1-4.7 2.2-9.1 3.3-13.6 19.8-79.4 39.6-158.7 59.3-238.1.7-2.7 1.6-3.5 4.4-3.5 40.8.1 81.6 0 122.5.2 13.5.1 26.7 2.2 39.3 7.3 21.1 8.6 32.6 24.3 34.3 47 1.5 19.6-4.2 36.9-18.5 50.8-10 9.7-22.1 15.6-35.7 18.4l-1.5.3c-.5 0-.9.1-2.1.3zm-125.1 75.7c.6 0 .9.1 1.3.1 17.6 0 35.1.1 52.7 0 7.5 0 14.9-.9 22.1-3.4 13.1-4.6 19.9-14.5 19-27.7-.4-5.7-3.1-9.9-8.2-12.6-5.4-2.9-11.2-3.7-17.1-3.7-18.6-.1-37.1 0-55.7 0-.6 0-1.3.1-1.9.1-4.1 15.8-8.1 31.4-12.2 47.2zM266 200c-3.9 15.4-7.8 30.8-11.7 46.4 1 0 1.7.1 2.4.1 15.2 0 30.5 0 45.7-.1 8.5-.1 16.8-1 24.7-4.4 6.2-2.6 10.9-6.7 13.2-13.2 3.3-9.1 1.3-18.3-5.2-23.5-4.6-3.7-10.1-5.2-15.8-5.3-17.7-.1-35.3 0-53.3 0z"
            fill="#f9eee9"
          /><path
            d="M229.5 345.3c4.1-15.8 8.1-31.4 12.1-47.2.7-.1 1.3-.1 1.9-.1 18.6 0 37.1-.1 55.7 0 5.9 0 11.8.8 17.1 3.7 5 2.7 7.7 6.9 8.2 12.6 1 13.2-5.8 23.1-19 27.7-7.2 2.5-14.6 3.4-22.1 3.4-17.6.1-35.1 0-52.7 0-.2 0-.5-.1-1.2-.1z"
            fill="#012a92"
          /><path
            d="M266 200c18 0 35.7-.1 53.3.1 5.7.1 11.2 1.5 15.8 5.3 6.4 5.2 8.4 14.4 5.2 23.5-2.3 6.5-7 10.6-13.2 13.2-7.9 3.4-16.2 4.3-24.7 4.4-15.2.1-30.5.1-45.7.1-.7 0-1.5-.1-2.4-.1 3.9-15.7 7.8-31.1 11.7-46.5z"
            fill="#012992"
          />
        </svg>
        <div>Brando &copy;{NaiveDateTime.utc_now().year}</div>
      </div>
      <div class="login-container">
        <div class="login-box">
          <div class="figure-wrapper">
            <figure>
              <%= if Brando.config(:client_brand) do %>
                {Brando.config(:client_brand) |> raw}
              <% else %>
                <svg
                  version="1.1"
                  id="Layer_1"
                  xmlns="http://www.w3.org/2000/svg"
                  x="0"
                  y="0"
                  viewBox="0 0 560 559.4"
                  xml:space="preserve"
                >
                  <path
                    d="M280 559.4C125.1 559.5-.9 433.5 0 277.7.9 123.9 126.3-1.6 282-.6c153.7 1 279.2 126.4 278 282.3-1.2 153.3-125.8 277.7-280 277.7zm74.6-289.8c1.2-.2 1.6-.3 2.1-.4l1.5-.3c13.6-2.8 25.7-8.7 35.7-18.4 14.3-13.9 20-31.1 18.5-50.8-1.7-22.7-13.2-38.3-34.3-47-12.6-5.2-25.8-7.3-39.3-7.3-40.8-.2-81.6-.1-122.5-.2-2.8 0-3.7.8-4.4 3.5-19.7 79.4-39.5 158.7-59.3 238.1-1.1 4.5-2.2 9-3.3 13.6h2.3c43.8 0 87.6.1 131.5 0 19.3-.1 38.1-2.8 56.3-9.5 14.8-5.5 28.2-13.2 38.6-25.4 13.2-15.4 18-33.5 15.8-53.5-1.5-13.3-7.4-24.4-18.1-32.7-6.1-4.6-13-7.6-21.1-9.7z"
                    fill="#002992"
                  /><path
                    d="M354.6 269.6c8.1 2.1 15 5 21.1 9.8 10.7 8.3 16.7 19.4 18.1 32.7 2.2 19.9-2.6 38-15.8 53.5-10.4 12.2-23.8 19.9-38.6 25.4-18.2 6.7-37.1 9.4-56.3 9.5-43.8.1-87.6 0-131.5 0h-2.3c1.1-4.7 2.2-9.1 3.3-13.6 19.8-79.4 39.6-158.7 59.3-238.1.7-2.7 1.6-3.5 4.4-3.5 40.8.1 81.6 0 122.5.2 13.5.1 26.7 2.2 39.3 7.3 21.1 8.6 32.6 24.3 34.3 47 1.5 19.6-4.2 36.9-18.5 50.8-10 9.7-22.1 15.6-35.7 18.4l-1.5.3c-.5 0-.9.1-2.1.3zm-125.1 75.7c.6 0 .9.1 1.3.1 17.6 0 35.1.1 52.7 0 7.5 0 14.9-.9 22.1-3.4 13.1-4.6 19.9-14.5 19-27.7-.4-5.7-3.1-9.9-8.2-12.6-5.4-2.9-11.2-3.7-17.1-3.7-18.6-.1-37.1 0-55.7 0-.6 0-1.3.1-1.9.1-4.1 15.8-8.1 31.4-12.2 47.2zM266 200c-3.9 15.4-7.8 30.8-11.7 46.4 1 0 1.7.1 2.4.1 15.2 0 30.5 0 45.7-.1 8.5-.1 16.8-1 24.7-4.4 6.2-2.6 10.9-6.7 13.2-13.2 3.3-9.1 1.3-18.3-5.2-23.5-4.6-3.7-10.1-5.2-15.8-5.3-17.7-.1-35.3 0-53.3 0z"
                    fill="#f9eee9"
                  /><path
                    d="M229.5 345.3c4.1-15.8 8.1-31.4 12.1-47.2.7-.1 1.3-.1 1.9-.1 18.6 0 37.1-.1 55.7 0 5.9 0 11.8.8 17.1 3.7 5 2.7 7.7 6.9 8.2 12.6 1 13.2-5.8 23.1-19 27.7-7.2 2.5-14.6 3.4-22.1 3.4-17.6.1-35.1 0-52.7 0-.2 0-.5-.1-1.2-.1z"
                    fill="#012a92"
                  /><path
                    d="M266 200c18 0 35.7-.1 53.3.1 5.7.1 11.2 1.5 15.8 5.3 6.4 5.2 8.4 14.4 5.2 23.5-2.3 6.5-7 10.6-13.2 13.2-7.9 3.4-16.2 4.3-24.7 4.4-15.2.1-30.5.1-45.7.1-.7 0-1.5-.1-2.4-.1 3.9-15.7 7.8-31.1 11.7-46.5z"
                    fill="#012992"
                  />
                </svg>
              <% end %>
            </figure>
          </div>
          <div class="login-form">
            <.form for={@form} id="login_form" action={@create_action} phx-update="ignore" as={:user}>
              <div class="title">
                {Brando.config(:app_name)}
              </div>

              <%= if @error_message do %>
                <div class="alert alert-danger">
                  <p>{@error_message}</p>
                </div>
              <% end %>

              <div class="field-wrapper">
                <.input
                  field={@form[:email]}
                  type="email"
                  label={gettext("Email")}
                  class="text"
                  data-testid="email"
                  autofocus
                />
              </div>

              <div class="field-wrapper">
                <.input
                  field={@form[:password]}
                  label={gettext("Password")}
                  type="password"
                  class="text"
                  data-testid="password"
                />
              </div>

              <div class="field-wrapper">
                <div class="check-wrapper small">
                  <.input
                    field={@form[:remember_me]}
                    type="checkbox"
                    label={gettext("Keep me logged in for 60 days")}
                  />
                </div>
              </div>
              <div>
                <button
                  class="primary"
                  phx-disable-with={gettext("Logging in...")}
                  data-testid="login-button"
                >
                  {gettext("Log in")}
                </button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    error_message = Phoenix.Flash.get(socket.assigns.flash, :error)
    form = to_form(%{"email" => email}, as: "user")
    create_action = "/admin/login"

    {:ok, assign(socket, form: form, create_action: create_action, error_message: error_message),
     temporary_assigns: [form: form]}
  end

  attr :id, :any, default: nil
  attr :name, :any
  attr :class, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range radio search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  slot :inner_block

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div>
      <input type="hidden" name={@name} value="false" />
      <input type="checkbox" id={@id} name={@name} value="true" checked={@checked} {@rest} />
      <label class="control-label small" for={@id}>
        {@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={@class}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <div class="label-wrapper">
      <label class="control-label" for={@for}>
        {render_slot(@inner_block)}
      </label>
    </div>
    """
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(BrandoAdmin.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(BrandoAdmin.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p>
      <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
      {render_slot(@inner_block)}
    </p>
    """
  end
end
