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
      not superuser?(socket.assigns.current_user) ->
        {:ok, redirect(socket, to: "/admin")}

      connected?(socket) ->
        {:ok,
         socket
         |> assign(:socket_connected, true)
         |> assign(:scope_site, scope_site(socket))
         |> set_admin_locale()
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
      subtitle={gettext("Manage the frontend build currently served by Phoenix")}
    >
      <button type="button" class="secondary" phx-click="refresh">{gettext("Refresh")}</button>
    </Content.header>

    <div class="frontend-assets-live">
      <section class={["frontend-assets-current", @active_set && "uploaded"]}>
        <div class="frontend-assets-current__icon">
          <.icon name={if @active_set, do: "hero-cube-transparent", else: "hero-code-bracket"} />
        </div>

        <div class="frontend-assets-current__content">
          <span class="frontend-assets-eyebrow">
            {gettext("Currently served")} · {scope_name(@scope_site)}
          </span>
          <h2>{if @active_set, do: @active_set.name, else: gettext("Release assets")}</h2>
          <p>
            {if @active_set,
              do: gettext("This uploaded build is serving frontend requests now."),
              else: gettext("The CSS and JavaScript packaged with the current application release are being served.")}
          </p>

          <dl :if={@active_set} class="frontend-assets-current__meta">
            <div>
              <dt>{gettext("Revision")}</dt>
              <dd>{@active_set.metadata["revision"] || gettext("Not provided")}</dd>
            </div>
            <div>
              <dt>{gettext("Uploaded")}</dt>
              <dd>{format_datetime(@active_set.uploaded_at)}</dd>
            </div>
            <div>
              <dt>{gettext("Bundle")}</dt>
              <dd>{ngettext("%{count} file", "%{count} files", @active_set.file_count)}</dd>
              <dd>{format_size(@active_set.size)}</dd>
            </div>
          </dl>
        </div>

        <div class="frontend-assets-current__actions">
          <span class="frontend-assets-status active">
            <span aria-hidden="true"></span>
            {gettext("Serving now")}
          </span>
          <button
            :if={@active_set}
            type="button"
            class="secondary small"
            phx-click="deactivate"
            phx-confirm={gettext("Use the frontend assets included in the current release?")}
          >
            {gettext("Use release assets")}
          </button>
        </div>
      </section>

      <section class="frontend-assets-library">
        <header>
          <div>
            <span class="frontend-assets-eyebrow">{gettext("Build library")}</span>
            <h2>{gettext("Uploaded builds")}</h2>
            <p>
              {gettext(
                "Florist registers each build here. Activating one takes effect immediately and does not deploy the application."
              )}
            </p>
          </div>
          <span class="frontend-assets-count">
            {ngettext("%{count} build", "%{count} builds", length(@sets))}
          </span>
        </header>

        <div :if={@sets == []} class="frontend-assets-empty">
          <span class="frontend-assets-empty__icon"><.icon name="hero-arrow-path" /></span>
          <h3>{gettext("No uploaded builds yet")}</h3>
          <p>
            {gettext("The frontend packaged with the current release remains active until Florist registers a build.")}
          </p>
        </div>

        <div :if={@sets != []} class="frontend-assets-list">
          <article
            :for={asset_set <- @sets}
            id={"asset-set-#{asset_set.id}"}
            class={["frontend-assets-build", asset_set.active && "active"]}
          >
            <span class="frontend-assets-build__icon"><.icon name="hero-cube-transparent" /></span>

            <div class="frontend-assets-build__identity">
              <h3>{asset_set.name}</h3>
              <code>{asset_set.metadata["revision"] || asset_set.path}</code>
            </div>

            <dl class="frontend-assets-build__meta">
              <div>
                <dt>{gettext("Uploaded")}</dt>
                <dd>{format_datetime(asset_set.uploaded_at)}</dd>
              </div>
              <div>
                <dt>{gettext("Bundle")}</dt>
                <dd>
                  {ngettext("%{count} file", "%{count} files", asset_set.file_count)} · {format_size(asset_set.size)}
                </dd>
              </div>
            </dl>

            <div class="frontend-assets-build__actions">
              <span class={["frontend-assets-status", asset_set.active && "active"]}>
                <span aria-hidden="true"></span>
                {if asset_set.active, do: gettext("Active"), else: gettext("Available")}
              </span>
              <button
                :if={!asset_set.active}
                type="button"
                class="primary small"
                phx-click="activate"
                phx-value-id={asset_set.id}
                phx-confirm={
                  gettext("Activate %{name} now? Frontend requests will switch immediately.", name: asset_set.name)
                }
              >
                {gettext("Activate build")}
              </button>
            </div>
          </article>
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

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language
    |> to_string()
    |> Gettext.put_locale()

    socket
  end

  defp scope_name(nil), do: gettext("This installation")
  defp scope_name(site), do: site.name

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")

  defp format_size(bytes) when bytes < 1_024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1_024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp superuser?(user) do
    if Brando.Authorization.enabled?(),
      do: Brando.Authorization.can?(Brando.Authorization.Scope.installation(user), :read, :frontend_assets),
      else: user.role == :superuser
  end
end
