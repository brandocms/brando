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
       ip: if(connected?(socket), do: Brando.Users.SecurityLog.meta(connect_info(socket)).ip),
       form: to_form(%{"email" => ""}, as: "user"),
       sent: nil,
       error_message: Phoenix.Flash.get(socket.assigns.flash, :error),
       page_title: gettext("Forgot your password?")
     )}
  end

  # Too many requests for one address get the same answer as one that went
  # out, so the limit tells nothing about the account; too many from one IP
  # address are told to wait.
  def handle_event("send", %{"user" => %{"email" => email}}, socket) when is_binary(email) do
    case Brando.Users.Throttle.check_reset(socket.assigns.ip, email) do
      :ok -> send_reset(socket, email, Brando.Users.request_password_reset(email))
      {:error, :account_limited, _retry_after} -> send_reset(socket, email, :ok)
      {:error, :ip_limited, _retry_after} -> {:noreply, assign(socket, error_message: too_many_requests())}
    end
  end

  def handle_event("send", _params, socket), do: {:noreply, socket}

  defp send_reset(socket, email, result) do
    case result do
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

  defp too_many_requests, do: gettext("Too many requests from your network. Try again in a few minutes.")

  # The socket's peer data, when the endpoint's socket gives it
  # (`connect_info: [:peer_data, ...]`); otherwise only the email is counted.
  defp connect_info(socket) do
    %{peer_data: get_connect_info(socket, :peer_data), user_agent: get_connect_info(socket, :user_agent)}
  end
end
