defmodule BrandoAdmin.Sites.MCPLive do
  @moduledoc """
  Configuration → Integrations → Connected AI tools: the switch for the
  remote MCP endpoint of the current site environment, its URL, the Figma
  token its tools read Figma with (`Brando.Figma`), the guidance for
  building from Figma that `brando_figma_read_frame` returns
  (`Brando.AI.Agent.Guidance`, kind `:figma`), and every connection people
  have made to it, with a revoke button for each.

  The guidance is edited by those who may configure the assistant
  (`Brando.AI.Agent.Guidance.configurable?/1`), as the assistant's guidance
  is; others see it read-only. Every save is a version.

  For people who may manage connections (`Brando.MCP.can_manage?/2`).
  Turning the endpoint on or off, adding or removing the Figma token and
  revoking ask for the password, a code or a passkey when the session has
  not given one lately (`BrandoAdmin.Reauth`). The token is never shown
  again once saved: only its last four characters.

  Once the page is up it asks Figma about the token (`Brando.Figma.check/1`,
  without holding the page up), and Test asks again. The expiry date given
  with the token shows under it, as a warning in its last week and after it.
  """
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias Brando.AI.Agent.Guidance
  alias Brando.Figma
  alias Brando.MCP
  alias BrandoAdmin.Components.Workspace
  alias BrandoAdmin.Toast

  on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, __MODULE__}})
  on_mount({BrandoAdmin.Reauth, events: ~w(enable disable revoke save_figma_token remove_figma_token)})

  def __authorization__, do: {:manage, :mcp}

  # The expiry the token form suggests: Figma's longest
  @figma_default_days 90

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
            <span class="integrations-icon" aria-hidden="true"><.icon name="bot" /></span>
            <div class="integrations-text">
              <h3>
                {site_label(@tenant)}
                <span class={["badge", @enabled? && "badge--success"]} data-testid="mcp-status">
                  {if @enabled?, do: gettext("On"), else: gettext("Off")}
                </span>
              </h3>
              <p :if={@enabled?}>
                {gettext(
                  "People with the Connected AI tools permission and two-factor authentication can connect. Turning it off disconnects every connected app at once."
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
                class="btn btn--primary"
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
                class="btn btn--danger"
                phx-click="disable"
                data-testid="mcp-disable"
                data-confirm-title={gettext("Turn the MCP endpoint off?")}
                data-confirm={
                  ngettext(
                    "This disconnects %{count} connected app. Its person can connect it again once the endpoint is back on.",
                    "This disconnects %{count} connected apps. Their people can connect them again once the endpoint is back on.",
                    length(@grants)
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

        <section aria-labelledby="mcp-figma-heading">
          <h2 id="mcp-figma-heading" class="integrations-group">{gettext("Figma")}</h2>
          <article class="integrations-row" id="mcp-figma" data-testid="mcp-figma">
            <span class="integrations-icon" aria-hidden="true"><.icon name="frame" /></span>
            <div class="integrations-text">
              <h3>
                {gettext("Figma access token")}
                <span :if={@figma && @figma.readable} class="badge badge--success" data-testid="mcp-figma-status">
                  {gettext("Added")}
                </span>
                <span
                  :if={@figma && !@figma.readable}
                  class="badge badge--attention"
                  data-testid="mcp-figma-unreadable"
                >
                  {gettext("Cannot be read")}
                </span>
              </h3>
              <p>
                {gettext(
                  "Connected tools read a Figma frame from its link and import its images into the media library, in a folder named after the frame. They see the Figma files the token's owner can open."
                )}
              </p>
              <p :if={@figma} data-testid="mcp-figma-hint">
                {figma_added(@figma)}
              </p>
              <.figma_check :if={@figma && @figma.readable && @figma_check} check={@figma_check} />
              <.figma_expiry :if={@figma} expiry={Figma.expiry(@figma.expires_on, @today)} />
              <p :if={@figma && !@figma.readable}>
                {gettext(
                  "It can no longer be decrypted, as after a change of the encryption secret, so the tools cannot reach Figma. Replace it."
                )}
              </p>
              <form
                :if={!@figma or @figma_form?}
                class="mcp-figma-form"
                phx-submit="save_figma_token"
                data-testid="mcp-figma-form"
              >
                <input
                  type="password"
                  name="token"
                  autocomplete="off"
                  spellcheck="false"
                  required
                  placeholder="figd_…"
                  aria-label={gettext("Figma access token")}
                  aria-describedby="mcp-figma-help"
                  data-testid="mcp-figma-token"
                />
                <label class="mcp-figma-expires">
                  <span>{gettext("Expires")}</span>
                  <input
                    type="date"
                    name="expires_on"
                    value={Date.to_iso8601(Date.add(@today, @figma_default_days))}
                    min={Date.to_iso8601(@today)}
                    aria-describedby="mcp-figma-help"
                    data-testid="mcp-figma-expires-on"
                  />
                </label>
                <button type="submit" class="btn btn--primary" data-testid="mcp-figma-save">
                  {gettext("Save token")}
                </button>
                <button
                  :if={@figma}
                  type="button"
                  class="btn"
                  phx-click="cancel_figma_token"
                  data-testid="mcp-figma-cancel"
                >
                  {gettext("Cancel")}
                </button>
                <small id="mcp-figma-help">
                  {gettext(
                    "In Figma: Settings → Security → Personal access tokens, with the scopes File content: read (file_content:read) and Current user: read (current_user:read), which checking the token needs. Use the account of someone with a Full or Dev seat: Figma limits API calls for other seats."
                  )}
                  {gettext(
                    "Figma does not tell Brando when a token expires: give the expiry you chose in Figma, at most 90 days ahead, so this page can warn a week before. Leave it empty if you do not know it."
                  )}
                </small>
              </form>
            </div>
            <div :if={@figma && !@figma_form?} class="integrations-actions">
              <button
                :if={@figma.readable}
                type="button"
                class="btn btn--quiet"
                phx-click="test_figma_token"
                disabled={@figma_check == :checking}
                data-testid="mcp-figma-test"
              >
                {gettext("Test")}
              </button>
              <button type="button" class="btn" phx-click="replace_figma_token" data-testid="mcp-figma-replace">
                {gettext("Replace")}
              </button>
              <button
                type="button"
                class="btn btn--danger"
                phx-click="remove_figma_token"
                data-testid="mcp-figma-remove"
                data-confirm-title={gettext("Remove the Figma token?")}
                data-confirm={
                  gettext("Connected tools can then no longer read Figma. Images already imported stay in the media library.")
                }
                data-confirm-ok={gettext("Remove")}
                data-confirm-destructive
              >
                {gettext("Remove")}
              </button>
            </div>
          </article>
          <.figma_guidance guidance={@figma_guidance} />
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
                  <span :if={MCP.grant_expired?(grant)} class="badge badge--attention" data-testid="mcp-grant-expired">
                    {gettext("Expired")}
                  </span>
                  <small><code>{URI.parse(grant.client_id).host}</code></small>
                </td>
                <td>
                  {grant.user && grant.user.name}
                  <small>{grant.user && grant.user.email}</small>
                </td>
                <td data-label={gettext("Connected")}>
                  <time datetime={DateTime.to_iso8601(grant.inserted_at)}>{date(grant.inserted_at)}</time>
                </td>
                <td data-label={gettext("Last used")}>
                  {if grant.last_used_at, do: date(grant.last_used_at), else: gettext("Not used yet")}
                </td>
                <td class="row-actions">
                  <.link navigate={MCP.Watch.path(grant)} class="btn btn--quiet" data-testid="mcp-grant-watch">
                    {gettext("Follow live")}
                  </.link>
                  <button
                    type="button"
                    class="btn btn--danger"
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

  # What Figma said of the token when the page asked (`Brando.Figma.check/1`)
  attr :check, :any, required: true

  defp figma_check(assigns) do
    ~H"""
    <p class="mcp-figma-check" data-testid="mcp-figma-check" data-state={check_state(@check)}>
      <span class={["badge", check_tone(@check)]}>{check_label(@check)}</span>
      <span :if={check_text(@check)}>{check_text(@check)}</span>
    </p>
    """
  end

  defp check_state({state, _detail}), do: to_string(state)
  defp check_state(state), do: to_string(state)

  defp check_tone({:valid, _handle}), do: "badge--success"
  defp check_tone({state, _err}) when state in [:expired, :invalid], do: "badge--error"
  defp check_tone(_check), do: nil

  defp check_label({:valid, _handle}), do: gettext("Valid")
  defp check_label({:expired, _err}), do: gettext("Expired")
  defp check_label({:invalid, _err}), do: gettext("Not valid")
  defp check_label({:no_account_scope, _err}), do: gettext("Not checked")
  defp check_label(:unreachable), do: gettext("Not checked")
  defp check_label(_checking), do: gettext("Checking with Figma…")

  defp check_text({:valid, nil}), do: gettext("Figma accepts it.")
  defp check_text({:valid, handle}), do: gettext("Figma accepts it, for the account %{handle}.", handle: handle)
  defp check_text({:expired, _err}), do: gettext("Figma says it has expired. Replace it.")
  defp check_text({:invalid, nil}), do: gettext("Figma does not accept it. Replace it.")

  defp check_text({:invalid, err}),
    do: gettext("Figma does not accept it. Replace it. Figma said: “%{error}”", error: err)

  defp check_text({:no_account_scope, _err}),
    do:
      gettext(
        "It may not read its own Figma account (the current_user:read scope), so it could not be checked. It may still read files. For the check, replace it with a token that also has current_user:read."
      )

  defp check_text(:unreachable), do: gettext("Figma could not be reached to check it. Try again in a moment.")
  defp check_text(_checking), do: nil

  # The expiry date recorded with the token (`Brando.Figma.expiry/2`)
  attr :expiry, :any, required: true

  defp figma_expiry(assigns) do
    ~H"""
    <p
      class={["mcp-figma-expiry", warning?(@expiry) && "is-warning"]}
      data-testid="mcp-figma-expiry"
      data-expiry={expiry_state(@expiry)}
    >
      {expiry_text(@expiry)}
    </p>
    """
  end

  defp warning?({state, _date, _days}), do: state == :soon
  defp warning?({state, _date}), do: state == :passed
  defp warning?(_expiry), do: false

  defp expiry_state(expiry) when is_atom(expiry), do: to_string(expiry)
  defp expiry_state(expiry), do: expiry |> elem(0) |> to_string()

  defp expiry_text(:not_recorded), do: gettext("Expiry not recorded.")
  defp expiry_text({:later, date}), do: gettext("Expires %{date}.", date: day(date))
  defp expiry_text({:soon, date, 0}), do: gettext("Expires today, %{date}. Replace it now.", date: day(date))

  defp expiry_text({:soon, date, days}),
    do:
      ngettext(
        "Expires %{date}, in %{count} day. Replace it before then.",
        "Expires %{date}, in %{count} days. Replace it before then.",
        days,
        date: day(date)
      )

  defp expiry_text({:passed, date}),
    do: gettext("Its expiry date, %{date}, has passed. Replace it if Figma no longer accepts it.", date: day(date))

  @guidance_max 12_000

  attr :guidance, :map, required: true

  defp figma_guidance(assigns) do
    guidance = assigns.guidance
    saved = (guidance.current && guidance.current.text) || ""
    assigns = assign(assigns, dirty?: guidance.draft != saved, saved: saved, length: String.length(guidance.draft))

    ~H"""
    <article class="integrations-row plain mcp-figma-guidance" id="mcp-figma-guidance" data-testid="mcp-figma-guidance">
      <div class="integrations-text">
        <h3>{gettext("Guidance for building from Figma")}</h3>
        <p>
          {gettext(
            "Connected tools get this with every frame they read: how the design's frames and components map to this site's modules, which texts belong in the entry's own fields, and what to leave out. The content assistant does not use it. Permissions and review still apply."
          )}
        </p>

        <form
          :if={@guidance.editable?}
          id="mcp-figma-guidance-form"
          class="mcp-figma-guidance-form"
          phx-change="figma_guidance_draft"
          phx-submit="save_figma_guidance"
          data-testid="mcp-figma-guidance-form"
        >
          <textarea
            id="mcp-figma-guidance-text"
            name="text"
            rows="8"
            maxlength={@guidance.max}
            phx-debounce="300"
            aria-label={gettext("Guidance for building from Figma")}
            placeholder={
              gettext(
                "For example: The frame's top text is the entry's Heading and Introduction fields, not a Text module. Header and footer are page chrome: leave them out."
              )
            }
          >{@guidance.draft}</textarea>
          <div class="guidance-form-footer">
            <div class="guidance-form-status">
              <span class={["guidance-count", @length > @guidance.max && "is-over"]}>
                {gettext("%{count} of %{max} characters", count: @length, max: @guidance.max)}
              </span>
              <span :if={@guidance.note && @dirty?} class="guidance-note">{@guidance.note}</span>
              <span :if={!@dirty? && @guidance.current} class="guidance-saved" data-testid="mcp-figma-guidance-saved">
                {gettext("Saved %{time} by %{author}",
                  time: timestamp(@guidance.current.inserted_at),
                  author: author(@guidance.current)
                )}
              </span>
            </div>
            <div class="guidance-actions">
              <button :if={@dirty?} type="button" class="btn btn--quiet" phx-click="discard_figma_guidance">
                {gettext("Discard changes")}
              </button>
              <button
                type="submit"
                class="btn btn--primary"
                disabled={!@dirty?}
                phx-disable-with={gettext("Saving…")}
                data-testid="mcp-figma-guidance-save"
              >
                {gettext("Save guidance")}
              </button>
            </div>
          </div>
        </form>

        <div :if={!@guidance.editable?} class="mcp-figma-guidance-readonly" data-testid="mcp-figma-guidance-readonly">
          <pre :if={@saved != ""}>{@saved}</pre>
          <p :if={@saved == ""}>{gettext("None has been written for this site.")}</p>
          <p>{gettext("Only people who may configure the assistant can change it.")}</p>
        </div>

        <details :if={@guidance.code} class="mcp-figma-guidance-more" data-testid="mcp-figma-guidance-code">
          <summary>{gettext("From the site's code")}</summary>
          <p>
            {gettext(
              "Set by the developers in the site's configuration. Where it conflicts with the guidance above, the guidance above applies."
            )}
          </p>
          <pre>{@guidance.code}</pre>
        </details>

        <details
          :if={@guidance.editable? && @guidance.history != []}
          class="mcp-figma-guidance-more"
          data-testid="mcp-figma-guidance-history"
        >
          <summary>{gettext("History")}</summary>
          <ol class="guidance-history">
            <li :for={version <- @guidance.history}>
              <div>
                <strong>{timestamp(version.inserted_at)}</strong>
                <span>{author(version)}</span>
                <span :if={version.note} class="guidance-note">{version.note}</span>
                <p class="guidance-excerpt">{excerpt(version.text)}</p>
              </div>
              <span :if={@guidance.current && version.id == @guidance.current.id} class="badge badge--success">
                {gettext("In use")}
              </span>
              <button
                :if={!(@guidance.current && version.id == @guidance.current.id)}
                type="button"
                class="btn btn--sm"
                phx-click="restore_figma_guidance"
                phx-value-id={version.id}
                data-confirm={@dirty? && gettext("Replace your unsaved changes with this version?")}
              >
                {gettext("Load into editor")}
              </button>
            </li>
          </ol>
        </details>
      </div>
    </article>
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
         secure?: MCP.secure_base?(),
         figma_form?: false,
         figma_check: nil,
         figma_default_days: @figma_default_days,
         today: Figma.today()
       )
       |> load()
       |> check_figma_token()
       |> load_figma_guidance()}
    else
      {:ok, redirect(socket, to: "/admin/access-denied")}
    end
  end

  defp load(socket) do
    tenant = socket.assigns.tenant

    assign(socket,
      enabled?: MCP.enabled?(tenant),
      grants: MCP.list_grants(tenant),
      figma: MCP.figma_token_status(tenant)
    )
  end

  # Asks Figma about the stored token once the page is up: the page does not
  # wait for Figma. The token is read here, in the page's process, and only
  # the call to Figma runs apart.
  defp check_figma_token(socket) do
    with true <- connected?(socket),
         %{readable: true} <- socket.assigns.figma,
         {:ok, token} <- Figma.token(socket.assigns.tenant) do
      socket |> assign(:figma_check, :checking) |> start_async(:figma_check, fn -> Figma.check(token) end)
    else
      _no_token -> assign(socket, :figma_check, nil)
    end
  end

  def handle_async(:figma_check, {:ok, check}, socket), do: {:noreply, assign(socket, :figma_check, check)}
  def handle_async(:figma_check, {:exit, _reason}, socket), do: {:noreply, assign(socket, :figma_check, :unreachable)}

  defp load_figma_guidance(socket) do
    user = socket.assigns.current_user
    editable? = Guidance.configurable?(user)
    current = Guidance.current(:figma)

    history =
      case editable? && Guidance.history(user, kind: :figma, limit: 10) do
        {:ok, history} -> history
        _ -> []
      end

    assign(socket, :figma_guidance, %{
      editable?: editable?,
      current: current,
      draft: (current && current.text) || "",
      note: nil,
      history: history,
      code: Guidance.code_figma_guidance(),
      max: @guidance_max
    })
  end

  defp update_figma_guidance(socket, changes),
    do: assign(socket, :figma_guidance, Map.merge(socket.assigns.figma_guidance, changes))

  def handle_event("figma_guidance_draft", %{"text" => text}, socket),
    do: {:noreply, update_figma_guidance(socket, %{draft: text})}

  def handle_event("discard_figma_guidance", _params, socket),
    do: {:noreply, load_figma_guidance(socket)}

  def handle_event("save_figma_guidance", %{"text" => text}, socket) do
    user = socket.assigns.current_user

    case Guidance.save(text, user, kind: :figma, note: socket.assigns.figma_guidance.note) do
      {:ok, _current} ->
        Toast.send_to(user, gettext("Guidance saved"))
        {:noreply, load_figma_guidance(socket)}

      {:error, message} ->
        Toast.send_to(user, message, %{level: :error})
        {:noreply, socket}
    end
  end

  def handle_event("restore_figma_guidance", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.figma_guidance.history, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      version ->
        note = gettext("Restored the version from %{time}", time: timestamp(version.inserted_at))
        {:noreply, update_figma_guidance(socket, %{draft: version.text, note: note})}
    end
  end

  def handle_event("enable", _params, socket), do: {:noreply, toggle(socket, true)}
  def handle_event("disable", _params, socket), do: {:noreply, toggle(socket, false)}

  def handle_event("replace_figma_token", _params, socket), do: {:noreply, assign(socket, :figma_form?, true)}
  def handle_event("cancel_figma_token", _params, socket), do: {:noreply, assign(socket, :figma_form?, false)}

  def handle_event("test_figma_token", _params, socket), do: {:noreply, check_figma_token(socket)}

  def handle_event("save_figma_token", %{"token" => token} = params, socket) do
    %{current_user: user, tenant: tenant} = socket.assigns

    with {:ok, expires_on} <- expires_on(params["expires_on"]),
         :ok <- MCP.put_figma_token(tenant, token, user, expires_on: expires_on) do
      Toast.send_to(user, gettext("The Figma token was saved."))
      {:noreply, socket |> assign(figma_form?: false, today: Figma.today()) |> load() |> check_figma_token()}
    else
      {:error, :invalid_token} ->
        Toast.send_to(user, gettext("That does not look like a Figma access token."), %{level: :error})
        {:noreply, socket}

      {:error, :invalid_expiry} ->
        Toast.send_to(user, gettext("Give the expiry as a date from today on, or leave it empty."), %{level: :error})
        {:noreply, socket}

      {:error, _reason} ->
        Toast.send_to(user, gettext("The Figma token could not be saved."), %{level: :error})
        {:noreply, socket}
    end
  end

  def handle_event("remove_figma_token", _params, socket) do
    %{current_user: user, tenant: tenant} = socket.assigns

    case MCP.delete_figma_token(tenant, user) do
      :ok -> Toast.send_to(user, gettext("The Figma token was removed."))
      {:error, _reason} -> Toast.send_to(user, gettext("The Figma token could not be removed."), %{level: :error})
    end

    {:noreply, socket |> assign(:figma_form?, false) |> load() |> check_figma_token()}
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case MCP.revoke(id, user, "admin") do
      :ok -> Toast.send_to(user, gettext("The connection was revoked."))
      {:error, _} -> Toast.send_to(user, gettext("That connection is gone already."), %{level: :error})
    end

    {:noreply, load(socket)}
  end

  defp expires_on(value) when value in [nil, ""], do: {:ok, nil}

  defp expires_on(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, :invalid_expiry}
    end
  end

  defp expires_on(_value), do: {:error, :invalid_expiry}

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

  defp figma_added(%{hint: hint, set_at: set_at, set_by: set_by}) do
    cond do
      set_by && set_at ->
        gettext("Ends in %{hint}. Added %{date} by %{name}.", hint: hint, date: date(set_at), name: set_by.name)

      set_at ->
        gettext("Ends in %{hint}. Added %{date}.", hint: hint, date: date(set_at))

      true ->
        gettext("Ends in %{hint}.", hint: hint)
    end
  end

  defp timestamp(datetime), do: BrandoAdmin.Dates.long(datetime)

  defp author(%{author: %{name: name}}) when is_binary(name), do: name
  defp author(_version), do: gettext("Unknown user")

  defp excerpt(""), do: gettext("Cleared")

  defp excerpt(text) do
    line = text |> String.split("\n", trim: true) |> Enum.join(" · ")
    if String.length(line) > 160, do: String.slice(line, 0, 160) <> "…", else: line
  end

  defp date(datetime), do: Brando.Utils.Datetime.format_datetime(datetime, "%-d %B %Y, %H:%M")
  defp day(date), do: Brando.Utils.Datetime.format_datetime(date, "%-d %B %Y")
end
