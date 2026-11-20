defmodule BrandoAdmin.MCP.WatchLive do
  @moduledoc """
  The live page of a connected AI tool (`Brando.MCP.Watch`),
  `/admin/assistant/connected/live/<connection>`: each call the tool makes on
  the site, as it starts and as it ends, with what it was about, whether it
  worked and the error if not; the images an import added to the media
  library or reused, with their folder; and each proposal it stored, with
  its summary, counts, problems and review link.

  It opens on the connection's calls from Activity of the last hour, then
  follows the new ones. Only the connection's person, while active with
  access to its site, and those who may manage connections to its site
  environment (`Brando.MCP.can_manage?/2`) see it, checked again on each
  authorization change; anyone else, and a connection that does not exist,
  get the access-denied page. Once the connection is revoked or expires, the
  page says so and shows what it did.

  The person sees all of it. A manager sees each call's step without what
  it named (the entry's title, the words searched for, the frame and the
  folder), only the images they may read, and a proposal's summary and
  problems only when they may read what it changes, as Activity shows them.
  """
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Content.Proposals.Codec
  alias Brando.Content.Proposals.Record
  alias Brando.Content.Transfer.Catalog
  alias Brando.Images.Image
  alias Brando.MCP
  alias Brando.MCP.Grant
  alias Brando.MCP.Watch
  alias Brando.Repo
  alias Brando.Users.User
  alias BrandoAdmin.Components.ToolSteps
  alias BrandoAdmin.Components.Workspace
  alias BrandoAdmin.Dates

  # Calls kept on the page; older ones leave it
  @limit 100

  # A timer holds 49 days at most: the expiry is looked at again each day
  @expiry_check :timer.hours(24)

  def __authorization__, do: {:access, :backend}

  def mount(%{"grant_id" => id}, %{"user_token" => token}, socket) do
    socket = socket |> BrandoAdmin.Hooks.assign_current_user(token) |> assign(:socket_connected, connected?(socket))
    user = socket.assigns.current_user
    Gettext.put_locale(Brando.Gettext, to_string(user.language))

    case load(id, user) do
      {:ok, grant} ->
        tenant = MCP.grant_tenant(grant)
        live? = live?(grant)
        reader = reader(grant, user, tenant)
        if connected?(socket) and live?, do: Watch.subscribe(grant.id)
        calls = if connected?(socket), do: Watch.history(grant), else: []

        {:ok,
         socket
         |> assign(
           page_title: grant.client_name,
           grant: grant,
           tenant: tenant,
           reader: reader,
           live?: live?,
           loaded?: connected?(socket),
           empty?: calls == [],
           history: MapSet.new(calls, & &1.event_id),
           live_calls: %{}
         )
         |> schedule_expiry()
         |> stream_configure(:calls, dom_id: &dom_id/1)
         |> stream(:calls, rows(calls, tenant, reader), limit: @limit)}

      :error ->
        {:ok, redirect(socket, to: "/admin/access-denied")}
    end
  end

  @doc """
  Sends the viewer away when they may no longer see the connection
  (`BrandoAdmin.Authorization`). Someone other than the connection's person
  stays with the calls read again, as they may read them now.
  """
  def refresh_authorization(%{assigns: %{grant: grant, current_user: user}} = socket) do
    if allowed?(grant, user) do
      reread(socket)
    else
      Watch.unsubscribe(grant.id)
      redirect(socket, to: "/admin/access-denied")
    end
  end

  def refresh_authorization(socket), do: socket

  defp reread(%{assigns: %{reader: nil}} = socket), do: socket

  # Activity has only the calls that ended and were written: the ones this
  # page was told of and Activity has not (running, or not written) are
  # shown again too
  # Every time: a scope is asked what it may read when it is used, so one
  # equal to the last says nothing about what changed
  defp reread(%{assigns: %{grant: grant, tenant: tenant, current_user: user}} = socket) do
    reader = reader(grant, user, tenant)
    history = if connected?(socket), do: Watch.history(grant), else: []
    seen = MapSet.new(history, & &1.event_id)

    calls =
      socket.assigns.live_calls
      |> Map.values()
      |> Enum.reject(&(&1[:event_id] && MapSet.member?(seen, &1.event_id)))
      |> Enum.concat(history)
      |> Enum.sort_by(& &1.at, {:desc, DateTime})
      |> Enum.take(@limit)

    socket
    |> assign(reader: reader, empty?: calls == [], history: seen)
    |> stream(:calls, rows(calls, tenant, reader), reset: true, limit: @limit)
  end

  def handle_info({Watch, :ended}, socket), do: {:noreply, assign(socket, :live?, false)}

  def handle_info({__MODULE__, :expiry}, %{assigns: %{grant: grant}} = socket) do
    if MCP.grant_expired?(grant) do
      Watch.unsubscribe(grant.id)
      {:noreply, assign(socket, :live?, false)}
    else
      {:noreply, schedule_expiry(socket)}
    end
  end

  def handle_info({Watch, %{} = call}, socket) do
    # Already shown from Activity, when it ended between the subscription
    # and the history's read: its start, if that came after, goes
    if call[:event_id] && MapSet.member?(socket.assigns.history, call.event_id) do
      {:noreply, stream_delete_by_dom_id(socket, :calls, dom_id(call))}
    else
      [row] = rows([call], socket.assigns.tenant, socket.assigns.reader)

      {:noreply,
       socket
       |> assign(empty?: false, live_calls: keep_live(socket.assigns.live_calls, call))
       |> stream_insert(:calls, row, at: 0, limit: @limit)}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # The calls this page was told of, the latest of each (an end replaces its
  # start), as many as it shows
  defp keep_live(live, call) do
    live = Map.put(live, call.id, call)

    if map_size(live) > @limit,
      do: live |> Enum.sort_by(fn {_id, c} -> c.at end, {:desc, DateTime}) |> Enum.take(@limit) |> Map.new(),
      else: live
  end

  def render(%{grant: _} = assigns) do
    ~H"""
    <div class="admin-workspace mcp-watch-workspace" data-testid="mcp-watch" data-live={to_string(@live?)}>
      <Workspace.header
        eyebrow={gettext("Connected AI tools")}
        title={@grant.client_name}
        subtitle={
          gettext(
            "What %{client} does in %{site} as %{person}, while it works. It saves nothing: you review what it proposes.",
            client: @grant.client_name,
            site: site_label(@tenant),
            person: person(@grant, @current_user)
          )
        }
      >
        <span :if={@live?} class="badge badge--success" data-testid="mcp-watch-status">
          <span class="badge-dot" aria-hidden="true"></span>{gettext("Connected")}
        </span>
        <span :if={!@live?} class="badge" data-testid="mcp-watch-status">{gettext("Disconnected")}</span>
        <.link :if={@grant.user_id == @current_user.id} navigate="/admin/assistant/connected" class="btn">
          <.icon name="plug" />{gettext("From connected tools")}
        </.link>
      </Workspace.header>

      <p :if={!@live?} class="mcp-watch-ended" role="status">
        {gettext(
          "This connection has ended, so nothing new will appear. To follow the tool again, connect it again and use the link it gives."
        )}
      </p>

      <section class="workspace-panel mcp-watch-panel" aria-labelledby="mcp-watch-title">
        <header class="workspace-panel-heading">
          <div>
            <h2 id="mcp-watch-title">{gettext("Tool calls")}</h2>
            <p>{gettext("Newest first, from the last hour. Each call appears as it starts.")}</p>
          </div>
        </header>
        <div :if={@loaded? and @empty?} class="workspace-empty mcp-watch-empty" data-testid="mcp-watch-empty">
          <.icon name="radio" />
          <h3>{if @live?, do: gettext("Waiting for the tool…"), else: gettext("No calls in the last hour")}</h3>
          <p :if={@live?}>
            {gettext("Ask %{client} to start. Each call it makes on the site appears here as it happens.",
              client: @grant.client_name
            )}
          </p>
        </div>
        <ol id="mcp-watch-calls" class="mcp-watch-calls" phx-update="stream" role="log" aria-labelledby="mcp-watch-title">
          <li
            :for={{dom_id, call} <- @streams.calls}
            id={dom_id}
            class="mcp-watch-call"
            data-state={call.state}
            data-tool={call.tool}
          >
            <span class="mcp-watch-icon" aria-hidden="true"><.icon name={state_icon(call.state)} /></span>
            <div class="mcp-watch-body">
              <p class="mcp-watch-label"><ToolSteps.text parts={call.parts} /></p>
              <p class="mcp-watch-meta">
                <code>{call.tool}</code>
                <time datetime={iso(call.at)} title={Dates.full(call.at)}>{Dates.clock(call.at)}</time>
                <span :if={call.duration_ms}>{duration(call.duration_ms)}</span>
              </p>
              <p :if={call.error} class="mcp-watch-error">{call.error}</p>
              <.images :if={call.folder || call.images != [] || call.failed} call={call} />
              <.proposal :if={call.proposal} proposal={call.proposal} owner?={@grant.user_id == @current_user.id} />
            </div>
            <span class={["badge", state_tone(call.state)]} data-testid="mcp-watch-state">{state_label(call.state)}</span>
          </li>
        </ol>
      </section>
    </div>
    """
  end

  def render(assigns), do: ~H""

  attr :call, :map, required: true

  defp images(assigns) do
    ~H"""
    <div class="mcp-watch-images">
      <p :if={@call.folder} class="mcp-watch-folder"><.icon name="folder" />{@call.folder}</p>
      <ul :if={@call.images != []}>
        <li :for={image <- @call.images} data-image-id={image.id} data-reused={to_string(image.reused)}>
          <span class="mcp-watch-thumb">
            <img :if={image.url} src={image.url} alt={image.title || ""} loading="lazy" />
            <.icon :if={!image.url} name="image" />
          </span>
          <span :if={image.reused} class="badge">{gettext("Reused")}</span>
          <span :if={!image.reused} class="badge badge--success">{gettext("New")}</span>
        </li>
      </ul>
      <p :if={@call.failed} class="mcp-watch-error">
        {ngettext("%{count} image could not be imported.", "%{count} images could not be imported.", @call.failed)}
      </p>
    </div>
    """
  end

  attr :proposal, :map, required: true
  attr :owner?, :boolean, required: true, doc: "only the person reviews their proposals"

  defp proposal(assigns) do
    ~H"""
    <article class="mcp-watch-proposal" data-proposal-id={@proposal.id}>
      <header>
        <h3>{@proposal.title}</h3>
        <span class={["badge", @proposal.tone]}>{@proposal.state}</span>
      </header>
      <p class="mcp-watch-counts">
        {gettext("Version %{version}", version: @proposal.version)}<span :for={count <- @proposal.counts}> · {count}</span>
      </p>
      <ul :if={@proposal.problems != []} class="mcp-watch-problems" aria-label={gettext("Problems to fix")}>
        <li :for={problem <- @proposal.problems}><.icon name="triangle-alert" />{problem}</li>
      </ul>
      <div :if={@owner?} class="mcp-watch-actions">
        <.link navigate={@proposal.review} class="btn btn--sm">{gettext("Open the review")}</.link>
        <.link :if={@proposal.preview} navigate={@proposal.preview} class="btn btn--sm btn--quiet">
          <.icon name="eye" />{gettext("Open on the page")}
        </.link>
      </div>
    </article>
    """
  end

  ## Loading

  defp load(id, user) do
    with {id, ""} <- Integer.parse(to_string(id)),
         %Grant{} = grant <- Repo.get(Grant, id),
         grant = Repo.preload(grant, [:site, :environment, :user]),
         true <- allowed?(grant, user) do
      {:ok, grant}
    else
      _ -> :error
    end
  end

  # As stored now: the socket's user is the one that logged in, and the
  # connection's site (legacy access takes its status from the struct)
  defp allowed?(grant, user) do
    grant = Repo.preload(grant, :site, force: true)

    case Repo.one(from(u in User, where: u.id == ^user.id and u.active and is_nil(u.deleted_at)), prefix: "public") do
      nil -> false
      user -> (grant.user_id == user.id and site_access?(user, grant)) or MCP.can_manage?(user, MCP.grant_tenant(grant))
    end
  end

  defp site_access?(_user, %Grant{site: nil}), do: true
  defp site_access?(user, %Grant{site: site}), do: Brando.Tenant.Access.can_access?(user, site)

  # Who reads what the calls named: nil for the connection's person, who sees
  # it all; for anyone else, whom to ask what they may read, in the
  # connection's site environment
  defp reader(%Grant{user_id: id}, %User{id: id}, _tenant), do: nil

  defp reader(_grant, user, tenant),
    do: if(Brando.Authorization.Engine.enabled?(), do: MCP.authorization_scope(user, tenant), else: user)

  defp live?(grant), do: is_nil(grant.revoked_at) and not MCP.grant_expired?(grant)

  defp schedule_expiry(%{assigns: %{live?: true, grant: grant}} = socket) do
    if connected?(socket) do
      left = DateTime.diff(MCP.grant_expires_at(grant), DateTime.utc_now(), :millisecond) + 1
      Process.send_after(self(), {__MODULE__, :expiry}, left |> max(0) |> min(@expiry_check))
    end

    socket
  end

  defp schedule_expiry(socket), do: socket

  defp dom_id(call), do: "mcp-call-#{call.id}"

  defp person(%{user_id: id}, %{id: id}), do: gettext("you")
  defp person(%{user: %{name: name}}, _viewer), do: name

  defp site_label(%{site: nil}), do: Brando.config(:app_name) || "Brando"
  defp site_label(%{site: site, environment: environment}), do: "#{site.name} · #{environment.name}"

  # Each call as a row: its line, error, images and proposal. What they name
  # is read in the connection's site environment.
  defp rows(calls, tenant, reader) do
    MCP.in_tenant(tenant, fn ->
      images = load_images(Enum.flat_map(calls, &image_ids/1), reader)
      proposals = load_proposals(Enum.flat_map(calls, &List.wrap(&1.details["proposal"])))
      Enum.map(calls, &row(&1, images, proposals, reader))
    end)
  end

  defp row(call, images, proposals, reader) do
    details = if reader, do: unnamed(call.details), else: call.details
    output = details["output"] || %{}

    %{
      id: call.id,
      tool: call.tool,
      state: call.state,
      at: call.at,
      duration_ms: call[:duration_ms],
      parts: ToolSteps.label(Watch.short_name(call.tool), details["input"] || %{}, output),
      error: details["error"],
      folder: details["folder"],
      failed: details["failed"],
      images:
        for(
          %{"id" => id} = image <- List.wrap(details["images"]),
          do: Map.merge(Map.get(images, id, %{url: nil, title: nil}), %{id: id, reused: image["reused"] == true})
        ),
      proposal: proposal_card(Map.get(proposals, details["proposal"]), details, reader)
    }
  end

  # A call's details without what it named: the words searched for, the
  # entry's title, the frame, the file name and the folder
  defp unnamed(details) do
    input = details["input"] || %{}

    input =
      if is_binary(input["query"]) and String.trim(input["query"]) != "",
        do: Map.put(input, "query", :hidden),
        else: input

    details
    |> Map.put("input", Map.drop(input, ["name", "filename"]))
    |> Map.put("output", Map.drop(details["output"] || %{}, ["title", "frame"]))
    |> Map.delete("folder")
  end

  defp image_ids(call), do: for(%{"id" => id} when is_integer(id) <- List.wrap(call.details["images"]), do: id)

  defp load_images([], _reader), do: %{}

  defp load_images(ids, reader) do
    query = from(i in Image, where: i.id in ^Enum.uniq(ids) and is_nil(i.deleted_at))

    if(reader, do: Catalog.scoped_query(query, Image, reader, :read), else: query)
    |> Repo.all()
    |> Map.new(&{&1.id, %{url: image_url(&1), title: plain(&1.title)}})
  end

  defp load_proposals([]), do: %{}

  defp load_proposals(ids) do
    ids = Enum.filter(ids, &match?({:ok, _}, Ecto.UUID.cast(&1)))

    from(r in Record, where: r.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp proposal_card(nil, _details, _reader), do: nil

  defp proposal_card(%Record{} = record, details, reader) do
    {state, tone} = proposal_state(record)
    readable? = is_nil(reader) or readable?(record, reader)

    %{
      id: record.id,
      title: if(readable?, do: record.summary || gettext("Untitled proposal"), else: gettext("A proposal")),
      version: record.version,
      state: state,
      tone: tone,
      counts: counts(record.effects || %{}),
      problems:
        if(readable?,
          do: record.problems |> List.wrap() |> Enum.map(& &1["message"]) |> Enum.filter(&is_binary/1),
          else: []
        ),
      review: "/admin/assistant/connected/#{record.id}",
      preview: details["preview"]
    }
  end

  # Whether `reader` may read each entry the proposal changes, and the
  # content types it creates entries of
  defp readable?(%Record{operations: operations, status: status}, reader) do
    operations
    |> List.wrap()
    |> Enum.flat_map(&(&1 |> as_applied(status) |> subjects()))
    |> Enum.uniq()
    |> Enum.all?(&readable_subject?(&1, reader))
  end

  # Once applied, the image whose file replaced another's has no record
  defp as_applied(%{"op" => "replace_image_file"} = op, "applied"), do: Map.delete(op, "with")
  defp as_applied(op, _status), do: op

  defp subjects(%{"op" => "create_entry", "content_type" => type}), do: [{type, nil}]

  defp subjects(%{"op" => "create_translation", "source" => %{"content_type" => type, "id" => id}}),
    do: [{type, nil}, {type, id}]

  defp subjects(%{"op" => "replace_image_file"} = op) do
    for %{"kind" => "image", "id" => id} <- [op["asset"], op["with"]], do: {:image, id}
  end

  defp subjects(%{} = op) do
    for %{"content_type" => type, "id" => id} <- [op["target"], op["to"]], do: {type, id}
  end

  defp subjects(_op), do: []

  defp readable_subject?({:image, id}, reader),
    do: is_integer(id) and Boundary.authorize_record(reader, :read, Image, id) == :ok

  defp readable_subject?({type, id}, reader) do
    case Codec.schema(type) do
      {:ok, schema} when is_integer(id) -> Boundary.authorize_record(reader, :read, schema, id) == :ok
      {:ok, schema} -> Boundary.authorize(reader, :read, schema) == :ok
      :error -> false
    end
  end

  defp proposal_state(%{status: "applied"}), do: {gettext("Applied"), "badge--success"}
  defp proposal_state(%{status: "approved"}), do: {gettext("Approved"), "badge--success"}
  defp proposal_state(%{status: "undone"}), do: {gettext("Undone"), nil}
  defp proposal_state(%{status: "cancelled"}), do: {gettext("Discarded"), nil}
  defp proposal_state(%{status: "superseded"}), do: {gettext("Replaced by a newer version"), nil}
  defp proposal_state(%{problems: [_ | _]}), do: {gettext("Needs changes"), "badge--attention"}

  defp proposal_state(record) do
    if DateTime.compare(record.expires_at, DateTime.utc_now()) == :lt,
      do: {gettext("Expired"), nil},
      else: {gettext("Waiting for review"), "badge--ai"}
  end

  defp counts(effects) do
    [
      {effects["creates"], &ngettext("%{count} new entry", "%{count} new entries", &1)},
      {effects["updates"], &ngettext("%{count} updated entry", "%{count} updated entries", &1)},
      {effects["inserted_blocks"], &ngettext("%{count} new block", "%{count} new blocks", &1)},
      {effects["updated_blocks"], &ngettext("%{count} changed block", "%{count} changed blocks", &1)},
      {effects["moved_blocks"], &ngettext("%{count} moved block", "%{count} moved blocks", &1)},
      {effects["deletions"], &ngettext("%{count} deletion", "%{count} deletions", &1)},
      {effects["replaced_images"], &ngettext("%{count} image file replaced", "%{count} image files replaced", &1)}
    ]
    |> Enum.filter(fn {count, _label} -> is_integer(count) and count > 0 end)
    |> Enum.map(fn {count, label} -> label.(count) end)
  end

  # A fresh upload has no sizes until processing finishes; show the original.
  defp image_url(image) do
    size = if Map.has_key?(image.sizes || %{}, "thumb"), do: :thumb, else: :original
    Brando.Utils.img_url(image, size, prefix: Brando.Utils.media_url())
  rescue
    _ -> nil
  end

  defp plain(%{} = text), do: text[Gettext.get_locale(Brando.Gettext)] || text |> Map.values() |> List.first()
  defp plain(text), do: text

  defp iso(%NaiveDateTime{} = at), do: NaiveDateTime.to_iso8601(at) <> "Z"
  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)

  defp state_icon(:running), do: "loader-circle"
  defp state_icon(:ok), do: "check"
  defp state_icon(:error), do: "circle-alert"

  defp state_tone(:running), do: "badge--ai"
  defp state_tone(:ok), do: nil
  defp state_tone(:error), do: "badge--error"

  defp state_label(:running), do: gettext("Running")
  defp state_label(:ok), do: gettext("Done")
  defp state_label(:error), do: gettext("Failed")

  defp duration(ms) when ms < 1_000, do: gettext("%{ms} ms", ms: ms)
  defp duration(ms), do: gettext("%{seconds} s", seconds: :erlang.float_to_binary(ms / 1_000, decimals: 1))
end
