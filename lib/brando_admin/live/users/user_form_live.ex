defmodule BrandoAdmin.Users.UserFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Users.User
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Toast

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
    """
  end

  # Brando.Users.send_password_reset/2 decides who may send the link.
  def handle_event("send_password_reset", _params, %{assigns: %{entry_id: entry_id}} = socket)
      when not is_nil(entry_id) do
    %{current_user: current_user} = socket.assigns

    case Brando.Users.send_password_reset(entry_id, current_user) do
      {:ok, user} ->
        Toast.send_to(current_user, gettext("A password reset link was sent to %{email}.", email: user.email))

      {:error, reason} ->
        Toast.send_to(current_user, reset_error(reason), %{level: :error, type: :notification})
    end

    {:noreply, socket}
  end

  def handle_event("send_password_reset", _params, socket), do: {:noreply, socket}

  defp reset_error(:forbidden), do: gettext("Only a superuser can reset the password of another user.")
  defp reset_error(:inactive), do: gettext("The user is deactivated, so no reset link was sent.")

  defp reset_error(reason) when reason in [:no_mailer, :no_sender],
    do: gettext("This site cannot send email, so no reset link was sent.")

  defp reset_error(_reason), do: gettext("The reset link could not be sent.")
end
