defmodule BrandoAdmin.UserForgotPasswordLive do
  @moduledoc false
  # Asks for a password reset link. The answer never says whether the email
  # belongs to an account: see `Brando.Users.request_password_reset/1`.
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Auth

  def render(assigns) do
    ~H"""
    <Auth.shell>
      <div :if={@sent} id="reset_password_sent" class="login-sent">
        <Auth.title subtitle={gettext("Check your email")} />
        <Auth.notice message={@sent} />
        <div class="login-actions">
          <.link navigate="/admin/login" class="login-link">{gettext("Back to login")}</.link>
        </div>
      </div>

      <.form :if={!@sent} for={@form} id="reset_password_form" phx-submit="send">
        <Auth.title subtitle={gettext("Forgot your password?")} />
        <Auth.notice kind={:error} message={@error_message} />
        <p class="login-intro">
          {gettext("Enter the email address you log in with, and we will send you a link to choose a new password.")}
        </p>

        <div class="field-wrapper">
          <Auth.input
            field={@form[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            data-testid="email"
            required
            autofocus
          />
        </div>

        <div class="login-actions">
          <button class="primary" phx-disable-with={gettext("Sending...")} data-testid="send-reset-link">
            {gettext("Send reset link")}
          </button>
          <.link navigate="/admin/login" class="login-link">{gettext("Back to login")}</.link>
        </div>
      </.form>
    </Auth.shell>
    """
  end

  def mount(_params, _session, socket) do
    Auth.put_locale()

    {:ok,
     assign(socket,
       form: to_form(%{"email" => ""}, as: "user"),
       sent: nil,
       error_message: Phoenix.Flash.get(socket.assigns.flash, :error),
       page_title: gettext("Forgot your password?")
     )}
  end

  def handle_event("send", %{"user" => %{"email" => email}}, socket) when is_binary(email) do
    case Brando.Users.request_password_reset(email) do
      :ok ->
        minutes = Brando.Users.UserToken.reset_password_validity_in_minutes()

        sent =
          gettext(
            "If %{email} belongs to an account, we have sent it a link to choose a new password. The link works once, for %{minutes} minutes.",
            email: String.slice(String.trim(email), 0, 160),
            minutes: minutes
          )

        {:noreply, assign(socket, sent: sent, error_message: nil)}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           error_message: gettext("This site cannot send email right now. Ask an administrator to reset your password.")
         )}
    end
  end

  def handle_event("send", _params, socket), do: {:noreply, socket}
end
