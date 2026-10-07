defmodule BrandoAdmin.Users.UserUpdatePasswordLive do
  @moduledoc false
  # The logged-in user changes their own password, giving the current one.
  # It is also where `reset_password_on_first_login` sends a user after their
  # first login, to replace the password they were given.
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias Brando.Users
  alias BrandoAdmin.Components.Auth
  alias BrandoAdmin.Components.Workspace

  on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, __MODULE__}})

  def render(assigns) do
    ~H"""
    <div class="admin-workspace password-workspace">
      <Workspace.header
        title={if @first_login?, do: gettext("Set your password"), else: gettext("Change password")}
        subtitle={@current_user.email}
        icon="key-round"
      />
      <section class="workspace-panel password-panel">
        <header class="workspace-panel-heading">
          <div>
            <h2>{gettext("New password")}</h2>
            <p>
              {if @first_login?,
                do: gettext("The administrator has set a mandatory password change on first login for this website."),
                else: gettext("Your other sessions are logged out when the password changes. This one stays logged in.")}
            </p>
          </div>
        </header>
        <.form for={@form} id="password_form" class="password-form" phx-change="validate" phx-submit="save">
          <div class="field-wrapper">
            <Auth.input
              field={@form[:current_password]}
              type="password"
              label={gettext("Current password")}
              autocomplete="current-password"
              required
            />
          </div>
          <div class="field-wrapper">
            <Auth.input
              field={@form[:password]}
              type="password"
              label={gettext("New password")}
              autocomplete="new-password"
              required
            />
          </div>
          <div class="field-wrapper">
            <Auth.input
              field={@form[:password_confirmation]}
              type="password"
              label={gettext("Confirm new password")}
              autocomplete="new-password"
              required
            />
          </div>
          <div class="password-actions">
            <button type="submit" class="workspace-button primary" phx-disable-with={gettext("Saving...")}>
              {gettext("Change password")}
            </button>
            <.link :if={!@first_login?} navigate={"/admin/users/update/#{@current_user.id}"} class="workspace-button quiet">
              {gettext("Cancel")}
            </.link>
          </div>
        </.form>
      </section>
      <p class="workspace-note password-note">
        {gettext("Forgot your current password? Log out and use “Forgot password?” on the login page.")}
      </p>
    </div>
    """
  end

  def mount(_params, session, socket) do
    user = socket.assigns.current_user

    {:ok,
     assign(socket,
       socket_connected: connected?(socket),
       # The session's token row id, not the token, so it stays out of state
       session_id: Users.token_id(session["user_token"]),
       first_login?: match?(%{reset_password_on_first_login: true}, user.config),
       form: to_form(Users.password_changeset(user), as: "user"),
       page_title: gettext("Change password")
     )}
  end

  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket.assigns.current_user
      |> Users.password_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    %{current_user: current_user, session_id: session_id} = socket.assigns
    # Fresh from the database: the password may have changed since mount.
    {:ok, user} = Users.get_user(current_user.id)

    case Users.update_user_password(user, params["current_password"], params, session_id) do
      {:ok, _user} ->
        send(self(), {:toast, gettext("Your password has been changed.")})
        {:noreply, push_navigate(socket, to: "/admin")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
    end
  end
end
