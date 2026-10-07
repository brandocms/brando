defmodule BrandoAdmin.UserTwoFactorSetupLive do
  @moduledoc false
  # On the way in, for a user whom the sign-in policy requires to use
  # two-factor authentication and who has not set it up: their password was
  # right, and they set it up here before they get a session. Once they have,
  # the sign-in waiting in their session is marked done, and Continue posts to
  # `BrandoAdmin.UserSessionController.complete_setup/2`, which logs them in.
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias Brando.Users
  alias Brando.Users.TwoFactor
  alias Brando.Users.UserToken
  alias BrandoAdmin.Components.Auth
  alias BrandoAdmin.Components.TwoFactor, as: TwoFactorComponents

  def render(assigns) do
    ~H"""
    <Auth.shell>
      <div id="two_factor_setup" class="login-two-factor-setup">
        <Auth.title subtitle={gettext("Set up two-factor authentication")} />
        <%= if @codes do %>
          <Auth.notice message={gettext("Two-factor authentication is on.")} />
          <TwoFactorComponents.recovery_codes :if={@codes != []} codes={@codes} />
          <.form for={%{}} id="two_factor_complete" action="/admin/login/two-factor/complete" class="login-actions">
            <button class="primary" data-testid="two-factor-continue">{gettext("I have saved my codes")}</button>
          </.form>
        <% else %>
          <p class="login-intro">
            {gettext(
              "This site requires two-factor authentication for %{email}. Choose how you will confirm it is you when you log in, as well as with your password.",
              email: @user.email
            )}
          </p>
          <nav class="pill-tabs login-setup-methods" aria-label={gettext("Two-factor authentication")}>
            <button
              type="button"
              phx-click="method"
              phx-value-method="passkey"
              aria-pressed={to_string(@method == :passkey)}
              data-testid="setup-method-passkey"
            >
              <.icon name="fingerprint-pattern" />{gettext("Passkey")}
            </button>
            <button
              type="button"
              phx-click="method"
              phx-value-method="app"
              aria-pressed={to_string(@method == :app)}
              data-testid="setup-method-app"
            >
              <.icon name="smartphone" />{gettext("Authenticator app")}
            </button>
          </nav>
          <div :if={@method == :passkey} class="login-setup-method">
            <p class="login-setup-method-intro">
              {gettext("Your fingerprint, face or screen lock, on this device or your phone. Nothing to type.")}
            </p>
            <.live_component
              module={TwoFactorComponents.PasskeySetup}
              id="passkey-setup"
              user={@user}
              keep_id={@token_id}
              proof={:signed_in_now}
              meta={@meta}
            />
          </div>
          <.live_component
            :if={@method == :app}
            module={TwoFactorComponents.Setup}
            id="two-factor-setup"
            user={@user}
            keep_id={@token_id}
            proof={{:signed_in_now, @token_id}}
            meta={@meta}
          />
          <div class="login-actions">
            <.link href="/admin/logout" class="login-link">{gettext("Back to login")}</.link>
          </div>
        <% end %>
      </div>
    </Auth.shell>
    """
  end

  def mount(_params, session, socket) do
    token = session["pending_login_token"]

    case Users.get_pending_login(token) do
      {user, :pending} ->
        Auth.put_locale(user.language)

        token_id = Users.token_id(token, "pending_2fa")

        if TwoFactor.enabled?(user) do
          {:ok, push_navigate(socket, to: "/admin/login/two-factor")}
        else
          {:ok,
           socket
           |> watch_pending_login(token_id)
           |> assign(
             user: user,
             token_id: token_id,
             codes: nil,
             method: :passkey,
             meta: Brando.Users.SecurityLog.socket_meta(socket),
             page_title: gettext("Set up two-factor authentication")
           )}
        end

      {user, :verified} ->
        # Set up already, waiting for Continue: a reload cannot show the
        # codes again, so it goes on in.
        Auth.put_locale(user.language)

        {:ok,
         assign(socket, user: user, token_id: nil, codes: [], meta: nil, page_title: gettext("Two-factor authentication"))}

      nil ->
        Auth.put_locale()

        {:ok,
         socket
         |> put_flash(:error, gettext("Your login took too long. Log in again."))
         |> push_navigate(to: "/admin/login")}
    end
  end

  # Only the waiting sign-in vouches for the user here, so the screen closes
  # when it ends: deleted by a password change or reset, or simply too old.
  # Every event checks it again, and so does whatever adds a factor.
  defp watch_pending_login(socket, token_id) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Brando.pubsub(), Users.pending_login_topic(token_id))
      Process.send_after(self(), :check_pending_login, UserToken.pending_validity_in_minutes() * 60_000)
    end

    attach_hook(socket, :pending_login, :handle_event, fn _event, _params, socket ->
      if pending?(socket), do: {:cont, socket}, else: {:halt, ended(socket)}
    end)
  end

  defp pending?(%{assigns: %{codes: codes}}) when is_list(codes), do: true
  defp pending?(socket), do: Users.pending_login_valid?(socket.assigns.token_id, socket.assigns.user)

  defp ended(socket) do
    socket
    |> put_flash(:error, gettext("Your login took too long. Log in again."))
    |> push_navigate(to: "/admin/login")
  end

  def handle_event("method", %{"method" => method}, socket) when method in ["passkey", "app"],
    do: {:noreply, assign(socket, :method, String.to_existing_atom(method))}

  def handle_info({:pending_login_ended, _id}, %{assigns: %{codes: nil}} = socket), do: {:noreply, ended(socket)}

  def handle_info(:check_pending_login, socket) do
    if pending?(socket), do: {:noreply, socket}, else: {:noreply, ended(socket)}
  end

  def handle_info({:passkey_added, _passkey, codes}, socket), do: handle_info({:two_factor_enabled, codes || []}, socket)

  def handle_info({:two_factor_enabled, codes}, socket) do
    case Users.verify_pending_login(socket.assigns.token_id) do
      :ok ->
        {:noreply, assign(socket, codes: codes)}

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Your login took too long. Log in again."))
         |> push_navigate(to: "/admin/login")}
    end
  end

  # Anything else, such as a test mailer's copy of an email sent from here
  def handle_info(_message, socket), do: {:noreply, socket}
end
