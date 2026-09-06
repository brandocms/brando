defmodule BrandoAdmin.Sites.SiteLive do
  @moduledoc false

  use BrandoAdmin, :live_view
  use BrandoAdmin.Toast
  use Gettext, backend: Brando.Gettext

  alias Brando.Sites.Site
  alias Brando.Tenant.Access
  alias Brando.Tenant.Registry
  alias Brando.Tenant.Setup
  alias Brando.Tenant.Storage
  alias Brando.Users.User
  alias BrandoAdmin.Components.Content

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    cond do
      Brando.Tenant.mode() != :multi or not superuser?(socket.assigns.current_user) ->
        {:ok, redirect(socket, to: "/admin")}

      connected?(socket) ->
        {:ok, socket |> assign(:socket_connected, true) |> refresh()}

      true ->
        {:ok, assign(socket, :socket_connected, false)}
    end
  end

  @impl Phoenix.LiveView
  def render(%{socket_connected: false} = assigns) do
    ~H"""
    """
  end

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("Sites")}
      subtitle={gettext("Provision isolated sites, control lifecycle, and assign users")}
    >
      <button type="button" class="secondary" phx-click="refresh">{gettext("Refresh")}</button>
    </Content.header>

    <div class="environment-management-live">
      <section class="environment-panel">
        <h2>{gettext("Create site")}</h2>
        <p>{gettext("Creates Production and Staging schemas, seeds initial content, and grants you site admin access.")}</p>
        <form id="create-site-form" phx-submit="create_site">
          <div class="environment-grid">
            <label>
              <span>{gettext("Name")}</span>
              <input name="site[name]" required placeholder={gettext("Acme Corporation")} />
            </label>
            <label>
              <span>{gettext("Key")}</span>
              <input name="site[key]" required pattern="[a-z0-9]+(?:-[a-z0-9]+)*" placeholder="acme" />
            </label>
            <label>
              <span>{gettext("Languages")}</span>
              <input name="site[languages]" required value="en" placeholder="en,no" />
            </label>
            <label>
              <span>{gettext("Default language")}</span>
              <input name="site[default_language]" required value="en" />
            </label>
            <label>
              <span>{gettext("Delivery")}</span>
              <select name="site[delivery_mode]">
                <option value="dynamic">{gettext("Dynamic")}</option>
                <option value="static">{gettext("Static")}</option>
              </select>
              <small>
                {gettext("Dynamic is served directly by Phoenix. Static requires a configured SSG build and deploy pipeline.")}
              </small>
            </label>
          </div>
          <button type="submit" class="primary" phx-disable-with={gettext("Provisioning…")}>
            {gettext("Create site")}
          </button>
        </form>
      </section>

      <section :for={site <- @sites} class="environment-panel" id={"site-#{site.id}"}>
        <header>
          <div>
            <h2>{site.name}</h2>
            <p><code>{site.key}</code></p>
          </div>
          <span class={["environment-state", site.status == :active && "live"]}>{site.status}</span>
        </header>

        <dl class="site-stats">
          <div>
            <dt>{gettext("Environments")}</dt><dd>{length(site.environments)}</dd>
          </div>
          <div>
            <dt>{gettext("Pages")}</dt><dd>{stat(@stats, site.id, :page_count)}</dd>
          </div>
          <div>
            <dt>{gettext("Media")}</dt><dd>{format_size(stat(@stats, site.id, :media_size))}</dd>
          </div>
          <div>
            <dt>{gettext("Last page edit")}</dt><dd>{format_last_edit(stat(@stats, site.id, :last_edit))}</dd>
          </div>
        </dl>

        <div class="environment-actions">
          <button
            :if={site.status == :active}
            type="button"
            class="secondary"
            phx-click="suspend"
            phx-value-id={site.id}
          >
            {gettext("Suspend")}
          </button>
          <button
            :if={site.status == :suspended}
            type="button"
            class="primary"
            phx-click="activate_site"
            phx-value-id={site.id}
          >
            {gettext("Activate")}
          </button>
          <button
            :if={site.status != :archived}
            type="button"
            class="danger"
            phx-click="archive"
            phx-value-id={site.id}
            phx-confirm={gettext("Archive %{name}? Its domains will stop serving immediately.", name: site.name)}
          >
            {gettext("Archive")}
          </button>
          <button
            :if={site.status == :archived}
            type="button"
            class="secondary"
            phx-click="activate_site"
            phx-value-id={site.id}
          >
            {gettext("Restore")}
          </button>
          <button
            :if={site.status == :archived}
            type="button"
            class="danger"
            phx-click="delete"
            phx-value-id={site.id}
            phx-confirm={gettext("Permanently delete %{name}, all schemas, media, and uploaded assets?", name: site.name)}
          >
            {gettext("Permanently delete")}
          </button>
        </div>

        <p :if={Brando.Authorization.enabled?()}>
          <a href={"/admin/groups?brando_site_key=#{site.key}"}>{gettext("Manage this site’s groups and members →")}</a>
        </p>
        <div :if={!Brando.Authorization.enabled?()} class="environment-grid">
          <section>
            <h3>{gettext("Site users")}</h3>
            <p :if={assignments(@assignments, site.id) == []}>{gettext("No explicit user assignments.")}</p>
            <table :if={assignments(@assignments, site.id) != []}>
              <tbody>
                <tr :for={assignment <- assignments(@assignments, site.id)} id={"assignment-#{assignment.id}"}>
                  <td>{assignment.user.name}<small>{assignment.user.email}</small></td>
                  <td><span class="badge">{assignment.role}</span></td>
                  <td>
                    <button
                      type="button"
                      class="danger small"
                      phx-click="revoke"
                      phx-value-site-id={site.id}
                      phx-value-user-id={assignment.user_id}
                    >
                      {gettext("Revoke")}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </section>

          <section>
            <h3>{gettext("Grant access")}</h3>
            <form phx-submit="grant" id={"grant-site-#{site.id}"}>
              <input type="hidden" name="assignment[site_id]" value={site.id} />
              <label>
                <span>{gettext("User")}</span>
                <select name="assignment[user_id]" required>
                  <option :for={user <- @users} value={user.id}>{user.name} · {user.email}</option>
                </select>
              </label>
              <label>
                <span>{gettext("Role")}</span>
                <select name="assignment[role]">
                  <option value="editor">{gettext("Editor")}</option>
                  <option value="admin">{gettext("Administrator")}</option>
                </select>
              </label>
              <button type="submit" class="primary">{gettext("Grant access")}</button>
            </form>
          </section>
        </div>
      </section>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("refresh", _params, socket), do: {:noreply, refresh(socket)}

  def handle_event("create_site", %{"site" => params}, socket) do
    attrs = %{
      name: params["name"],
      key: params["key"],
      languages: parse_languages(params["languages"]),
      default_language: params["default_language"],
      status: :active,
      delivery_mode: parse_delivery_mode(params["delivery_mode"])
    }

    case Setup.create_site(attrs, socket.assigns.current_user) do
      {:ok, site} -> {:noreply, socket |> notify(gettext("Site %{name} created.", name: site.name)) |> refresh()}
      {:error, reason} -> {:noreply, notify_error(socket, lifecycle_error(reason))}
    end
  end

  def handle_event(event, _params, socket)
      when event in ["grant", "revoke"] and is_map_key(socket.assigns, :authorization) do
    {:noreply, put_flash(socket, :error, gettext("Manage access through this site’s groups."))}
  end

  def handle_event("grant", %{"assignment" => params}, socket) do
    with {:ok, site} <- site_from_socket(socket, params["site_id"]),
         {:ok, user} <- user_from_socket(socket, params["user_id"]),
         {:ok, role} <- parse_role(params["role"]),
         {:ok, _assignment} <- Access.grant(user, site, role) do
      {:noreply, socket |> notify(gettext("Site access updated.")) |> refresh()}
    else
      {:error, reason} -> {:noreply, notify_error(socket, lifecycle_error(reason))}
    end
  end

  def handle_event("revoke", params, socket) do
    with {:ok, site} <- site_from_socket(socket, params["site-id"]),
         {:ok, user} <- user_from_socket(socket, params["user-id"]),
         :ok <- Access.revoke(user, site) do
      {:noreply, socket |> notify(gettext("Site access revoked.")) |> refresh()}
    else
      {:error, reason} -> {:noreply, notify_error(socket, lifecycle_error(reason))}
    end
  end

  for {event, operation} <- [
        {"suspend", :suspend_site},
        {"activate_site", :activate_site},
        {"archive", :archive_site},
        {"delete", :delete_site}
      ] do
    def handle_event(unquote(event), %{"id" => id}, socket) do
      with {:ok, site} <- site_from_socket(socket, id),
           {:ok, _site} <- apply(Setup, unquote(operation), [site]) do
        {:noreply, socket |> notify(gettext("Site lifecycle updated.")) |> refresh()}
      else
        {:error, reason} -> {:noreply, notify_error(socket, lifecycle_error(reason))}
      end
    end
  end

  defp refresh(socket) do
    sites = Registry.list_sites() |> Enum.sort_by(&{&1.name, &1.id})
    {:ok, users} = Brando.Users.list_users(%{order: "asc name"})
    users = Enum.reject(users, &(&1.role == :superuser))

    socket
    |> assign(:sites, sites)
    |> assign(:users, users)
    |> assign(:assignments, Map.new(sites, &{&1.id, Access.list_assignments(&1)}))
    |> assign(:stats, Map.new(sites, &{&1.id, site_stats(&1)}))
  end

  defp site_stats(site) do
    live_environment = Enum.find(site.environments, & &1.live)

    %{
      page_count: page_stat(site, live_environment, :count),
      last_edit: page_stat(site, live_environment, :last_edit),
      media_size: directory_size(Storage.media_root(site))
    }
  end

  defp page_stat(_site, nil, _stat), do: "—"

  defp page_stat(site, environment, stat) do
    prefix = Brando.Tenant.prefix(site, environment)
    table = Brando.Pages.Page.__schema__(:source)

    sql =
      case stat do
        :count -> ~s|SELECT count(*) FROM "#{prefix}"."#{table}"|
        :last_edit -> ~s|SELECT max(updated_at) FROM "#{prefix}"."#{table}"|
      end

    case Ecto.Adapters.SQL.query(Brando.Repo.repo(), sql, []) do
      {:ok, %{rows: [[value]]}} -> value || "—"
      {:error, _reason} -> "—"
    end
  end

  defp directory_size(path) do
    case File.ls(path) do
      {:ok, entries} ->
        Enum.reduce(entries, 0, fn entry, total -> total + entry_size(path, entry) end)

      {:error, _reason} ->
        0
    end
  end

  defp entry_size(path, entry) do
    child = Path.join(path, entry)

    case File.lstat(child) do
      {:ok, %{type: :regular, size: size}} -> size
      {:ok, %{type: :directory}} -> directory_size(child)
      _symlink_or_error -> 0
    end
  end

  defp site_from_socket(socket, id) do
    with {site_id, ""} <- Integer.parse(to_string(id)),
         %Site{} = site <- Enum.find(socket.assigns.sites, &(&1.id == site_id)) do
      {:ok, site}
    else
      _ -> {:error, :site_not_found}
    end
  end

  defp user_from_socket(socket, id) do
    with {user_id, ""} <- Integer.parse(to_string(id)),
         %User{} = user <- Enum.find(socket.assigns.users, &(&1.id == user_id)) do
      {:ok, user}
    else
      _ -> {:error, :user_not_found}
    end
  end

  defp parse_languages(languages) do
    languages
    |> to_string()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp parse_delivery_mode("static"), do: :static
  defp parse_delivery_mode(_dynamic), do: :dynamic

  defp parse_role("editor"), do: {:ok, :editor}
  defp parse_role("admin"), do: {:ok, :admin}
  defp parse_role(_role), do: {:error, :invalid_role}

  defp assignments(assignments, site_id), do: Map.get(assignments, site_id, [])
  defp stat(stats, site_id, key), do: stats |> Map.get(site_id, %{}) |> Map.get(key, "—")

  defp format_size("—"), do: "—"
  defp format_size(bytes) when bytes < 1_024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1_024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_last_edit(%NaiveDateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  defp format_last_edit(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  defp format_last_edit(value), do: value

  defp notify(socket, message) do
    send(self(), {:toast, message})
    socket
  end

  defp notify_error(socket, message) do
    BrandoAdmin.Toast.send_to(socket.assigns.current_user, message, %{level: :error, type: :notification})
    socket
  end

  defp lifecycle_error({:retention_period, days}),
    do: gettext("This site must remain archived for %{days} days before permanent deletion.", days: days)

  defp lifecycle_error(%Ecto.Changeset{} = changeset) do
    BrandoAdmin.Utils.format_changeset_errors(changeset)
  end

  defp lifecycle_error({:site_setup_failed, reason, _compensation}), do: lifecycle_error(reason)
  defp lifecycle_error(reason) when is_atom(reason), do: reason |> Atom.to_string() |> String.replace("_", " ")
  defp lifecycle_error(reason), do: inspect(reason)

  defp superuser?(user) do
    if Brando.Authorization.enabled?(),
      do: Brando.Authorization.can?(Brando.Authorization.Scope.installation(user), :read, :sites),
      else: user.role == :superuser
  end
end
