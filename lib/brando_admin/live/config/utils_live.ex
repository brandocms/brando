defmodule BrandoAdmin.Sites.UtilsLive do
  use BrandoAdmin, :live_view

  use Gettext, backend: Brando.Gettext
  import Phoenix.Component
  alias BrandoAdmin.Components.Content

  on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, __MODULE__}})

  def mount(_, %{"user_token" => token}, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> assign(:socket_connected, true)
       |> assign_current_user(token)
       |> assign_sitemap()
       |> set_admin_locale()}
    else
      {:ok,
       socket
       |> assign(:socket_connected, false)}
    end
  end

  defp assign_sitemap(socket) do
    sitemap_path = Path.join([Brando.config(:media_path), "sitemaps", "sitemap.xml.gz"])

    sitemap_last_updated =
      if File.exists?(sitemap_path) do
        {:ok, stat} = File.stat(sitemap_path, time: :posix)

        stat.mtime
        |> DateTime.from_unix!()
        |> DateTime.shift_zone!(Brando.timezone())
      else
        "Does not exist"
      end

    assign(socket, :sitemap_last_updated, sitemap_last_updated)
  end

  def render(%{socket_connected: false} = assigns) do
    ~H"""
    """
  end

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Utils")} subtitle={gettext("Admin utilities")} />

    <div class="utils-live">
      <p class="help">
        <%= gettext(
          "These utilities are for administrative purposes and are potentially expensive procedures. Use with care."
        ) %>
      </p>
      <h1><%= gettext("Utilities") %></h1>
      <table>
        <tr>
          <td>
            <%= gettext("Sync all identifiers") %><br />
          </td>
          <td>
            <button type="button" class="tiny" phx-click={JS.push("sync_identifiers")}>
              <%= gettext("Execute") %>
            </button>
          </td>
        </tr>
        <tr>
          <td>
            <%= gettext("Generate sitemap") %><br />
            <small>
              <%= gettext("Last updated: %{last_updated}", %{last_updated: @sitemap_last_updated}) %>
            </small>
          </td>
          <td>
            <button type="button" class="tiny" phx-click={JS.push("generate_sitemap")}>
              <%= gettext("Execute") %>
            </button>
          </td>
        </tr>
      </table>
    </div>
    """
  end

  def handle_params(params, url, socket) do
    uri = URI.parse(url)

    {:noreply,
     socket
     |> assign(:params, params)
     |> assign(:uri, uri)}
  end

  def handle_event("sync_identifiers", _, socket) do
    Brando.Blueprint.Identifier.sync()
    send(self(), {:toast, gettext("Identifiers synced.")})

    {:noreply, socket}
  end

  def handle_event("generate_sitemap", _, socket) do
    Brando.Sitemap.generate_sitemap()
    send(self(), {:toast, gettext("Generated sitemap.")})

    {:noreply, assign_sitemap(socket)}
  end

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language
    |> to_string
    |> Gettext.put_locale()

    socket
  end

  defp assign_current_user(socket, token) do
    assign_new(socket, :current_user, fn ->
      Brando.Users.get_user_by_session_token(token)
    end)
  end
end
