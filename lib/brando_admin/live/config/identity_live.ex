defmodule BrandoAdmin.Sites.IdentityLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Sites.Identity
  alias Brando.Sites
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form

  def mount(_params, %{"user_token" => token} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_current_user(token)
     |> assign_entry_id()}
  end

  def render(assigns) do
    ~F"""
    <Content.Header
      title="Identity"
      subtitle="Update identity" />

    <Form
      id="identity_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
    />
    """
  end

  defp assign_current_user(socket, token) do
    assign_new(socket, :current_user, fn ->
      Brando.Users.get_user_by_session_token(token)
    end)
  end

  defp assign_entry_id(
         %{
           assigns: %{current_user: %{config: %{content_language: content_language}}}
         } = socket
       ) do
    case Sites.get_identity(%{matches: %{language: content_language}}) do
      {:ok, identity} ->
        assign(socket, :entry_id, identity.id)

      {:error, _} ->
        {:ok, english_identity} = Sites.get_identity(%{matches: %{language: "en"}})
        {:ok, identity} = Sites.duplicate_identity(english_identity.id, :system)
        {:ok, identity} = Sites.update_identity(identity, %{language: content_language}, :system)
        assign(socket, :entry_id, identity.id)
    end
  end
end
