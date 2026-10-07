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
              "This site requires two-factor authentication for %{email}. When you log in, you will give a code from an app on your phone as well as your password.",
              email: @user.email
            )}
          </p>
          <.live_component
            module={TwoFactorComponents.Setup}
            id="two-factor-setup"
            user={@user}
            keep_token={@token}
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

        if TwoFactor.enabled?(user) do
          {:ok, push_navigate(socket, to: "/admin/login/two-factor")}
        else
          {:ok,
           assign(socket,
             user: user,
             token: token,
             codes: nil,
             meta: if(connected?(socket), do: Brando.Users.SecurityLog.meta(connect_info(socket))),
             page_title: gettext("Set up two-factor authentication")
           )}
        end

      {user, :verified} ->
        # Set up already, waiting for Continue: a reload cannot show the
        # codes again, so it goes on in.
        Auth.put_locale(user.language)

        {:ok,
         assign(socket, user: user, token: token, codes: [], meta: nil, page_title: gettext("Two-factor authentication"))}

      nil ->
        Auth.put_locale()

        {:ok,
         socket
         |> put_flash(:error, gettext("Your login took too long. Log in again."))
         |> push_navigate(to: "/admin/login")}
    end
  end

  def handle_info({:two_factor_enabled, codes}, socket) do
    case Users.verify_pending_login(socket.assigns.token) do
      :ok ->
        {:noreply, assign(socket, codes: codes)}

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Your login took too long. Log in again."))
         |> push_navigate(to: "/admin/login")}
    end
  end

  defp connect_info(socket) do
    %{peer_data: get_connect_info(socket, :peer_data), user_agent: get_connect_info(socket, :user_agent)}
  end
end
