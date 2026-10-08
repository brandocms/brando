defmodule BrandoAdmin.Users.UserSecurityLive do
  @moduledoc false
  # The signed-in user's own sign-in security: passkeys, the authenticator
  # app and recovery codes, the password, sessions, and what has happened
  # lately. Turning the app off and making new recovery codes ask for the
  # password or a current code first (`Brando.Users.TwoFactor.confirm/3`);
  # setting the app up and adding or removing a passkey ask again when the
  # session has not confirmed lately (`BrandoAdmin.Reauth`).
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias Brando.Users
  alias Brando.Users.Passkeys
  alias Brando.Users.SecurityLog
  alias Brando.Users.TwoFactor
  alias BrandoAdmin.Components.Auth
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.TwoFactor, as: TwoFactorComponents
  alias BrandoAdmin.Components.Workspace
  alias BrandoAdmin.Toast

  on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, __MODULE__}})

  on_mount(
    {BrandoAdmin.Reauth,
     events: ~w(open_setup new_passkey remove_passkey revoke_session revoke_other_sessions revoke_connected_app)}
  )

  def render(assigns) do
    ~H"""
    <div class="admin-workspace security-workspace">
      <Workspace.header title={gettext("Security")} subtitle={@current_user.email} icon="shield" />

      <section class="workspace-panel security-panel" id="two-factor-panel">
        <header class="workspace-panel-heading">
          <div>
            <h2>{gettext("Two-factor authentication")}</h2>
            <p>{gettext("Confirm it is you with a passkey or a code from your phone, as well as your password.")}</p>
          </div>
          <span
            class={["workspace-badge", @enabled? && "positive"]}
            data-testid="two-factor-status"
            data-enabled={to_string(@enabled?)}
          >
            {if @enabled?, do: gettext("On"), else: gettext("Off")}
          </span>
        </header>
        <div class="security-row">
          <div class="security-row-text">
            <h3>{gettext("Passkeys")}</h3>
            <p>
              {gettext(
                "Your fingerprint, face or screen lock, on this device or your phone, or a security key. A passkey also logs you in without your password."
              )}
            </p>
          </div>
          <div class="security-row-actions">
            <button type="button" class="workspace-button" phx-click="new_passkey" data-testid="passkey-add">
              <.icon name="plus" />{gettext("Add a passkey")}
            </button>
          </div>
        </div>
        <ul :if={@passkeys != []} class="security-items security-passkeys" data-testid="passkeys">
          <li :for={passkey <- @passkeys} class="security-item" data-testid="passkey">
            <.icon name="fingerprint-pattern" class="security-item-icon" />
            <div class="security-item-text">
              <span class="security-item-title">{passkey.name}</span>
              <span class="security-item-meta">
                {gettext("Added %{date}", date: date(passkey.inserted_at))} · {if passkey.last_used_at,
                  do: gettext("last used %{date}", date: date(passkey.last_used_at)),
                  else: gettext("not used yet")}
              </span>
            </div>
            <button
              type="button"
              class="workspace-button quiet"
              phx-click="remove_passkey"
              phx-value-id={passkey.id}
              data-testid="passkey-remove"
              data-confirm-title={gettext("Remove the passkey %{name}?", name: passkey.name)}
              data-confirm={gettext("It no longer logs you in. Remove it from the device too, in its settings.")}
              data-confirm-ok={gettext("Remove passkey")}
              data-confirm-destructive
            >
              {gettext("Remove")}
            </button>
          </li>
        </ul>
        <%= if @security.totp_enabled_at do %>
          <div class="security-row">
            <div class="security-row-text">
              <h3>{gettext("Authenticator app")}</h3>
              <p>
                {gettext("Turned on %{date}.",
                  date: Brando.Utils.Datetime.format_datetime(@security.totp_enabled_at, "%-d %B %Y")
                )}
                {if @required? and @passkeys == [],
                  do: gettext("The sign-in policy of this site requires it for your account.")}
              </p>
            </div>
            <div class="security-row-actions">
              <button
                :if={!@required? or @passkeys != []}
                type="button"
                class="workspace-button destructive"
                phx-click="ask_confirm"
                phx-value-action="disable"
                data-testid="two-factor-disable"
              >
                {gettext("Turn off")}
              </button>
            </div>
          </div>
        <% else %>
          <div class="security-row">
            <div class="security-row-text">
              <h3>{gettext("Authenticator app")}</h3>
              <p>
                {gettext(
                  "Not set up. Someone who learns your password cannot log in without your phone once it is. Setting it up logs out your other sessions."
                )}
              </p>
            </div>
            <div class="security-row-actions">
              <button type="button" class="workspace-button" phx-click="open_setup" data-testid="two-factor-setup">
                {gettext("Set up")}
              </button>
            </div>
          </div>
        <% end %>
        <div :if={@enabled?} class="security-row">
          <div class="security-row-text">
            <h3>{gettext("Recovery codes")}</h3>
            <p data-testid="recovery-codes-left">
              {ngettext(
                "One unused code left. Each code signs you in once if you lose your phone.",
                "%{count} unused codes left. Each code signs you in once if you lose your phone.",
                @codes_left
              )}
            </p>
          </div>
          <div class="security-row-actions">
            <button
              type="button"
              class="workspace-button"
              phx-click="ask_confirm"
              phx-value-action="regenerate"
              data-testid="recovery-codes-regenerate"
            >
              {gettext("Create new codes")}
            </button>
          </div>
        </div>
      </section>

      <section class="workspace-panel security-panel">
        <header class="workspace-panel-heading security-panel-single">
          <div>
            <h2>{gettext("Password")}</h2>
            <p>{gettext("Changing your password asks for the current one, and logs out your other sessions.")}</p>
          </div>
          <.link navigate="/admin/users/password" class="workspace-button">
            <.icon name="key-round" />{gettext("Change password")}
          </.link>
        </header>
      </section>

      <section class="workspace-panel security-panel" id="sessions-panel">
        <header class="workspace-panel-heading">
          <div>
            <h2>{gettext("Sessions")}</h2>
            <p>{gettext("Where you are logged in. Logging out a session ends it at once.")}</p>
          </div>
          <button
            :if={length(@sessions) > 1}
            type="button"
            class="workspace-button"
            phx-click="revoke_other_sessions"
            data-testid="sessions-revoke-others"
            data-confirm-title={gettext("Log out your other sessions?")}
            data-confirm={gettext("Every other browser where you are logged in is logged out. This one stays logged in.")}
            data-confirm-ok={gettext("Log them out")}
          >
            {gettext("Log out other sessions")}
          </button>
        </header>
        <ul class="security-items security-sessions" data-testid="sessions">
          <li
            :for={session <- @sessions}
            class="security-item"
            data-testid="session"
            data-current={to_string(session.id == @session_id)}
          >
            <.icon
              name={if (session.user_agent || "") =~ ~r/iPhone|Android|iPad/, do: "smartphone", else: "monitor"}
              class="security-item-icon"
            />
            <div class="security-item-text">
              <span class="security-item-title">
                {if session.user_agent, do: TwoFactorComponents.browser(session.user_agent), else: gettext("Unknown browser")}
                <span :if={session.id == @session_id} class="workspace-badge positive">{gettext("This browser")}</span>
              </span>
              <span class="security-item-meta">
                {[
                  session.ip,
                  gettext("logged in %{date}", date: date(session.inserted_at)),
                  session.last_used_at && gettext("last active %{date}", date: date(session.last_used_at))
                ]
                |> Enum.filter(& &1)
                |> Enum.join(" · ")}
              </span>
            </div>
            <button
              :if={session.id != @session_id}
              type="button"
              class="workspace-button quiet"
              phx-click="revoke_session"
              phx-value-id={session.id}
              data-testid="session-revoke"
            >
              {gettext("Log out")}
            </button>
          </li>
        </ul>
      </section>

      <section :if={@mcp?} class="workspace-panel security-panel" id="connected-apps-panel" data-testid="connected-apps">
        <header class="workspace-panel-heading">
          <div>
            <h2>{gettext("Connected apps")}</h2>
            <p>
              {gettext(
                "AI tools you let read content and propose changes as you, over MCP. Disconnecting one stops it at once."
              )}
            </p>
          </div>
        </header>
        <p :if={@connected_apps == []} class="security-empty-row">{gettext("No apps are connected.")}</p>
        <ul :if={@connected_apps != []} class="security-items security-connected-apps" data-testid="connected-app-list">
          <li :for={grant <- @connected_apps} class="security-item" data-testid="connected-app" data-id={grant.id}>
            <.icon name="plug" class="security-item-icon" />
            <div class="security-item-text">
              <span class="security-item-title">
                {grant.client_name} <span class="workspace-badge">{URI.parse(grant.client_id).host}</span>
              </span>
              <span class="security-item-meta">
                {[
                  grant.site && "#{grant.site.name} · #{grant.environment.name}",
                  gettext("connected %{date}", date: date(grant.inserted_at)),
                  if(grant.last_used_at,
                    do: gettext("last used %{date}", date: date(grant.last_used_at)),
                    else: gettext("not used yet")
                  )
                ]
                |> Enum.filter(& &1)
                |> Enum.join(" · ")}
              </span>
            </div>
            <button
              type="button"
              class="workspace-button quiet"
              phx-click="revoke_connected_app"
              phx-value-id={grant.id}
              data-testid="connected-app-revoke"
              data-confirm-title={gettext("Disconnect %{client}?", client: grant.client_name)}
              data-confirm={gettext("It stops working at once. You can connect it again from the app.")}
              data-confirm-ok={gettext("Disconnect")}
              data-confirm-destructive
            >
              {gettext("Disconnect")}
            </button>
          </li>
        </ul>
      </section>

      <section class="workspace-panel security-panel">
        <header class="workspace-panel-heading">
          <div>
            <h2>{gettext("Recent activity")}</h2>
            <p>{gettext("Logins, failed attempts and changes to your sign-in settings.")}</p>
          </div>
        </header>
        <div class="security-events-wrapper">
          <TwoFactorComponents.events events={@events} />
        </div>
      </section>
    </div>

    <Content.modal
      :if={@modal == :setup}
      id="two-factor-setup-modal"
      title={gettext("Set up two-factor authentication")}
      icon="shield"
      show
      medium
      close={JS.push("close_modal")}
    >
      <.live_component
        module={TwoFactorComponents.Setup}
        id="two-factor-setup"
        user={@current_user}
        keep_id={@session_id}
        meta={@meta}
      />
    </Content.modal>

    <Content.modal
      :if={@modal == :add_passkey}
      id="passkey-add-modal"
      title={gettext("Add a passkey")}
      icon="fingerprint-pattern"
      show
      narrow
      close={JS.push("close_modal")}
    >
      <.live_component
        module={TwoFactorComponents.PasskeySetup}
        id="passkey-setup"
        user={@current_user}
        keep_id={@session_id}
        meta={@meta}
      />
    </Content.modal>

    <Content.modal
      :if={match?({:codes, _}, @modal)}
      id="recovery-codes-modal"
      title={gettext("Your recovery codes")}
      icon="key-round"
      show
      medium
      close={JS.push("close_modal")}
    >
      <TwoFactorComponents.recovery_codes codes={elem(@modal, 1)} />
      <:footer>
        <button type="button" class="primary" phx-click="close_modal" data-testid="recovery-codes-done">
          {gettext("I have saved my codes")}
        </button>
      </:footer>
    </Content.modal>

    <Content.modal
      :if={match?({:confirm, _}, @modal)}
      id="security-confirm-modal"
      title={confirm_title(elem(@modal, 1))}
      icon="lock"
      show
      narrow
      close={JS.push("close_modal")}
    >
      <p class="security-confirm-intro">{confirm_intro(elem(@modal, 1))}</p>
      <.form for={@confirm_form} id="security-confirm-form" class="security-confirm-form" phx-submit="confirm">
        <div class="field-wrapper">
          <Auth.input
            field={@confirm_form[:proof]}
            type="password"
            label={gettext("Password or code from your app")}
            autocomplete="current-password"
            data-testid="security-proof"
            required
            autofocus
          />
        </div>
        <p :if={@confirm_error} class="security-confirm-error" role="alert">{@confirm_error}</p>
      </.form>
      <:footer>
        <button type="button" class="secondary" phx-click="close_modal">{gettext("Cancel")}</button>
        <button
          type="submit"
          form="security-confirm-form"
          class={["primary", elem(@modal, 1) == :disable && "danger"]}
          phx-disable-with={gettext("Checking...")}
          data-testid="security-confirm"
        >
          {confirm_label(elem(@modal, 1))}
        </button>
      </:footer>
    </Content.modal>
    """
  end

  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(
       socket_connected: connected?(socket),
       session_id: Brando.Users.token_id(session["user_token"]),
       meta: Brando.Users.SecurityLog.socket_meta(socket),
       modal: nil,
       confirm_form: to_form(%{"proof" => ""}, as: "confirm"),
       confirm_error: nil,
       page_title: gettext("Security")
     )
     |> load_state()}
  end

  defp load_state(socket) do
    user = socket.assigns.current_user
    passkeys = Passkeys.list(user)
    security = TwoFactor.security(user)

    assign(socket,
      security: security,
      passkeys: passkeys,
      enabled?: !!security.totp_enabled_at or passkeys != [],
      sessions: Users.list_sessions(user),
      codes_left: TwoFactor.recovery_codes_left(user),
      required?: TwoFactor.required?(user),
      events: SecurityLog.list(user, 10),
      mcp?: Brando.MCP.mounted?(),
      connected_apps: Brando.MCP.list_user_grants(user)
    )
  end

  def handle_event("open_setup", _params, socket) do
    if socket.assigns.security.totp_enabled_at,
      do: {:noreply, socket},
      else: {:noreply, assign(socket, modal: :setup)}
  end

  def handle_event("new_passkey", _params, socket), do: {:noreply, assign(socket, modal: :add_passkey)}

  def handle_event("remove_passkey", %{"id" => id}, socket) do
    %{current_user: user, meta: meta} = socket.assigns

    case Passkeys.delete(user, id, meta: meta) do
      :ok ->
        Toast.send_to(user, gettext("The passkey was removed."))

      {:error, :required} ->
        Toast.send_to(
          user,
          gettext("The sign-in policy requires two-factor authentication: add another passkey or the app first."),
          %{level: :error, type: :notification}
        )

      {:error, _reason} ->
        :ok
    end

    {:noreply, load_state(socket)}
  end

  def handle_event("revoke_session", %{"id" => id}, socket) do
    _ = Users.revoke_session(socket.assigns.current_user, id, meta: socket.assigns.meta)
    {:noreply, load_state(socket)}
  end

  def handle_event("revoke_other_sessions", _params, socket) do
    %{current_user: user, session_id: session_id, meta: meta} = socket.assigns
    :ok = Users.log_out_everywhere(user, user, except_id: session_id, meta: meta)
    Toast.send_to(user, gettext("Your other sessions were logged out."))
    {:noreply, load_state(socket)}
  end

  def handle_event("revoke_connected_app", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Brando.MCP.revoke(id, user, "user") do
      :ok -> Toast.send_to(user, gettext("The app was disconnected."))
      {:error, _} -> :ok
    end

    {:noreply, load_state(socket)}
  end

  def handle_event("ask_confirm", %{"action" => action}, socket) when action in ["disable", "regenerate"] do
    {:noreply,
     assign(socket,
       modal: {:confirm, String.to_existing_atom(action)},
       confirm_form: to_form(%{"proof" => ""}, as: "confirm"),
       confirm_error: nil
     )}
  end

  def handle_event("confirm", %{"confirm" => %{"proof" => proof}}, %{assigns: %{modal: {:confirm, action}}} = socket) do
    %{current_user: user, meta: meta} = socket.assigns

    result =
      case action do
        :disable -> TwoFactor.disable(user, proof, meta: meta)
        :regenerate -> TwoFactor.regenerate_recovery_codes(user, proof, meta: meta)
      end

    case result do
      :ok ->
        Toast.send_to(user, gettext("Two-factor authentication is off."))
        {:noreply, socket |> assign(modal: nil) |> load_state()}

      {:ok, codes} ->
        {:noreply, socket |> assign(modal: {:codes, codes}) |> load_state()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(confirm_error: confirm_error(reason), confirm_form: to_form(%{"proof" => ""}, as: "confirm"))
         |> load_state()}
    end
  end

  def handle_event("confirm", _params, socket), do: {:noreply, socket}

  def handle_event("close_modal", _params, socket), do: {:noreply, socket |> assign(modal: nil) |> load_state()}

  def handle_info({:passkey_added, _passkey, nil}, socket) do
    Toast.send_to(socket.assigns.current_user, gettext("The passkey was added."))
    {:noreply, socket |> assign(modal: nil) |> load_state()}
  end

  def handle_info({:passkey_added, _passkey, codes}, socket) do
    Toast.send_to(socket.assigns.current_user, gettext("The passkey was added."))
    {:noreply, socket |> assign(modal: {:codes, codes}) |> load_state()}
  end

  def handle_info({:two_factor_enabled, codes}, socket) do
    Toast.send_to(socket.assigns.current_user, gettext("Two-factor authentication is on."))
    {:noreply, socket |> assign(modal: {:codes, codes}) |> load_state()}
  end

  # Anything else, such as a test mailer's copy of an email sent from here
  def handle_info(_message, socket), do: {:noreply, socket}

  defp date(datetime), do: Brando.Utils.Datetime.format_datetime(datetime, "%-d %B %Y")

  defp confirm_title(:disable), do: gettext("Turn off two-factor authentication?")
  defp confirm_title(:regenerate), do: gettext("Create new recovery codes?")

  defp confirm_intro(:disable),
    do: gettext("Your recovery codes stop working too. Enter your password or a code from your app to continue.")

  defp confirm_intro(:regenerate),
    do: gettext("Your current recovery codes stop working. Enter your password or a code from your app to continue.")

  defp confirm_label(:disable), do: gettext("Turn off")
  defp confirm_label(:regenerate), do: gettext("Create new codes")

  defp confirm_error(:invalid_proof), do: gettext("That is not your password or a current code.")

  defp confirm_error(:locked),
    do: gettext("Too many failed attempts. Your account is locked for a few minutes; try again later.")

  defp confirm_error(:unreadable),
    do: gettext("Codes from your app cannot be checked on this site right now. Use your password.")

  defp confirm_error(:required), do: gettext("The sign-in policy of this site requires two-factor authentication.")
  defp confirm_error(_), do: gettext("That did not work. Reload the page and try again.")
end
