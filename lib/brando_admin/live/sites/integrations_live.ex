defmodule BrandoAdmin.Sites.IntegrationsLive do
  @moduledoc """
  Configuration → Integrations: the services this site sends content to or
  reads data from, in one settings list — what each does for the site on the
  left, its action on the right. Plausible and Search Console are set in the
  application's configuration and shown in Content SEO; webhooks are managed
  here (`BrandoAdmin.Sites.WebhooksLive`).
  """
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias Brando.SEO.Analytics
  alias Brando.Webhooks
  alias BrandoAdmin.Components.Workspace

  on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, __MODULE__}})

  def __authorization__, do: {:manage, :webhooks}

  def mount(_params, _session, socket) do
    if Webhooks.can_manage?(socket.assigns.current_user) do
      if connected?(socket), do: Phoenix.PubSub.subscribe(Brando.pubsub(), Webhooks.topic())

      {:ok,
       socket
       |> assign(:socket_connected, connected?(socket))
       |> assign(:page_title, gettext("Integrations"))
       |> assign(:plausible?, Analytics.Plausible.configured?())
       |> assign(:search_console?, Analytics.SearchConsole.configured?())
       |> assign_webhooks()}
    else
      {:ok, redirect(socket, to: "/admin/access-denied")}
    end
  end

  defp assign_webhooks(socket), do: assign(socket, :webhooks, Webhooks.summary())

  def handle_info({Webhooks, _message}, socket), do: {:noreply, assign_webhooks(socket)}

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
          <.row :for={row <- @connected} row={row} on webhooks={@webhooks} />
        </section>
        <section :if={@not_set_up != []} aria-labelledby="integrations-not-set-up">
          <h2 id="integrations-not-set-up" class="integrations-group">{gettext("Not set up")}</h2>
          <.row :for={row <- @not_set_up} row={row} on={false} webhooks={@webhooks} />
        </section>
      </div>
    </div>
    """
  end

  defp connected_rows(assigns) do
    Enum.filter([:plausible, :search_console, :webhooks], &on?(&1, assigns))
  end

  defp not_set_up_rows(assigns) do
    Enum.reject([:plausible, :search_console, :webhooks], &on?(&1, assigns))
  end

  defp on?(:plausible, assigns), do: assigns.plausible?
  defp on?(:search_console, assigns), do: assigns.search_console?
  defp on?(:webhooks, assigns), do: assigns.webhooks.count > 0

  attr :row, :atom, required: true
  attr :on, :boolean, default: false
  attr :webhooks, :map, required: true

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
end
