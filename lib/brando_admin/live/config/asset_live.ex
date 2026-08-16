defmodule BrandoAdmin.Sites.AssetLive do
  @moduledoc false

  use BrandoAdmin, :live_view
  use BrandoAdmin.Toast
  use Gettext, backend: Brando.Gettext

  alias Brando.Assets.SiteAssets
  alias Brando.Tenant
  alias BrandoAdmin.Components.Content

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    cond do
      socket.assigns.current_user.role != :superuser ->
        {:ok, redirect(socket, to: "/admin")}

      connected?(socket) ->
        {:ok,
         socket
         |> assign(:socket_connected, true)
         |> assign(:scope_site, scope_site(socket))
         |> refresh()}

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
      title={gettext("Frontend assets")}
      subtitle={gettext("Activate or revert persistent frontend builds without deploying a release")}
    >
      <button type="button" class="secondary" phx-click="refresh">{gettext("Refresh")}</button>
    </Content.header>

    <div class="environment-management-live">
      <section class="environment-panel">
        <header>
          <div>
            <h2>{scope_name(@scope_site)}</h2>
            <p>{gettext("Florist registers uploaded sets here; registration never activates a build.")}</p>
          </div>
          <button
            type="button"
            class="danger"
            disabled={is_nil(@active_set)}
            phx-click="deactivate"
            phx-confirm={gettext("Revert to the frontend assets included in the current release?")}
          >
            {gettext("Revert to release assets")}
          </button>
        </header>

        <div :if={@sets == []} class="environment-notice">
          {gettext("No uploaded frontend asset sets have been registered.")}
        </div>

        <div :if={@sets != []} class="environment-table-wrap">
          <table>
            <thead>
              <tr>
                <th>{gettext("Set")}</th>
                <th>{gettext("Uploaded")}</th>
                <th>{gettext("Files")}</th>
                <th>{gettext("Size")}</th>
                <th>{gettext("State")}</th>
                <th>{gettext("Actions")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={asset_set <- @sets} id={"asset-set-#{asset_set.id}"}>
                <td>
                  <strong>{asset_set.name}</strong>
                  <code>{asset_set.metadata["revision"] || asset_set.path}</code>
                </td>
                <td>{format_datetime(asset_set.uploaded_at)}</td>
                <td>{asset_set.file_count}</td>
                <td>{format_size(asset_set.size)}</td>
                <td>
                  <span class={["environment-state", asset_set.active && "live"]}>
                    {if asset_set.active, do: gettext("Active"), else: gettext("Available")}
                  </span>
                </td>
                <td>
                  <button
                    :if={!asset_set.active}
                    type="button"
                    class="primary small"
                    phx-click="activate"
                    phx-value-id={asset_set.id}
                    phx-confirm={gettext("Activate %{name} immediately?", name: asset_set.name)}
                  >
                    {gettext("Activate")}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("refresh", _params, socket), do: {:noreply, refresh(socket)}

  def handle_event("activate", %{"id" => id}, socket) do
    with {asset_set_id, ""} <- Integer.parse(id),
         true <- Enum.any?(socket.assigns.sets, &(&1.id == asset_set_id)),
         {:ok, asset_set} <- SiteAssets.activate_set(asset_set_id) do
      send(self(), {:toast, gettext("Activated %{name}", name: asset_set.name)})
      {:noreply, refresh(socket)}
    else
      _error ->
        send(self(), {:toast, gettext("Could not activate the frontend asset set"), :error})
        {:noreply, socket}
    end
  end

  def handle_event("deactivate", _params, socket) do
    case SiteAssets.deactivate(socket.assigns.scope_site) do
      :ok ->
        send(self(), {:toast, gettext("Reverted to release assets")})
        {:noreply, refresh(socket)}

      {:error, _reason} ->
        send(self(), {:toast, gettext("Could not revert the frontend assets"), :error})
        {:noreply, socket}
    end
  end

  defp refresh(socket) do
    sets = SiteAssets.list_sets(socket.assigns.scope_site)

    socket
    |> assign(:sets, sets)
    |> assign(:active_set, Enum.find(sets, & &1.active))
  end

  defp scope_site(socket) do
    if Tenant.mode() == :multi, do: socket.assigns[:current_site], else: nil
  end

  defp scope_name(nil), do: gettext("Standalone frontend")
  defp scope_name(site), do: site.name

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")

  defp format_size(bytes) when bytes < 1_024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1_024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"
end
