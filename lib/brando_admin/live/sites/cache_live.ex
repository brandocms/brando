defmodule BrandoAdmin.Sites.CacheLive do
  @moduledoc false
  use BrandoAdmin, :live_view
  # use Phoenix.HTML

  use Gettext, backend: Brando.Gettext

  import Phoenix.Component

  alias Brando.Authorization.{Boundary, Engine, Scope}
  alias Brando.Tenant
  alias Brando.Tenant.Access
  alias BrandoAdmin.Components.Workspace

  on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, __MODULE__}})

  def mount(_, %{"user_token" => token}, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> assign(:socket_connected, true)
       |> assign(:tenancy?, Tenant.enabled?())
       |> assign_current_user(token)
       |> assign_caches()
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
        <button type="button" class="btn" phx-click="empty_caches" phx-disable-with={gettext("Clearing…")}>
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
                  <th>{gettext("Type")}</th><th :if={@tenancy?}>{gettext("Site")}</th><th>{gettext("Module")}</th><th>
                    {gettext("Cache key")}
                  </th><th>
                    {gettext("Entry ID")}
                  </th><th><span class="workspace-sr-only">{gettext("Actions")}</span></th>
                </tr>
              </thead>
              <tbody>
                <.cache_row :for={entry <- entries} entry={entry} tenancy?={@tenancy?} />
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
    assigns = assign(assigns, :cache_token, cache_token(assigns.entry.key))

    ~H"""
    <tr>
      <td><span class="badge">{type_label(@entry.type)}</span></td>
      <td :if={@tenancy?}>
        <%= if @entry.site do %>
          {@entry.site}
        <% else %>
          <span class="cache-unavailable">—</span>
        <% end %>
      </td>
      <td><code>{@entry.source}</code></td><td><code>{@entry.hash}</code></td>
      <td>
        <%= if @entry.id do %>
          <code>#{@entry.id}</code>
        <% else %>
          <span class="cache-unavailable">—</span>
        <% end %>
      </td>
      <td class="row-actions">
        <button
          type="button"
          class="btn"
          phx-click="clear_cache_entry"
          phx-value-key={@cache_token}
          aria-label={gettext("Clear cache %{key}", key: @entry.hash)}
        >
          {gettext("Clear")}
        </button>
      </td>
    </tr>
    """
  end

  defp type_label(:list), do: gettext("List")
  defp type_label(:single), do: gettext("Single")

  def handle_params(params, url, socket) do
    uri = URI.parse(url)

    {:noreply,
     socket
     |> assign(:params, params)
     |> assign(:uri, uri)}
  end

  def handle_event("empty_caches", _, socket) do
    user = socket.assigns.current_user

    :ok =
      if every_entry?(user),
        do: Brando.Cache.reload_all(),
        else: user |> entries(:update) |> Enum.map(& &1.key) |> Brando.Cache.reload_all()

    send(self(), {:toast, gettext("Caches cleared!")})

    {:noreply, assign_caches(socket)}
  end

  def handle_event("clear_cache_entry", %{"key" => token}, socket) do
    case Enum.find(entries(socket.assigns.current_user, :update), &(cache_token(&1.key) == token)) do
      nil -> :ok
      entry -> Cachex.del(:query, entry.key)
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
    assign(socket, :caches, %{query: entries(socket.assigns.current_user, :read)})
  end

  # The query cache's entries this user may `action` (`:read` lists, `:update`
  # clears). On a multi-site install, a site environment's are under its
  # prefix, for those who may use this screen there; the rest, cached outside
  # every site or for a site no longer in the registry, for superusers. With
  # one site, the screen's own authorization covers it, and everyone here may
  # use every entry. A key of another shape is no query result this screen
  # knows, and is skipped.
  defp entries(user, action) do
    {:ok, keys} = Cachex.keys(:query)
    entries = keys |> Enum.map(&entry/1) |> Enum.reject(&is_nil/1)

    permitted =
      if every_entry?(user),
        do: entries,
        else: entries |> Enum.group_by(& &1.prefix) |> permitted_groups(user, action)

    permitted
    |> Enum.map(&put_site/1)
    |> Enum.sort_by(&{&1.site || "", &1.source, &1.type, &1.hash, &1.id || 0})
  end

  defp permitted_groups(groups, user, action) do
    Enum.flat_map(groups, fn {prefix, entries} -> if permitted?(user, prefix, action), do: entries, else: [] end)
  end

  defp every_entry?(user), do: Tenant.mode() != :multi or Boundary.superuser?(user)

  defp entry({:tenant, prefix, key} = tenant_key) when is_binary(prefix) do
    case entry(key) do
      %{prefix: nil} = entry -> %{entry | key: tenant_key, prefix: prefix}
      _ -> nil
    end
  end

  defp entry({:list, source, hash} = key) when is_binary(source) and is_binary(hash),
    do: %{key: key, prefix: nil, site: nil, type: :list, source: source, hash: hash, id: nil}

  defp entry({:single, source, hash, id} = key)
       when is_binary(source) and is_binary(hash) and (is_integer(id) or is_binary(id)),
       do: %{key: key, prefix: nil, site: nil, type: :single, source: source, hash: hash, id: id}

  defp entry(_key), do: nil

  defp permitted?(_user, nil, _action), do: false

  defp permitted?(user, prefix, action) do
    case site_environment(prefix) do
      {site, environment} ->
        if Engine.enabled?(),
          do: Engine.can?(Scope.site(user, site, environment), action, :utilities),
          else: Access.can_access?(user, site)

      nil ->
        false
    end
  end

  defp put_site(%{prefix: nil} = entry), do: entry

  defp put_site(%{prefix: prefix} = entry) do
    case site_environment(prefix) do
      {site, environment} -> %{entry | site: "#{site.name} · #{environment.name}"}
      nil -> %{entry | site: prefix}
    end
  end

  defp site_environment("tenant_" <> suffix) do
    with [site_key, environment_key] <- String.split(suffix, "_", parts: 2),
         %{} = site <- Tenant.Cache.get_site(site_key),
         %{} = environment <- Tenant.Cache.get_env(site_key, environment_key) do
      {site, environment}
    else
      _ -> nil
    end
  end

  defp site_environment(_prefix), do: nil
end
