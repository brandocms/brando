defmodule BrandoAdmin.UserTwoFactorLive do
  @moduledoc false
  # The second step of a sign-in: the password was right, and the user gives
  # a code from their authenticator app or a recovery code. The form posts to
  # `BrandoAdmin.UserSessionController.two_factor/2`, which checks it and
  # logs the user in; this screen only asks. It is in the user's own
  # language, since the password told us who they are.
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias Brando.Users
  alias BrandoAdmin.Components.Auth
  alias Phoenix.Flash

  def render(assigns) do
    ~H"""
    <Auth.shell>
      <.form for={@form} id="two_factor_form" action="/admin/login/two-factor" phx-update="ignore">
        <Auth.title subtitle={gettext("Two-factor authentication")} />
        <Auth.notice kind={:error} message={@error_message} />
        <p class="login-intro">
          {gettext("Open your authenticator app and enter the 6-digit code it shows for %{email}.", email: @email)}
        </p>

        <div class="field-wrapper">
          <Auth.input
            field={@form[:code]}
            label={gettext("Code")}
            autocomplete="one-time-code"
            inputmode="numeric"
            spellcheck="false"
            autocapitalize="off"
            data-testid="two-factor-code"
            required
            autofocus
          />
        </div>

        <details class="login-recovery">
          <summary>{gettext("Lost your phone?")}</summary>
          <p>
            {gettext(
              "Enter one of the recovery codes you saved when you set up two-factor authentication, in the field above. Each code works once. If you have none left, ask an administrator to reset two-factor authentication for you."
            )}
          </p>
        </details>

        <div class="login-actions">
          <button class="primary" phx-disable-with={gettext("Checking...")} data-testid="two-factor-submit">
            {gettext("Verify")}
          </button>
          <.link href="/admin/logout" class="login-link">{gettext("Back to login")}</.link>
        </div>
      </.form>
    </Auth.shell>
    """
  end

  def mount(_params, session, socket) do
    case Users.get_pending_login(session["pending_login_token"]) do
      {user, :pending} ->
        Auth.put_locale(user.language)

        {:ok,
         assign(socket,
           email: user.email,
           form: to_form(%{"code" => ""}, as: "two_factor"),
           error_message: Flash.get(socket.assigns.flash, :error),
           page_title: gettext("Two-factor authentication")
         )}

      {_user, :verified} ->
        {:ok, push_navigate(socket, to: "/admin/login/two-factor/setup")}

      nil ->
        Auth.put_locale()

        {:ok,
         socket
         |> put_flash(:error, gettext("Your login took too long. Log in again."))
         |> push_navigate(to: "/admin/login")}
    end
  end
end
