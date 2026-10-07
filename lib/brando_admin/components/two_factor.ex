defmodule BrandoAdmin.Components.TwoFactor do
  @moduledoc false
  # Two-factor authentication on screen: setting it up (the `Setup` live
  # component, on the user's security page and on the way in when the sign-in
  # policy requires it), the recovery codes shown once, and the security log.
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  @doc """
  The recovery codes, shown once, with a download. `id` names the download's
  link for tests.
  """
  attr :codes, :list, required: true

  def recovery_codes(assigns) do
    assigns = assign(assigns, :download, "data:text/plain;charset=utf-8," <> URI.encode(download_text(assigns.codes)))

    ~H"""
    <div class="two-factor-codes" data-testid="recovery-codes">
      <p class="two-factor-codes-intro">
        {gettext(
          "Save these recovery codes somewhere safe, away from your phone, such as a password manager. Each one signs you in once if you lose your authenticator app. They are not shown again."
        )}
      </p>
      <ol class="two-factor-code-list">
        <li :for={code <- @codes}><code data-testid="recovery-code">{code}</code></li>
      </ol>
      <div class="two-factor-codes-actions">
        <a href={@download} download="recovery-codes.txt" class="workspace-button">
          <.icon name="download" />{gettext("Download codes")}
        </a>
      </div>
    </div>
    """
  end

  defp download_text(codes) do
    "#{Brando.config(:app_name)} — " <> gettext("Recovery codes") <> "\n\n" <> Enum.join(codes, "\n") <> "\n"
  end

  @doc "The latest security events of a user, as a list."
  attr :events, :list, required: true

  def events(assigns) do
    ~H"""
    <p :if={@events == []} class="security-empty">{gettext("Nothing recorded yet.")}</p>
    <ol :if={@events != []} class="security-events" data-testid="security-events">
      <li :for={event <- @events} class="security-event" data-action={event.action}>
        <span class={["security-event-dot", negative?(event.action) && "negative"]} aria-hidden="true"></span>
        <div class="security-event-text">
          <span class="security-event-title">{event_label(event)}</span>
          <span class="security-event-meta">
            {event_meta(event)}
          </span>
        </div>
        <time datetime={DateTime.to_iso8601(event.inserted_at)}>
          {Brando.Utils.Datetime.format_datetime(event.inserted_at, "%-d %B %Y, %H:%M")}
        </time>
      </li>
    </ol>
    """
  end

  defp negative?(action),
    do: action in [:login_failed, :locked, :two_factor_disabled, :two_factor_reset, :passkey_removed]

  @doc "What a security event says, in the admin's language."
  def event_label(%{action: :login, details: %{"method" => "totp"}}),
    do: gettext("Logged in with an authenticator code")

  def event_label(%{action: :login, details: %{"method" => "recovery_code"}}),
    do: gettext("Logged in with a recovery code")

  def event_label(%{action: :login, details: %{"method" => "two_factor_setup"}}),
    do: gettext("Logged in after setting up two-factor authentication")

  def event_label(%{action: :login, details: %{"method" => "passkey"}}), do: gettext("Logged in with a passkey")

  def event_label(%{action: :login}), do: gettext("Logged in")
  def event_label(%{action: :login_failed, details: %{"reason" => "two_factor"}}), do: gettext("Wrong two-factor code")

  def event_label(%{action: :login_failed, details: %{"reason" => "confirm"}}),
    do: gettext("Wrong password or code when confirming a change")

  def event_label(%{action: :login_failed}), do: gettext("Wrong password")
  def event_label(%{action: :locked}), do: gettext("Locked after too many failed attempts")
  def event_label(%{action: :two_factor_enabled}), do: gettext("Two-factor authentication turned on")
  def event_label(%{action: :two_factor_disabled}), do: gettext("Two-factor authentication turned off")
  def event_label(%{action: :two_factor_reset}), do: gettext("Two-factor authentication reset by an administrator")
  def event_label(%{action: :recovery_codes_created}), do: gettext("New recovery codes created")

  def event_label(%{action: :password_changed, details: %{"by" => "admin"}}),
    do: gettext("Password set by an administrator")

  def event_label(%{action: :password_changed, details: %{"by" => "reset_link"}}),
    do: gettext("Password reset by email link")

  def event_label(%{action: :password_changed}), do: gettext("Password changed")
  def event_label(%{action: :policy_changed}), do: gettext("Sign-in policy changed")

  def event_label(%{action: :passkey_added, details: %{"name" => name}}),
    do: gettext("Passkey added: %{name}", name: name)

  def event_label(%{action: :passkey_removed, details: %{"name" => name}}),
    do: gettext("Passkey removed: %{name}", name: name)

  def event_label(%{action: :session_revoked}), do: gettext("A session was logged out")
  def event_label(%{action: :sessions_revoked}), do: gettext("Logged out everywhere")
  def event_label(%{action: action}), do: to_string(action)

  defp event_meta(event) do
    [
      event.actor && event.actor_id != event.user_id && gettext("by %{name}", name: event.actor.name),
      event.ip,
      event.user_agent && browser(event.user_agent)
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  # First match wins: Edge and Chrome also say Safari, Edge also says Chrome.
  @browsers [{"Edg/", "Edge"}, {"Firefox/", "Firefox"}, {"Chrome/", "Chrome"}, {"Safari/", "Safari"}]
  @systems [
    {"iPhone", "iOS"},
    {"iPad", "iOS"},
    {"Android", "Android"},
    {"Mac OS X", "macOS"},
    {"Windows", "Windows"},
    {"Linux", "Linux"}
  ]

  @doc "A short name for the browser and system of a user agent string."
  def browser(user_agent) do
    case {match(user_agent, @browsers), match(user_agent, @systems)} do
      {nil, nil} -> String.slice(user_agent, 0, 40)
      {nil, system} -> system
      {browser, nil} -> browser
      {browser, system} -> gettext("%{browser} on %{system}", browser: browser, system: system)
    end
  end

  defp match(user_agent, names), do: Enum.find_value(names, fn {marker, name} -> user_agent =~ marker && name end)
end

defmodule BrandoAdmin.Components.TwoFactor.Setup do
  @moduledoc false
  # Sets up two-factor authentication for `user`: a new secret as a QR code
  # and as a key to type, then a code from the app to confirm it. On success
  # it tells its LiveView `{:two_factor_enabled, recovery_codes}`; the
  # LiveView shows them. The secret stays on the server until then.
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.Users.TwoFactor

  # `keep_id`: the token row (session, or waiting sign-in) to keep when the
  # user's other sessions are logged out. `proof`: `:password` asks for the
  # password with the code; `{:signed_in_now, pending_id}` is for the setup
  # screen of a sign-in whose password was right a moment ago, checked
  # against that sign-in on every attempt (`TwoFactor.enable/4`). `meta`: the request's IP
  # address and browser, for the log. The secret is kept wrapped
  # (`Brando.Redacted`), so it stays out of logged state.
  def update(assigns, socket) do
    socket = assign(socket, Map.take(assigns, [:id, :user, :keep_id, :meta]))

    {:ok,
     socket
     |> assign(:proof, Map.get(assigns, :proof, :password))
     |> assign_new(:secret, fn -> Brando.Redacted.wrap(TwoFactor.new_secret()) end)
     |> assign_new(:form, fn -> to_form(%{"code" => "", "proof" => ""}, as: "setup") end)
     |> assign_new(:error, fn -> nil end)}
  end

  defp qr_code(user, secret),
    do: Phoenix.HTML.raw(TwoFactor.qr_code_svg(TwoFactor.otpauth_uri(user, Brando.Redacted.value(secret))))

  defp display_secret(secret), do: TwoFactor.display_secret(Brando.Redacted.value(secret))

  def render(assigns) do
    ~H"""
    <div id={@id} class="two-factor-setup">
      <ol class="two-factor-steps">
        <li class="two-factor-step">
          <span class="two-factor-step-number" aria-hidden="true">1</span>
          <div class="two-factor-step-body">
            <h3>{gettext("Scan the QR code")}</h3>
            <p>
              {gettext("Use an authenticator app, such as 1Password, Google Authenticator or Microsoft Authenticator.")}
            </p>
            <figure class="two-factor-qr" role="img" aria-label={gettext("QR code for your authenticator app")}>
              {qr_code(@user, @secret)}
            </figure>
            <details class="two-factor-manual">
              <summary>{gettext("Can’t scan it? Enter a key instead")}</summary>
              <p>{gettext("Choose to enter a setup key in the app, and type:")}</p>
              <code class="two-factor-secret" data-testid="two-factor-secret">{display_secret(@secret)}</code>
            </details>
          </div>
        </li>
        <li class="two-factor-step">
          <span class="two-factor-step-number" aria-hidden="true">2</span>
          <div class="two-factor-step-body">
            <h3>{gettext("Enter the code from the app")}</h3>
            <.form for={@form} id={"#{@id}-form"} class="two-factor-confirm" phx-submit="confirm" phx-target={@myself}>
              <div class="field-wrapper">
                <BrandoAdmin.Components.Auth.input
                  field={@form[:code]}
                  label={gettext("6-digit code")}
                  autocomplete="one-time-code"
                  inputmode="numeric"
                  spellcheck="false"
                  data-testid="two-factor-setup-code"
                  required
                />
              </div>
              <div :if={@proof == :password} class="field-wrapper">
                <BrandoAdmin.Components.Auth.input
                  field={@form[:proof]}
                  type="password"
                  label={gettext("Your password")}
                  autocomplete="current-password"
                  data-testid="two-factor-setup-proof"
                  required
                />
              </div>
              <p :if={@error} class="two-factor-error" role="alert">{@error}</p>
              <div class="two-factor-confirm-actions">
                <button
                  type="submit"
                  class="workspace-button primary"
                  phx-disable-with={gettext("Checking...")}
                  data-testid="two-factor-enable"
                >
                  {gettext("Turn on two-factor authentication")}
                </button>
              </div>
            </.form>
          </div>
        </li>
      </ol>
    </div>
    """
  end

  def handle_event("confirm", %{"setup" => %{"code" => code} = params}, socket) do
    %{user: user, secret: secret} = socket.assigns
    proof = if socket.assigns.proof == :password, do: params["proof"], else: socket.assigns.proof
    opts = [proof: proof, keep_id: socket.assigns[:keep_id], meta: socket.assigns[:meta]]

    case TwoFactor.enable(user, Brando.Redacted.value(secret), code, opts) do
      {:ok, codes} ->
        send(self(), {:two_factor_enabled, codes})
        {:noreply, assign(socket, error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: error(reason), form: to_form(%{"code" => "", "proof" => ""}, as: "setup"))}
    end
  end

  defp error(:already_enabled), do: gettext("Two-factor authentication is already on for this account.")
  defp error(:invalid_proof), do: gettext("That is not your password.")

  defp error(:locked),
    do: gettext("Too many failed attempts. Your account is locked for a few minutes; try again later.")

  defp error(_invalid_code),
    do: gettext("That code did not match. Check that the app shows this account, and try the newest code.")
end

defmodule BrandoAdmin.Components.TwoFactor.PasskeySetup do
  @moduledoc false
  # Adds a passkey for `user`: a name for the device and, unless `proof` is
  # `:signed_in_now`, the user's password or a code from their app; then the
  # browser's own dialog (the `Brando.Passkey` hook). The registration — and
  # its challenge — stays in this component's assigns, hidden from inspection,
  # and answers once. On success it tells its LiveView
  # `{:passkey_added, passkey, recovery_codes}`; the codes are nil unless this
  # was the user's first second factor.
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.Users.Passkeys
  alias BrandoAdmin.Components.Auth
  alias BrandoAdmin.Components.TwoFactor

  def update(assigns, socket) do
    socket = assign(socket, Map.take(assigns, [:id, :user, :keep_id, :meta]))

    default_name =
      socket.assigns[:meta] && socket.assigns.meta[:user_agent] && TwoFactor.browser(socket.assigns.meta.user_agent)

    {:ok,
     socket
     |> assign(:proof, Map.get(assigns, :proof, :password))
     |> assign_new(:form, fn -> to_form(%{"name" => default_name || "", "proof" => ""}, id: assigns.id) end)
     |> assign_new(:error, fn -> nil end)
     |> assign_new(:registration, fn -> nil end)}
  end

  def render(assigns) do
    ~H"""
    <div class="passkey-setup">
      <.form
        for={@form}
        id={"#{@id}-form"}
        class="passkey-setup-form"
        phx-hook="Brando.Passkey"
        data-passkey="create"
        data-options-event="options"
        data-result-event="register"
        data-error-event="error"
      >
        <div class="field-wrapper">
          <Auth.input field={@form[:name]} label={gettext("Name this passkey")} data-testid="passkey-name" required />
        </div>
        <div :if={@proof == :password} class="field-wrapper">
          <Auth.input
            field={@form[:proof]}
            type="password"
            label={gettext("Password or code from your app")}
            autocomplete="current-password"
            data-testid="passkey-proof"
            required
          />
        </div>
        <p class="passkey-setup-hint">
          {gettext("Your browser asks where to keep it: this device, your phone, or a security key.")}
        </p>
        <p :if={@error} class="two-factor-error" role="alert" data-testid="passkey-error">{@error}</p>
        <div class="passkey-setup-actions">
          <button type="submit" class="workspace-button primary" data-testid="passkey-create">
            <.icon name="fingerprint-pattern" />{gettext("Create a passkey")}
          </button>
        </div>
      </.form>
    </div>
    """
  end

  def handle_event("options", params, socket) do
    %{user: user, meta: meta} = socket.assigns
    proof = if socket.assigns.proof == :signed_in_now, do: :signed_in_now, else: params["proof"]
    # Keeps the name the user typed when the form renders again; never the proof
    socket = assign(socket, :form, to_form(%{"name" => params["name"] || "", "proof" => ""}, id: socket.assigns.id))

    case Passkeys.start_registration(user, proof, meta: meta) do
      {:ok, registration, options} ->
        {:reply, %{publicKey: options}, assign(socket, registration: registration, error: nil)}

      {:error, reason} ->
        {:reply, %{}, assign(socket, registration: nil, error: proof_error(reason))}
    end
  end

  def handle_event("register", params, %{assigns: %{registration: %Passkeys.Registration{} = registration}} = socket) do
    %{user: user} = socket.assigns
    opts = [keep_id: socket.assigns[:keep_id], meta: socket.assigns[:meta]]

    case Passkeys.register(user, params["name"], params, registration, opts) do
      {:ok, passkey, codes} ->
        send(self(), {:passkey_added, passkey, codes})
        {:noreply, assign(socket, registration: nil)}

      {:error, :already_registered} ->
        {:noreply, assign(socket, registration: nil, error: gettext("This passkey is added already."))}

      {:error, _reason} ->
        {:noreply, assign(socket, registration: nil, error: gettext("The passkey could not be added. Try again."))}
    end
  end

  def handle_event("register", _params, socket), do: {:noreply, socket}

  def handle_event("error", _params, socket) do
    {:noreply,
     assign(socket,
       registration: nil,
       error: gettext("No passkey was made. The browser was closed, or this device cannot make one.")
     )}
  end

  defp proof_error(:locked),
    do: gettext("Too many failed attempts. Your account is locked for a few minutes; try again later.")

  defp proof_error(_reason), do: gettext("That is not your password or a current code.")
end
