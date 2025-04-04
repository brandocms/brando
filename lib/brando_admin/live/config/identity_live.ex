defmodule BrandoAdmin.Sites.IdentityLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Sites.Identity
  use Gettext, backend: Brando.Gettext

  alias Brando.Sites
  alias BrandoAdmin.Components.Form

  def mount(_params, %{"user_token" => token}, socket) do
    {:ok,
     socket
     |> assign_current_user(token)
     |> assign_entry_id()}
  end

  def render(assigns) do
    ~H"""
    <.live_component module={Form} id="identity_form" entry_id={@entry_id} current_user={@current_user} schema={@schema}>
      <:header>
        {gettext("Update identity")} (<code><%= @current_user.config.content_language %></code>)
      </:header>
    </.live_component>
    """
  end

  defp assign_current_user(socket, token) do
    assign_new(socket, :current_user, fn ->
      Brando.Users.get_user_by_session_token(token)
    end)
  end

  defp assign_entry_id(%{assigns: %{current_user: %{config: %{content_language: content_language}}}} = socket) do
    case Sites.get_identity(%{matches: %{language: content_language}}) do
      {:ok, identity} ->
        assign(socket, :entry_id, identity.id)

      {:error, _} ->
        first_identity = List.first(Sites.list_identities!())

        {:ok, identity} =
          Sites.duplicate_identity(first_identity.id, :system, merge_fields: %{language: content_language})

        assign(socket, :entry_id, identity.id)
    end
  end

  def handle_info({:content_language, _language}, socket) do
    send_update_after(
      BrandoAdmin.Components.Form,
      [id: "identity_form", action: :refresh_entry],
      500
    )

    {:noreply, assign_entry_id(socket)}
  end
end
