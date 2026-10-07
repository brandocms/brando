defmodule BrandoAdmin.Users.UserFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Users.User
  use Gettext, backend: Brando.Gettext

  alias Brando.Users
  alias BrandoAdmin.Components.Auth
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Toast

  def mount(_params, _session, socket) do
    {:ok, assign(socket, set_password: nil, security_meta: Brando.Users.SecurityLog.socket_meta(socket))}
  end

  def render(assigns) do
    ~H"""
    <.live_component module={Form} id="user_form" entry_id={@entry_id} current_user={@current_user} schema={@schema}>
      <:header>
        <%= if @live_action == :create do %>
          {gettext("Create user")}
        <% else %>
          {gettext("Update user")}
        <% end %>
      </:header>
    </.live_component>

    <Content.modal
      :if={@set_password}
      id="user-set-password"
      title={gettext("Set a password")}
      subtitle={@set_password.email}
      icon="key-round"
      show
      narrow
      close={JS.push("close_set_password")}
    >
      <p class="user-set-password-intro">
        {gettext(
          "For when the user cannot get email from this site. They are logged out everywhere, and must choose their own password the next time they log in. Unsaved changes in the form are lost."
        )}
      </p>
      <.form
        for={@set_password.form}
        id="user-set-password-form"
        class="user-set-password-form"
        phx-change="validate_set_password"
        phx-submit="set_password"
      >
        <div class="field-wrapper">
          <Auth.input
            field={@set_password.form[:password]}
            type="password"
            label={gettext("New password")}
            autocomplete="new-password"
            required
          />
        </div>
        <div class="field-wrapper">
          <Auth.input
            field={@set_password.form[:password_confirmation]}
            type="password"
            label={gettext("Confirm new password")}
            autocomplete="new-password"
            required
          />
        </div>
      </.form>
      <:footer>
        <button type="button" class="secondary" phx-click="close_set_password">{gettext("Cancel")}</button>
        <button
          type="submit"
          form="user-set-password-form"
          class="primary"
          phx-disable-with={gettext("Saving...")}
          data-testid="set-password"
        >
          {gettext("Set password")}
        </button>
      </:footer>
    </Content.modal>
    """
  end

  # Brando.Users.send_password_reset/2 and set_user_password/3 decide who may.
  def handle_event("send_password_reset", _params, %{assigns: %{entry_id: entry_id}} = socket)
      when not is_nil(entry_id) do
    %{current_user: current_user} = socket.assigns

    case Users.send_password_reset(entry_id, current_user) do
      {:ok, user} ->
        Toast.send_to(current_user, gettext("A password reset link was sent to %{email}.", email: user.email))

      {:error, reason} ->
        Toast.send_to(current_user, reset_error(reason), %{level: :error, type: :notification})
    end

    {:noreply, socket}
  end

  def handle_event("send_password_reset", _params, socket), do: {:noreply, socket}

  # Brando.Users.TwoFactor.reset/3 decides who may.
  def handle_event("reset_two_factor", _params, %{assigns: %{entry_id: entry_id}} = socket)
      when not is_nil(entry_id) do
    %{current_user: current_user} = socket.assigns

    case Brando.Users.TwoFactor.reset(entry_id, current_user, meta: socket.assigns[:security_meta]) do
      {:ok, user} ->
        Toast.send_to(
          current_user,
          gettext("Two-factor authentication is off for %{email}. They were logged out everywhere.", email: user.email)
        )

        # Reloaded, so the form shows it off
        {:noreply, push_navigate(socket, to: "/admin/users/update/#{entry_id}")}

      {:error, _reason} ->
        Toast.send_to(
          current_user,
          gettext("Only a superuser can reset two-factor authentication for another user."),
          %{level: :error, type: :notification}
        )

        {:noreply, socket}
    end
  end

  def handle_event("reset_two_factor", _params, socket), do: {:noreply, socket}

  def handle_event("open_set_password", _params, %{assigns: %{entry_id: entry_id}} = socket)
      when not is_nil(entry_id) do
    {:ok, user} = Users.get_user(entry_id)

    if user.id != socket.assigns.current_user.id and
         Brando.Trait.ProtectPassword.allowed?(socket.assigns.current_user, user) do
      form = to_form(Users.password_changeset(user), as: "set_password")
      {:noreply, assign(socket, :set_password, %{email: user.email, form: form})}
    else
      Toast.send_to(socket.assigns.current_user, reset_error(:forbidden), %{level: :error, type: :notification})
      {:noreply, socket}
    end
  end

  def handle_event("open_set_password", _params, socket), do: {:noreply, socket}

  def handle_event("close_set_password", _params, socket), do: {:noreply, assign(socket, :set_password, nil)}

  def handle_event("validate_set_password", %{"set_password" => params}, %{assigns: %{set_password: %{}}} = socket) do
    {:ok, user} = Users.get_user(socket.assigns.entry_id)
    changeset = user |> Users.password_changeset(params) |> Map.put(:action, :validate)
    {:noreply, update(socket, :set_password, &%{&1 | form: to_form(changeset, as: "set_password")})}
  end

  def handle_event("set_password", %{"set_password" => params}, %{assigns: %{set_password: %{}}} = socket) do
    %{entry_id: entry_id, current_user: current_user} = socket.assigns

    case Users.set_user_password(entry_id, params, current_user) do
      {:ok, user} ->
        Toast.send_to(
          current_user,
          gettext("A new password was set for %{email}. They choose their own the next time they log in.",
            email: user.email
          )
        )

        # Reloaded, so the form shows the first-login change it now asks for
        {:noreply, push_navigate(socket, to: "/admin/users/update/#{entry_id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, update(socket, :set_password, &%{&1 | form: to_form(changeset, as: "set_password")})}

      {:error, reason} ->
        Toast.send_to(current_user, reset_error(reason), %{level: :error, type: :notification})
        {:noreply, assign(socket, :set_password, nil)}
    end
  end

  def handle_event(event, _params, socket) when event in ["validate_set_password", "set_password"],
    do: {:noreply, socket}

  defp reset_error(:forbidden), do: gettext("Only a superuser can reset the password of another user.")
  defp reset_error(:inactive), do: gettext("The user is deactivated, so no reset link was sent.")

  defp reset_error(reason) when reason in [:no_mailer, :no_sender],
    do: gettext("This site cannot send email, so no reset link was sent.")

  defp reset_error(_reason), do: gettext("The reset link could not be sent.")
end
