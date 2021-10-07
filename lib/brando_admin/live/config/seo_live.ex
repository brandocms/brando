defmodule BrandoAdmin.Sites.SEOLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Sites.SEO
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
      title="SEO"
      subtitle="Update SEO" />

    <Form
      id="seo_form"
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
end
