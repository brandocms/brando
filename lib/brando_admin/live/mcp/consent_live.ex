defmodule BrandoAdmin.MCP.ConsentLive do
  @moduledoc false
  # The OAuth consent screen of the remote MCP endpoint (`Brando.MCP`). A
  # client sends the person here (through `/mcp/…/oauth/authorize`) to let
  # it read content and propose changes as them in one site environment.
  #
  # `Brando.MCP.ConsentPlug` puts it out of reach of frames and of visitors
  # who are not signed in. People who may not connect tools see why, and
  # nothing is fetched for them. For the others, the client's metadata
  # document is fetched and checked, and the screen names the client, the
  # host behind its name, where it sends them back to, the site environment
  # and what it can do. Allow asks for the password, a code or a passkey
  # when the session has not given one lately (`BrandoAdmin.Reauth`), checks
  # everything again, and only then issues a code. Nothing is approved
  # without the click.
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias Brando.MCP.ClientMetadata
  alias Brando.MCP.OAuth
  alias BrandoAdmin.Components.Workspace

  on_mount({BrandoAdmin.Reauth, events: ~w(approve)})

  def __authorization__, do: {:access, :backend}

  def render(assigns) do
    ~H"""
    <div class="admin-workspace security-workspace mcp-consent-workspace" data-testid="mcp-consent" data-state={@state}>
      <Workspace.header eyebrow={gettext("Connected AI tools")} title={title(@state, @request)} icon="plug" />

      <section :if={@state == :consent} class="workspace-panel security-panel mcp-consent">
        <header class="workspace-panel-heading">
          <div>
            <h2 data-testid="mcp-consent-client">{@request.client.client_name}</h2>
            <p>
              {gettext(
                "Published by %{host}. Brando cannot check that the name is true: allow it only if you started this in %{client}.",
                host: @request.client.host,
                client: @request.client.client_name
              )}
            </p>
          </div>
        </header>

        <dl class="mcp-consent-facts">
          <div>
            <dt>{gettext("Site")}</dt>
            <dd data-testid="mcp-consent-site">{site_label(@request.tenant)}</dd>
          </div>
          <div>
            <dt>{gettext("As")}</dt>
            <dd>{@current_user.name} · {@current_user.email}</dd>
          </div>
          <div>
            <dt>{gettext("Returns to")}</dt>
            <dd>
              <code>{redirect_host(@request.redirect_uri)}</code>
              <span :if={ClientMetadata.loopback?(@request.redirect_uri)} class="mcp-consent-warning">
                {gettext("A program on this computer. Any program here can claim a name: allow it only if you started it.")}
              </span>
            </dd>
          </div>
        </dl>

        <div class="mcp-consent-scope">
          <div>
            <h3>{gettext("It can")}</h3>
            <ul>
              <li>{gettext("Read the content types, entries, modules and media you can edit in this site")}</li>
              <li>
                {gettext("Propose changes. You review and approve them in Brando, under Assistant → From connected tools")}
              </li>
            </ul>
          </div>
          <div>
            <h3>{gettext("It cannot")}</h3>
            <ul>
              <li>{gettext("Save, publish or delete anything")}</li>
              <li>{gettext("Reach other sites or environments")}</li>
            </ul>
          </div>
        </div>

        <footer class="mcp-consent-footer">
          <p>{gettext("You can disconnect it at any time, under Security → Connected apps.")}</p>
          <div class="mcp-consent-actions">
            <button type="button" class="workspace-button" phx-click="deny" data-testid="mcp-consent-deny">
              {gettext("Cancel")}
            </button>
            <button
              type="button"
              class="workspace-button primary"
              phx-click="approve"
              phx-disable-with={gettext("Connecting...")}
              data-testid="mcp-consent-approve"
            >
              {gettext("Allow")}
            </button>
          </div>
        </footer>
      </section>

      <section :if={@state == :refused} class="workspace-panel security-panel mcp-consent" data-testid="mcp-refusal">
        <header class="workspace-panel-heading">
          <div>
            <h2>{gettext("This app cannot be connected")}</h2>
            <p>{refusal(@reason)}</p>
          </div>
          <span class="workspace-badge negative">{gettext("Not allowed")}</span>
        </header>
        <dl class="mcp-consent-facts">
          <div>
            <dt>{gettext("App")}</dt>
            <dd><code>{@request.client_id |> URI.parse() |> Map.get(:host)}</code></dd>
          </div>
          <div>
            <dt>{gettext("Site")}</dt>
            <dd>{site_label(@request.tenant)}</dd>
          </div>
        </dl>
        <footer class="mcp-consent-footer">
          <p>{refusal_next(@reason)}</p>
          <div class="mcp-consent-actions">
            <.link :if={@reason == :two_factor} navigate="/admin/users/security" class="workspace-button primary">
              {gettext("Set up two-factor authentication")}
            </.link>
            <.link navigate="/admin" class="workspace-button">{gettext("Go to the dashboard")}</.link>
          </div>
        </footer>
      </section>

      <section :if={@state == :error} class="workspace-panel security-panel mcp-consent" data-testid="mcp-consent-error">
        <header class="workspace-panel-heading">
          <div>
            <h2>{gettext("This request cannot be used")}</h2>
            <p>{error(@reason)}</p>
          </div>
        </header>
        <footer class="mcp-consent-footer">
          <p>{gettext("Nothing was connected. Start again from the app.")}</p>
          <div class="mcp-consent-actions">
            <.link navigate="/admin" class="workspace-button">{gettext("Go to the dashboard")}</.link>
          </div>
        </footer>
      </section>
    </div>
    """
  end

  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(socket_connected: connected?(socket), params: params, request: nil, reason: nil)
     |> assign(page_title: gettext("Connect an app"))
     |> check()}
  end

  def handle_event("approve", _params, socket) do
    socket = check(socket)

    case socket.assigns do
      %{state: :consent, request: request, current_user: user} ->
        {:ok, url} = OAuth.approve(request, user)
        {:noreply, redirect(socket, external: url)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("deny", _params, %{assigns: %{state: :consent, request: request}} = socket),
    do: {:noreply, redirect(socket, external: OAuth.deny(request))}

  def handle_event("deny", _params, socket), do: {:noreply, push_navigate(socket, to: "/admin")}

  # Everything about the request and the person is checked from the start,
  # on every mount and before an approval.
  defp check(socket) do
    case OAuth.validate(socket.assigns.params, socket.assigns.current_user) do
      {:ok, request} -> assign(socket, state: :consent, request: request, reason: nil)
      {:error, {:refused, reason, request}} -> assign(socket, state: :refused, request: request, reason: reason)
      {:error, {:page, reason}} -> assign(socket, state: :error, request: nil, reason: reason)
      {:error, {:redirect, url}} -> socket |> assign(state: :redirecting) |> redirect(external: url)
    end
  end

  defp title(:consent, %{client: %{client_name: name}}), do: gettext("Connect %{client}?", client: name)
  defp title(:refused, _request), do: gettext("Connect an app")
  defp title(_state, _request), do: gettext("Connect an app")

  defp site_label(%{site: nil}), do: Brando.config(:app_name) || "Brando"
  defp site_label(%{site: site, environment: environment}), do: "#{site.name} · #{environment.name}"

  defp redirect_host(uri) do
    case URI.parse(uri) do
      %URI{host: host, port: port, scheme: "http"} -> "#{host}:#{port}"
      %URI{host: host} -> host
    end
  end

  defp refusal(:permission),
    do:
      gettext(
        "Your account is not allowed to connect AI tools to this site. An administrator can give you the permission."
      )

  defp refusal(:two_factor),
    do: gettext("Connecting AI tools needs two-factor authentication, which is off for your account.")

  defp refusal(_reason), do: gettext("Your account cannot connect AI tools.")

  defp refusal_next(:two_factor),
    do: gettext("Turn it on under Security, then start again from the app.")

  defp refusal_next(_reason), do: gettext("Nothing was connected.")

  defp error(:invalid_client),
    do: gettext("The app did not identify itself in a way Brando accepts.")

  defp error(:client_unreachable),
    do: gettext("Brando could not read the app's description from its website. Try again in a moment.")

  defp error(:invalid_redirect_uri),
    do: gettext("The app asked to send you back to an address it has not declared.")

  defp error(:rate_limited), do: gettext("Too many attempts. Wait a minute, then start again from the app.")
  defp error(_reason), do: gettext("This MCP endpoint does not exist or is turned off.")
end
