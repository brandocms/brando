defmodule BrandoAdmin.Sites.CacheLive do
  @moduledoc false
  use BrandoAdmin, :live_view
  # use Phoenix.HTML

  use Gettext, backend: Brando.Gettext

  import Phoenix.Component

  alias BrandoAdmin.Components.Workspace

  on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, __MODULE__}})

  def mount(_, %{"user_token" => token}, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> assign(:socket_connected, true)
       |> assign_caches()
       |> assign_current_user(token)
       |> set_admin_locale()}
    else
      {:ok, assign(socket, :socket_connected, false)}
    end
  end

  def render(%{socket_connected: false} = assigns) do
    ~H"""
    """
  end

  def render(assigns) do
    ~H"""
    <div class="admin-workspace cache-workspace">
      <Workspace.header title={gettext("Cache")} subtitle={gettext("Inspect cached content and clear outdated entries.")}>
        <button type="button" class="workspace-button" phx-click="empty_caches" phx-disable-with={gettext("Clearing…")}>
          {gettext("Empty all caches")}
        </button>
      </Workspace.header>
      <div class="cache-live">
        <section :for={{category, entries} <- @caches} class="workspace-panel">
          <header class="workspace-panel-heading">
            <div>
              <h2>{String.capitalize(to_string(category))}</h2>
              <p>{gettext("Stored results used to serve your website.")}</p>
            </div>
            <span>{ngettext("%{count} entry", "%{count} entries", length(entries))}</span>
          </header>
          <Workspace.empty
            :if={entries == []}
            title={gettext("No cached entries")}
            description={gettext("The cache fills automatically as content is requested.")}
          />
          <div
            :if={entries != []}
            class="workspace-table-scroll"
            tabindex="0"
            role="region"
            aria-label={gettext("Cache entries")}
          >
            <table class="workspace-table">
              <thead>
                <tr>
                  <th>{gettext("Type")}</th><th>{gettext("Module")}</th><th>{gettext("Cache key")}</th><th>
                    {gettext("Entry ID")}
                  </th><th><span class="workspace-sr-only">{gettext("Actions")}</span></th>
                </tr>
              </thead>
              <tbody>
                <.cache_row :for={entry <- entries} entry={entry} />
              </tbody>
            </table>
          </div>
        </section>
        <p class="workspace-note">
          {gettext(
            "Clear the cache if saved changes are not appearing on the website. Content is rebuilt on the next request."
          )}
        </p>
      </div>
    </div>
    """
  end

  defp cache_row(assigns) do
    row =
      case assigns.entry do
        {:list, module, key} -> %{type: gettext("List"), module: module, key: key, id: nil}
        {:single, module, key, id} -> %{type: gettext("Single"), module: module, key: key, id: id}
      end

    assigns = assigns |> assign(:row, row) |> assign(:cache_token, cache_token(assigns.entry))

    ~H"""
    <tr>
      <td><span class="workspace-badge">{@row.type}</span></td>
      <td><code>{@row.module}</code></td><td><code>{@row.key}</code></td>
      <td>
        <%= if @row.id do %>
          <code>#{@row.id}</code>
        <% else %>
          <span class="cache-unavailable">—</span>
        <% end %>
      </td>
      <td class="row-actions">
        <button
          type="button"
          class="workspace-button"
          phx-click="clear_cache_entry"
          phx-value-key={@cache_token}
          aria-label={gettext("Clear cache %{key}", key: @row.key)}
        >
          {gettext("Clear")}
        </button>
      </td>
    </tr>
    """
  end

  def handle_params(params, url, socket) do
    uri = URI.parse(url)

    {:noreply,
     socket
     |> assign(:params, params)
     |> assign(:uri, uri)}
  end

  def handle_event("empty_caches", _, socket) do
    Cachex.clear(:query)
    send(self(), {:toast, gettext("Caches cleared!")})

    {:noreply, assign_caches(socket)}
  end

  def handle_event("clear_cache_entry", %{"key" => token}, socket) do
    case Enum.find(socket.assigns.caches.query, &(cache_token(&1) == token)) do
      nil -> :ok
      entry -> Cachex.del(:query, entry)
    end

    {:noreply, assign_caches(socket)}
  end

  defp cache_token(entry) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(entry))
    |> Base.url_encode64(padding: false)
  end

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language
    |> to_string()
    |> Gettext.put_locale()

    socket
  end

  defp assign_current_user(socket, token) do
    assign_new(socket, :current_user, fn ->
      Brando.Users.get_user_by_session_token(token)
    end)
  end

  defp assign_caches(socket) do
    {:ok, query_caches} = Cachex.keys(:query)
    assign(socket, :caches, %{query: query_caches})
  end
end
