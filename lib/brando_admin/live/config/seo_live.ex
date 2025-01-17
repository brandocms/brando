defmodule BrandoAdmin.Sites.SEOLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Sites.SEO
  use Gettext, backend: Brando.Gettext

  alias Brando.Sites
  alias BrandoAdmin.Components.Form

  def mount(_params, %{"user_token" => token}, socket) do
    {:ok,
     socket
     |> assign_current_user(token)
     |> assign_entry_id()
     |> assign_404s()}
  end

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="seo_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
    >
      <:header>
        {gettext("Update SEO")}
      </:header>
    </.live_component>

    <div class="cache-live">
      <table>
        <h1>404s</h1>
        <tr>
          <th>{gettext("URL")}</th>
          <th>{gettext("Hits")}</th>
          <th>{gettext("Last hit")}</th>
        </tr>
        <%= for item <- @four_oh_fours do %>
          <tr>
            <td>
              <div class="text-mono">
                {item.url}
              </div>
            </td>
            <td>
              <div class="text-mono">
                {item.hits}
              </div>
            </td>
            <td>
              <div class="text-mono">
                {item.last_hit_at}
              </div>
            </td>
          </tr>
        <% end %>
      </table>
    </div>
    """
  end

  defp assign_current_user(socket, token) do
    assign_new(socket, :current_user, fn ->
      Brando.Users.get_user_by_session_token(token)
    end)
  end

  defp assign_404s(socket) do
    assign_new(socket, :four_oh_fours, fn -> Brando.Sites.FourOhFour.list() end)
  end

  defp assign_entry_id(%{assigns: %{current_user: %{config: %{content_language: content_language}}}} = socket) do
    case Sites.get_seo(%{matches: %{language: content_language}}) do
      {:ok, seo} ->
        assign(socket, :entry_id, seo.id)

      {:error, _} ->
        first_seo = List.first(Sites.list_seos!())

        {:ok, seo} =
          Sites.duplicate_seo(first_seo.id, :system, merge_fields: %{language: content_language})

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

  def handle_info({:EXIT, _port, :normal}, socket) do
    {:noreply, socket}
  end
end
