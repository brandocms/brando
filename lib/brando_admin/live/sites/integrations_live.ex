defmodule BrandoAdmin.Sites.IntegrationsLive do
  @moduledoc """
  Configuration → Integrations: the services this site sends content to or
  reads data from, in one settings list — what each does for the site on the
  left, its action on the right. Plausible and Search Console are set in the
  application's configuration and shown in Content SEO; webhooks are managed
  here (`BrandoAdmin.Sites.WebhooksLive`), and so are notification routes
  (`BrandoAdmin.Sites.NotificationsLive`) and connected AI tools
  (`BrandoAdmin.Sites.MCPLive`).

  The page is for those who may manage webhooks, notifications or connected
  AI tools (`can_open?/1`), and each of those rows only shows to those who
  may manage it. The Plausible and Search Console rows show to anyone who can open it.
  """
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias Brando.MCP
  alias Brando.Notifications.Routing
  alias Brando.SEO.Analytics
  alias Brando.Webhooks
  alias BrandoAdmin.Components.Workspace

  on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, __MODULE__}})

  # Either of two permissions opens the page, which one requirement cannot
  # say: the route asks for backend access, and `mount/3` for the rest.
  def __authorization__, do: {:access, :backend}

  @doc """
  Whether `user` may open Integrations in the current site environment: they
  may manage webhooks (`brando.webhooks.manage`), notification routes
  (`brando.notifications.manage`) or connected AI tools
  (`brando.mcp.manage`). Without group authorization, the admin and
  superuser roles.
  """
  def can_open?(user),
    do: Webhooks.can_manage?(user) or Routing.can_manage?(user) or MCP.can_manage_here?(user)

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    tenant = MCP.tenant(socket.assigns[:current_site], socket.assigns[:current_environment])
    webhooks? = Webhooks.can_manage?(user)
    notifications? = Routing.can_manage?(user)

    if webhooks? or notifications? or MCP.can_manage?(user, tenant) do
      if connected?(socket) and webhooks?, do: Phoenix.PubSub.subscribe(Brando.pubsub(), Webhooks.topic())
      if connected?(socket) and notifications?, do: Phoenix.PubSub.subscribe(Brando.pubsub(), Routing.topic())

      {:ok,
       socket
       |> assign(:socket_connected, connected?(socket))
       |> assign(:page_title, gettext("Integrations"))
       |> assign(:plausible?, Analytics.Plausible.configured?())
       |> assign(:search_console?, Analytics.SearchConsole.configured?())
       |> assign(:webhooks?, webhooks?)
       |> assign(:notifications?, notifications?)
       |> assign_mcp(tenant)
       |> assign_webhooks()
       |> assign_notifications()}
    else
      {:ok, redirect(socket, to: "/admin/access-denied")}
    end
  end

  # Webhooks, for those who may manage them
  defp assign_webhooks(%{assigns: %{webhooks?: true}} = socket), do: assign(socket, :webhooks, Webhooks.summary())
  defp assign_webhooks(socket), do: assign(socket, :webhooks, nil)

  # Notification routes, for those who may manage them
  defp assign_notifications(%{assigns: %{notifications?: true}} = socket),
    do: assign(socket, :notifications, Routing.summary())

  defp assign_notifications(socket), do: assign(socket, :notifications, nil)

  # Connected AI tools (`Brando.MCP`), for those who may manage them
  defp assign_mcp(socket, tenant) do
    if MCP.can_manage?(socket.assigns.current_user, tenant) do
      assign(socket, :mcp, %{enabled?: MCP.enabled?(tenant), count: length(MCP.list_grants(tenant))})
    else
      assign(socket, :mcp, nil)
    end
  end

  def handle_info({Webhooks, _message}, socket), do: {:noreply, assign_webhooks(socket)}
  def handle_info({Routing, _message}, socket), do: {:noreply, assign_notifications(socket)}

  def render(assigns) do
    assigns =
      assign(assigns,
        connected: connected_rows(assigns),
        not_set_up: not_set_up_rows(assigns)
      )

    ~H"""
    <div class="admin-workspace integrations-workspace">
      <Workspace.header
        eyebrow={gettext("Configuration")}
        title={gettext("Integrations")}
        subtitle={gettext("Services this site sends content to or reads data from.")}
      />

      <div class="integrations-list" data-testid="integrations-list">
        <section :if={@connected != []} aria-labelledby="integrations-connected">
          <h2 id="integrations-connected" class="integrations-group">{gettext("Connected")}</h2>
          <.row
            :for={row <- @connected}
            row={row}
            on
            webhooks={@webhooks}
            notifications={@notifications}
            mcp={@mcp}
          />
        </section>
        <section :if={@not_set_up != []} aria-labelledby="integrations-not-set-up">
          <h2 id="integrations-not-set-up" class="integrations-group">{gettext("Not set up")}</h2>
          <.row
            :for={row <- @not_set_up}
            row={row}
            on={false}
            webhooks={@webhooks}
            notifications={@notifications}
            mcp={@mcp}
          />
        </section>
      </div>
    </div>
    """
  end

  defp connected_rows(assigns) do
    Enum.filter(rows(assigns), &on?(&1, assigns))
  end

  defp not_set_up_rows(assigns) do
    Enum.reject(rows(assigns), &on?(&1, assigns))
  end

  defp rows(assigns) do
    [:plausible, :search_console] ++
      if(assigns.webhooks, do: [:webhooks], else: []) ++
      if(assigns.notifications, do: [:notifications], else: []) ++
      if(assigns.mcp, do: [:mcp], else: [])
  end

  defp on?(:plausible, assigns), do: assigns.plausible?
  defp on?(:search_console, assigns), do: assigns.search_console?
  defp on?(:webhooks, assigns), do: assigns.webhooks.count > 0
  defp on?(:notifications, assigns), do: assigns.notifications.count > 0
  defp on?(:mcp, assigns), do: assigns.mcp.enabled?

  attr :row, :atom, required: true
  attr :on, :boolean, default: false
  attr :webhooks, :map, default: nil
  attr :notifications, :map, default: nil
  attr :mcp, :map, default: nil

  defp row(%{row: :plausible} = assigns) do
    ~H"""
    <article class="integrations-row" id="integration-plausible">
      <span class="integrations-icon" aria-hidden="true"><.icon name="chart-line" /></span>
      <div class="integrations-text">
        <h3>
          Plausible <span :if={@on} class="workspace-badge positive">{gettext("Connected")}</span>
        </h3>
        <p :if={@on}>{gettext("Visitors per entry, in Content SEO.")}</p>
        <p :if={!@on}>
          {gettext("Visitors per entry, in Content SEO. A developer sets it up in the site's configuration.")}
        </p>
      </div>
      <div :if={@on} class="integrations-actions">
        <.link navigate="/admin/config/seo?tab=content" class="workspace-button">{gettext("Content SEO")}</.link>
      </div>
    </article>
    """
  end

  defp row(%{row: :search_console} = assigns) do
    ~H"""
    <article class="integrations-row" id="integration-search-console">
      <span class="integrations-icon" aria-hidden="true"><.icon name="search" /></span>
      <div class="integrations-text">
        <h3>
          Google Search Console <span :if={@on} class="workspace-badge positive">{gettext("Connected")}</span>
        </h3>
        <p :if={@on}>{gettext("Searches, clicks and impressions per entry, in Content SEO.")}</p>
        <p :if={!@on}>
          {gettext(
            "Searches, clicks and impressions per entry, in Content SEO. A developer sets it up in the site's configuration."
          )}
        </p>
      </div>
      <div :if={@on} class="integrations-actions">
        <.link navigate="/admin/config/seo?tab=content" class="workspace-button">{gettext("Content SEO")}</.link>
      </div>
    </article>
    """
  end

  defp row(%{row: :mcp} = assigns) do
    ~H"""
    <article class="integrations-row" id="integration-mcp" data-testid="integration-mcp">
      <span class="integrations-icon" aria-hidden="true"><.icon name="bot" /></span>
      <div class="integrations-text">
        <h3>
          {gettext("Connected AI tools")}
          <span :if={@on} class="workspace-badge positive">{gettext("On")}</span>
          <span :if={@mcp.count > 0} class="workspace-badge">
            {ngettext("%{count} connection", "%{count} connections", @mcp.count)}
          </span>
        </h3>
        <p>
          {gettext(
            "Claude, ChatGPT and other MCP clients read content and propose changes, as the person who connected them."
          )}
        </p>
      </div>
      <div class="integrations-actions">
        <.link navigate="/admin/config/mcp" class="workspace-button" data-testid="integration-mcp-manage">
          {if @on, do: gettext("Manage"), else: gettext("Set up")}
        </.link>
      </div>
    </article>
    """
  end

  defp row(%{row: :webhooks} = assigns) do
    ~H"""
    <article class="integrations-row" id="integration-webhooks" data-testid="integration-webhooks">
      <span class="integrations-icon" aria-hidden="true"><.icon name="webhook" /></span>
      <div class="integrations-text">
        <h3>
          {gettext("Webhooks")}
          <span :if={@webhooks.count > 0} class="workspace-badge">
            {ngettext("%{count} webhook", "%{count} webhooks", @webhooks.count)}
          </span>
        </h3>
        <p :if={@webhooks.count == 0}>
          {gettext("Tell other systems when content is published or changes, with a signed request.")}
        </p>
        <p :if={@webhooks.count > 0} data-testid="integration-webhooks-status">
          <span :if={@webhooks.latest}>
            {gettext("Last delivery %{time} to %{webhook}",
              time: BrandoAdmin.Dates.clock(@webhooks.latest.completed_at),
              webhook: @webhooks.latest.webhook.name
            )}
          </span>
          <span :if={!@webhooks.latest}>{gettext("Nothing sent yet")}</span>
          <span :if={@webhooks.failed > 0}>
            · {ngettext("%{count} failed in 24 h", "%{count} failed in 24 h", @webhooks.failed)}<span :if={
              @webhooks.retrying > 0
            }>, {gettext("retrying")}</span>
          </span>
        </p>
      </div>
      <div class="integrations-actions">
        <.link :if={@webhooks.count > 0} navigate="/admin/config/webhooks/deliveries" class="workspace-button">
          {gettext("Delivery log")}
        </.link>
        <.link :if={@webhooks.count == 0} navigate="/admin/config/webhooks/new" class="workspace-button">
          {gettext("Set up")}
        </.link>
        <.link navigate="/admin/config/webhooks" class="workspace-button">{gettext("Manage")}</.link>
      </div>
    </article>
    """
  end

  defp row(%{row: :notifications} = assigns) do
    ~H"""
    <article class="integrations-row" id="integration-notifications" data-testid="integration-notifications">
      <span class="integrations-icon" aria-hidden="true"><.icon name="bell" /></span>
      <div class="integrations-text">
        <h3>
          {gettext("Notifications")}
          <span :if={@notifications.count > 0} class="workspace-badge">
            {ngettext("%{count} route", "%{count} routes", @notifications.count)}
          </span>
        </h3>
        <p :if={@notifications.count == 0}>
          {gettext("Tell people in Slack, Microsoft Teams or by email about mentions, scheduled publishing and failed jobs.")}
        </p>
        <p :if={@notifications.count > 0} data-testid="integration-notifications-status">
          <span :if={@notifications.latest}>
            {gettext("Last sent %{time} on %{route}",
              time: BrandoAdmin.Dates.clock(@notifications.latest.completed_at),
              route: @notifications.latest.route.name
            )}
          </span>
          <span :if={!@notifications.latest}>{gettext("Nothing sent yet")}</span>
          <span :if={@notifications.failed > 0}>
            · {ngettext("%{count} failed in 24 h", "%{count} failed in 24 h", @notifications.failed)}
          </span>
        </p>
      </div>
      <div class="integrations-actions">
        <.link
          :if={@notifications.count > 0}
          navigate="/admin/config/notifications/deliveries"
          class="workspace-button"
        >
          {gettext("Delivery log")}
        </.link>
        <.link
          :if={@notifications.count == 0}
          navigate="/admin/config/notifications/new"
          class="workspace-button"
          data-testid="integration-notifications-set-up"
        >
          {gettext("Set up")}
        </.link>
        <.link navigate="/admin/config/notifications" class="workspace-button" data-testid="integration-notifications-manage">
          {gettext("Manage")}
        </.link>
      </div>
    </article>
    """
  end
end
