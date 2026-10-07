defmodule BrandoAdmin.Users.UserSecurityLive do
  @moduledoc false
  # The signed-in user's own sign-in security: two-factor authentication and
  # its recovery codes, the password, and what has happened lately. Turning
  # two-factor authentication off and making new recovery codes ask for the
  # password or a current code first (`Brando.Users.TwoFactor.confirm/3`).
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias Brando.Users.SecurityLog
  alias Brando.Users.TwoFactor
  alias BrandoAdmin.Components.Auth
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.TwoFactor, as: TwoFactorComponents
  alias BrandoAdmin.Components.Workspace
  alias BrandoAdmin.Toast

  on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, __MODULE__}})

  def render(assigns) do
    ~H"""
    <div class="admin-workspace security-workspace">
      <Workspace.header title={gettext("Security")} subtitle={@current_user.email} icon="shield" />

      <section class="workspace-panel security-panel" id="two-factor-panel">
        <header class="workspace-panel-heading">
          <div>
            <h2>{gettext("Two-factor authentication")}</h2>
            <p>{gettext("Log in with a code from an app on your phone as well as your password.")}</p>
          </div>
          <span
            class={["workspace-badge", @security.totp_enabled_at && "positive"]}
            data-testid="two-factor-status"
            data-enabled={to_string(!!@security.totp_enabled_at)}
          >
            {if @security.totp_enabled_at, do: gettext("On"), else: gettext("Off")}
          </span>
        </header>
        <%= if @security.totp_enabled_at do %>
          <div class="security-row">
            <div class="security-row-text">
              <h3>{gettext("Authenticator app")}</h3>
              <p>
                {gettext("Turned on %{date}.",
                  date: Brando.Utils.Datetime.format_datetime(@security.totp_enabled_at, "%-d %B %Y")
                )}
                {if @required?, do: gettext("The sign-in policy of this site requires it for your account.")}
              </p>
            </div>
            <div class="security-row-actions">
              <button
                :if={!@required?}
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
          <div class="security-row">
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
              <button type="button" class="workspace-button primary" phx-click="open_setup" data-testid="two-factor-setup">
                {gettext("Set up")}
              </button>
            </div>
          </div>
        <% end %>
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
        keep_token={@session_token}
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
       session_token: session["user_token"],
       meta: if(connected?(socket), do: SecurityLog.meta(connect_info(socket))),
       modal: nil,
       confirm_form: to_form(%{"proof" => ""}, as: "confirm"),
       confirm_error: nil,
       page_title: gettext("Security")
     )
     |> load_state()}
  end

  defp load_state(socket) do
    user = socket.assigns.current_user

    assign(socket,
      security: TwoFactor.security(user),
      codes_left: TwoFactor.recovery_codes_left(user),
      required?: TwoFactor.required?(user),
      events: SecurityLog.list(user, 10)
    )
  end

  defp connect_info(socket) do
    %{peer_data: get_connect_info(socket, :peer_data), user_agent: get_connect_info(socket, :user_agent)}
  end

  def handle_event("open_setup", _params, socket) do
    if socket.assigns.security.totp_enabled_at,
      do: {:noreply, socket},
      else: {:noreply, assign(socket, modal: :setup)}
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

  def handle_info({:two_factor_enabled, codes}, socket) do
    Toast.send_to(socket.assigns.current_user, gettext("Two-factor authentication is on."))
    {:noreply, socket |> assign(modal: {:codes, codes}) |> load_state()}
  end

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

  defp confirm_error(:required), do: gettext("The sign-in policy of this site requires two-factor authentication.")
  defp confirm_error(_), do: gettext("That did not work. Reload the page and try again.")
end
