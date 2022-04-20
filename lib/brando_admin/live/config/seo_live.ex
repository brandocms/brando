defmodule BrandoAdmin.Sites.SEOLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Sites.SEO
  import Brando.Gettext
  alias Brando.Sites
  alias BrandoAdmin.Components.Form

  def mount(_params, %{"user_token" => token} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_current_user(token)
     |> assign_entry_id()}
  end

  def render(assigns) do
    ~H"""
    <.live_component module={Form}
      id="seo_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}>
      <:header>
        <%= gettext("Update SEO") %>
      </:header>
    </.live_component>
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
    case Sites.get_seo(%{matches: %{language: content_language}}) do
      {:ok, seo} ->
        assign(socket, :entry_id, seo.id)

      {:error, _} ->
        {:ok, english_seo} = Sites.get_seo(%{matches: %{language: "en"}})
        {:ok, seo} = Sites.duplicate_seo(english_seo.id, :system)
        {:ok, seo} = Sites.update_seo(seo, %{language: content_language}, :system)
        assign(socket, :entry_id, seo.id)
    end
  end

  def handle_info({:content_language, _language}, socket) do
    send_update_after(
      BrandoAdmin.Components.Form,
      [id: "seo_form", action: :refresh_entry],
      500
    )

    {:noreply, assign_entry_id(socket)}
  end
end
