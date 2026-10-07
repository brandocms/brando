defmodule BrandoAdmin.UserResetPasswordLive do
  @moduledoc false
  # Where a password reset link leads: the user chooses a new password, which
  # logs them out everywhere and uses up the link.
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias Brando.Users
  alias BrandoAdmin.Components.Auth

  def render(assigns) do
    ~H"""
    <Auth.shell>
      <.form for={@form} id="new_password_form" phx-change="validate" phx-submit="save">
        <Auth.title subtitle={gettext("Choose a new password")} />
        <p class="login-intro">
          {gettext("Choose a new password for %{email}. You will be logged out everywhere, and can then log in with it.",
            email: @email
          )}
        </p>

        <div class="field-wrapper">
          <Auth.input
            field={@form[:password]}
            type="password"
            label={gettext("New password")}
            autocomplete="new-password"
            data-testid="password"
            required
            autofocus
          />
        </div>

        <div class="field-wrapper">
          <Auth.input
            field={@form[:password_confirmation]}
            type="password"
            label={gettext("Confirm new password")}
            autocomplete="new-password"
            data-testid="password-confirmation"
            required
          />
        </div>

        <div class="login-actions">
          <button class="primary" phx-disable-with={gettext("Saving...")} data-testid="save-password">
            {gettext("Set new password")}
          </button>
          <.link navigate="/admin/login" class="login-link">{gettext("Back to login")}</.link>
        </div>
      </.form>
    </Auth.shell>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    case Users.get_user_by_reset_password_token(token) do
      nil ->
        Auth.put_locale()
        {:ok, expired(socket)}

      user ->
        # In the user's own language, as the email that led here
        Auth.put_locale(user.language)

        {:ok,
         assign(socket,
           token: token,
           email: user.email,
           form: to_form(Users.password_changeset(user), as: "user"),
           page_title: gettext("Choose a new password")
         )}
    end
  end

  def handle_event("validate", %{"user" => params}, socket) do
    with_user(socket, fn user ->
      changeset = user |> Users.password_changeset(params) |> Map.put(:action, :validate)
      {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
    end)
  end

  def handle_event("save", %{"user" => params}, socket) do
    with_user(socket, fn user ->
      case Users.reset_user_password(user, params) do
        {:ok, _user} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Your password has been changed. Log in with your new password."))
           |> push_navigate(to: "/admin/login")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
      end
    end)
  end

  # The link is checked again on every event: it stops working the moment it
  # is used, or when the password is changed some other way.
  defp with_user(socket, fun) do
    case Users.get_user_by_reset_password_token(socket.assigns.token) do
      nil -> {:noreply, expired(socket)}
      user -> fun.(user)
    end
  end

  defp expired(socket) do
    socket
    |> put_flash(:error, gettext("This password reset link is invalid or has expired. Ask for a new one below."))
    |> push_navigate(to: "/admin/reset-password")
  end
end
