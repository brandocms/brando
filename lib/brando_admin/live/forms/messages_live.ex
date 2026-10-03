defmodule BrandoAdmin.Forms.MessagesLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Forms.Messages
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form

  def mount(_params, %{"user_token" => token}, socket) do
    socket =
      assign_new(socket, :current_user, fn -> Brando.Users.get_user_by_session_token(token) end)

    {:ok, messages} = Brando.Forms.ensure_messages(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:entry_id, messages.id)
     |> assign(:page_title, gettext("Form messages"))}
  end

  def render(assigns) do
    ~H"""
    <div class="admin-workspace settings-workspace form-messages-workspace">
      <.live_component module={Form} id="messages_form" entry_id={@entry_id} current_user={@current_user} schema={@schema}>
        <:header>
          <span>{gettext("Form messages")}</span>
        </:header>
        <:instructions>
          {gettext(
            "What visitors read around every form, in each of the site's languages. A language left empty uses Brando's wording, in English where Brando has no translation."
          )}
        </:instructions>
      </.live_component>
    </div>
    """
  end
end
