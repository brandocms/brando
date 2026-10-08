defmodule BrandoAdmin.UserLogoutLive do
  @moduledoc false
  # `GET /admin/logout` only asks. Signing out changes state, so it takes a
  # DELETE with the CSRF token (`BrandoAdmin.UserSessionController.delete/2`):
  # a GET that logged out would let any page sign an admin out with an image.
  # Links in applications that still point here keep working, one click
  # later. Brando's own sign-out buttons send the DELETE themselves.
  use Phoenix.LiveView, layout: {BrandoAdmin.Layouts, :live_child}
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Auth

  def render(assigns) do
    ~H"""
    <Auth.shell>
      <div id="logout" class="login-logout">
        <Auth.title subtitle={gettext("Sign out?")} />
        <p class="login-intro">
          {gettext(
            "You are signed in as %{email}. Signing out ends your session in this browser; your other devices stay signed in.",
            email: @email
          )}
        </p>
        <.form for={%{}} id="logout_form" action="/admin/logout" method="delete" class="login-actions">
          <button type="submit" class="primary" data-testid="logout-confirm">{gettext("Sign out")}</button>
          <.link href="/admin" class="login-link" data-testid="logout-cancel">
            {gettext("Return to your workspace")}
          </.link>
        </.form>
      </div>
    </Auth.shell>
    """
  end

  def mount(_params, session, socket) do
    case email(socket.assigns.current_user, session) do
      nil -> {:ok, redirect(socket, to: "/admin/login")}
      email -> {:ok, assign(socket, email: email, page_title: gettext("Sign out?"))}
    end
  end

  # Signed in (`BrandoAdmin.UserAuth` has put the user's locale), or half
  # way: a sign-in waiting for its second step also ends here.
  defp email(%{email: email}, _session), do: email

  defp email(nil, session) do
    case Brando.Users.get_pending_login(session["pending_login_token"]) do
      {user, _state} ->
        Auth.put_locale(user.language)
        user.email

      nil ->
        nil
    end
  end
end
