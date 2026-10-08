defmodule BrandoAdmin.Sites.MCPLive do
  @moduledoc """
  Configuration → Integrations → Connected AI tools: the switch for the
  remote MCP endpoint of the current site environment, its URL, and every
  connection people have made to it, with a revoke button for each.

  For people who may manage connections (`Brando.MCP.can_manage?/2`).
  Turning the endpoint on or off and revoking ask for the password, a code
  or a passkey when the session has not given one lately
  (`BrandoAdmin.Reauth`).
  """
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias Brando.MCP
  alias BrandoAdmin.Components.Workspace
  alias BrandoAdmin.Toast

  on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, __MODULE__}})
  on_mount({BrandoAdmin.Reauth, events: ~w(enable disable revoke)})

  def __authorization__, do: {:manage, :mcp}

  def render(assigns) do
    ~H"""
    <div class="admin-workspace integrations-workspace mcp-workspace" data-testid="mcp-settings">
      <.link navigate="/admin/config/integrations" class="integrations-back">
        <.icon name="arrow-left" />{gettext("Integrations")}
      </.link>
      <Workspace.header
        eyebrow={gettext("Configuration")}
        title={gettext("Connected AI tools")}
        subtitle={
          gettext(
            "Let people connect Claude, ChatGPT and other MCP clients to this site, to read content and propose changes they approve here."
          )
        }
      />

      <div class="integrations-list">
        <section aria-labelledby="mcp-endpoint-heading">
          <h2 id="mcp-endpoint-heading" class="integrations-group">{gettext("MCP endpoint")}</h2>
          <article class="integrations-row" id="mcp-switch" data-testid="mcp-switch" data-enabled={to_string(@enabled?)}>
            <span class="integrations-icon" aria-hidden="true"><.icon name="plug" /></span>
            <div class="integrations-text">
              <h3>
                {site_label(@tenant)}
                <span class={["workspace-badge", @enabled? && "positive"]} data-testid="mcp-status">
                  {if @enabled?, do: gettext("On"), else: gettext("Off")}
                </span>
              </h3>
              <p :if={@enabled?}>
                {gettext(
                  "People with the Connected AI tools permission and two-factor authentication can connect. Turning it off stops every connection at once; they work again when it is back on."
                )}
              </p>
              <p :if={!@enabled?}>
                {gettext(
                  "Off: the endpoint, its sign-in and its metadata answer as if they did not exist. Nothing reaches this site over MCP."
                )}
              </p>
            </div>
            <div class="integrations-actions">
              <button
                :if={!@enabled?}
                type="button"
                class="workspace-button primary"
                phx-click="enable"
                disabled={!@mounted? or !@secure?}
                data-testid="mcp-enable"
                data-confirm-title={gettext("Turn the MCP endpoint on?")}
                data-confirm={
                  gettext(
                    "People who may connect AI tools can then let them read this site's content and propose changes, as themselves."
                  )
                }
                data-confirm-ok={gettext("Turn on")}
              >
                {gettext("Turn on")}
              </button>
              <button
                :if={@enabled?}
                type="button"
                class="workspace-button destructive"
                phx-click="disable"
                data-testid="mcp-disable"
                data-confirm-title={gettext("Turn the MCP endpoint off?")}
                data-confirm={
                  gettext(
                    "Every connected tool stops working at once. The connections stay, and work again when you turn it back on."
                  )
                }
                data-confirm-ok={gettext("Turn off")}
                data-confirm-destructive
              >
                {gettext("Turn off")}
              </button>
            </div>
          </article>
          <article :if={@enabled?} class="integrations-row plain">
            <div class="integrations-text">
              <h3>{gettext("Server URL")}</h3>
              <p>{gettext("Paste this into the app as the MCP server's URL.")}</p>
              <div class="mcp-url">
                <input
                  type="text"
                  id="mcp-url"
                  value={MCP.resource(@tenant)}
                  readonly
                  aria-label={gettext("Server URL")}
                  data-testid="mcp-url"
                />
              </div>
            </div>
          </article>
          <article :if={!@mounted?} class="integrations-row plain" data-testid="mcp-not-mounted">
            <div class="integrations-text">
              <h3>{gettext("Not available in this installation")}</h3>
              <p>{gettext("A developer adds mcp_routes() to the application's router first. See the MCP guide.")}</p>
            </div>
          </article>
          <article :if={@mounted? and !@secure?} class="integrations-row plain">
            <div class="integrations-text">
              <h3>{gettext("Needs https")}</h3>
              <p>{gettext("The site's address must use https before the endpoint can be turned on.")}</p>
            </div>
          </article>
        </section>
      </div>

      <section class="workspace-panel mcp-grants" data-testid="mcp-grants">
        <header class="workspace-panel-heading">
          <div>
            <h2>{gettext("Connections")}</h2>
            <p>{gettext("Tools people have connected to this site. Revoking one stops it at once.")}</p>
          </div>
          <span>{ngettext("%{count} connection", "%{count} connections", length(@grants))}</span>
        </header>
        <Workspace.empty
          :if={@grants == []}
          title={gettext("No connections")}
          description={gettext("When someone connects an app, it is listed here with who connected it.")}
        />
        <div :if={@grants != []} class="workspace-table-scroll">
          <table class="workspace-table mcp-grants-table">
            <thead>
              <tr>
                <th scope="col">{gettext("App")}</th>
                <th scope="col">{gettext("Person")}</th>
                <th scope="col">{gettext("Connected")}</th>
                <th scope="col">{gettext("Last used")}</th>
                <th scope="col"><span class="workspace-sr-only">{gettext("Actions")}</span></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={grant <- @grants} data-testid="mcp-grant" data-id={grant.id}>
                <td>
                  {grant.client_name}
                  <small><code>{URI.parse(grant.client_id).host}</code></small>
                </td>
                <td>
                  {grant.user && grant.user.name}
                  <small>{grant.user && grant.user.email}</small>
                </td>
                <td><time datetime={DateTime.to_iso8601(grant.inserted_at)}>{date(grant.inserted_at)}</time></td>
                <td>{if grant.last_used_at, do: date(grant.last_used_at), else: gettext("Not used yet")}</td>
                <td class="row-actions">
                  <button
                    type="button"
                    class="workspace-button destructive"
                    phx-click="revoke"
                    phx-value-id={grant.id}
                    data-testid="mcp-grant-revoke"
                    data-confirm-title={gettext("Revoke %{client}?", client: grant.client_name)}
                    data-confirm={
                      gettext("It stops working at once. %{name} can connect it again.", name: grant.user && grant.user.name)
                    }
                    data-confirm-ok={gettext("Revoke")}
                    data-confirm-destructive
                  >
                    {gettext("Revoke")}
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

  def mount(_params, _session, socket) do
    tenant = MCP.tenant(socket.assigns[:current_site], socket.assigns[:current_environment])

    if MCP.can_manage?(socket.assigns.current_user, tenant) do
      {:ok,
       socket
       |> assign(
         socket_connected: connected?(socket),
         page_title: gettext("Connected AI tools"),
         tenant: tenant,
         mounted?: MCP.mounted?(),
         secure?: MCP.secure_base?()
       )
       |> load()}
    else
      {:ok, redirect(socket, to: "/admin/access-denied")}
    end
  end

  defp load(socket) do
    tenant = socket.assigns.tenant
    assign(socket, enabled?: MCP.enabled?(tenant), grants: MCP.list_grants(tenant))
  end

  def handle_event("enable", _params, socket), do: {:noreply, toggle(socket, true)}
  def handle_event("disable", _params, socket), do: {:noreply, toggle(socket, false)}

  def handle_event("revoke", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case MCP.revoke(id, user, "admin") do
      :ok -> Toast.send_to(user, gettext("The connection was revoked."))
      {:error, _} -> Toast.send_to(user, gettext("That connection is gone already."), %{level: :error})
    end

    {:noreply, load(socket)}
  end

  defp toggle(socket, enabled?) do
    %{current_user: user, tenant: tenant} = socket.assigns

    case MCP.set_enabled(tenant, enabled?, user) do
      :ok ->
        Toast.send_to(
          user,
          if(enabled?, do: gettext("The MCP endpoint is on."), else: gettext("The MCP endpoint is off."))
        )

      {:error, _reason} ->
        Toast.send_to(user, gettext("The MCP endpoint could not be changed."), %{level: :error})
    end

    load(socket)
  end

  defp site_label(%{site: nil}), do: Brando.config(:app_name) || "Brando"
  defp site_label(%{site: site, environment: environment}), do: "#{site.name} · #{environment.name}"

  defp date(datetime), do: Brando.Utils.Datetime.format_datetime(datetime, "%-d %B %Y, %H:%M")
end
