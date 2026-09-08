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
    <div class="admin-workspace settings-workspace seo-workspace">
      <.live_component module={Form} id="seo_form" entry_id={@entry_id} current_user={@current_user} schema={@schema}>
        <:header>
          {gettext("Update SEO")}
        </:header>
      </.live_component>

      <section class="workspace-panel seo-not-found">
        <header class="workspace-panel-heading">
          <div>
            <h2>{gettext("Not found (404)")}</h2><p>
              {gettext("Requests for URLs that do not exist. Add a redirect above when a page has moved.")}
            </p>
          </div>
        </header>
        <BrandoAdmin.Components.Workspace.empty
          :if={@four_oh_fours == []}
          title={gettext("No missing URLs recorded")}
          description={gettext("Missing pages will appear here when they are requested.")}
        />
        <div
          :if={@four_oh_fours != []}
          class="workspace-table-scroll"
          tabindex="0"
          role="region"
          aria-label={gettext("Not found (404)")}
        >
          <table class="workspace-table">
            <thead>
              <tr>
                <th>{gettext("URL")}</th><th>{gettext("Hits")}</th><th>{gettext("Last hit")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={item <- @four_oh_fours}>
                <td class="workspace-mono">{item.url}</td><td>{item.hits}</td><td>{item.last_hit_at}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
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
