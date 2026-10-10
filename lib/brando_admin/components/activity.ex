defmodule BrandoAdmin.Components.Activity do
  @moduledoc """
  The pieces of an activity event shared by Configuration → Activity and an
  entry's history: what happened (`action/1`), who did it (`person/1`, with
  the kind of actor as a badge, `kind_badge/1`), the entry it happened to
  (`entry/1`) and the details line (`details/1`). See `Brando.Activity`.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Transfer.Labels
  alias Brando.Utils.Datetime
  alias BrandoAdmin.Components.TextDiff

  @trash_days 30
  @webhook "Elixir.Brando.Webhooks.Webhook"
  @route "Elixir.Brando.Notifications.Route"
  # Connected AI tools (`Brando.MCP`): a connection, and the endpoint's switch
  @mcp_grant "Elixir.Brando.MCP.Grant"
  @mcp_setting "Elixir.Brando.MCP.Setting"

  ## Data

  @doc """
  Where each entry the events name stands: `%{{schema, id} => :live |
  :trashed}`; an entry missing from the map no longer exists. Covers the
  entries copies were made from, too.
  """
  def states(events) do
    events
    |> Enum.flat_map(fn event ->
      copied = get_in(event.details, ["copied_from", "id"])
      [{event.schema, event.entry_id}] ++ if(copied, do: [{event.schema, copied}], else: [])
    end)
    |> Enum.reject(fn {_, id} -> is_nil(id) end)
    |> Enum.uniq()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {schema_name, ids} ->
      case schema(schema_name) do
        nil -> []
        schema -> states_for(schema, ids)
      end
    end)
    |> Map.new()
  end

  defp states_for(schema, ids) do
    soft_delete? = :deleted_at in schema.__schema__(:fields)

    query =
      if soft_delete?,
        do: from(e in schema, where: e.id in ^ids, select: {e.id, e.deleted_at}),
        else: from(e in schema, where: e.id in ^ids, select: {e.id, nil})

    query
    |> Brando.Repo.all()
    |> Enum.map(fn {id, deleted_at} -> {{to_string(schema), id}, if(deleted_at, do: :trashed, else: :live)} end)
  rescue
    _ -> []
  end

  @doc "The schema module an event names, if it is still a known Blueprint."
  def schema(name) when is_binary(name) do
    module = Module.concat([name])
    if Code.ensure_loaded?(module) and function_exported?(module, :__naming__, 0), do: module
  end

  @doc """
  Consecutive events that share a `batch_id` (one content import) become one
  item: `{:batch, events}`; the rest stay `{:event, event}`.
  """
  def items(events) do
    events
    |> Enum.chunk_by(&(&1.batch_id || make_ref()))
    |> Enum.map(fn
      [event] -> {:event, event}
      batch -> {:batch, batch}
    end)
  end

  @doc "Items grouped by the day they happened, in the site's timezone: `[{date, items}]`."
  def by_day(items) do
    items
    |> Enum.chunk_by(&(&1 |> item_time() |> local_date()))
    |> Enum.map(fn [first | _] = day -> {first |> item_time() |> local_date(), day} end)
  end

  defp item_time({:event, event}), do: event.inserted_at
  defp item_time({:batch, [event | _]}), do: event.inserted_at

  defp local_date(datetime), do: datetime |> DateTime.shift_zone!(Brando.timezone()) |> DateTime.to_date()

  @doc "A day heading: Today, Yesterday or the weekday."
  def day_label(date) do
    today = DateTime.utc_now() |> DateTime.shift_zone!(Brando.timezone()) |> DateTime.to_date()

    case Date.diff(today, date) do
      0 -> gettext("Today")
      1 -> gettext("Yesterday")
      _ -> date |> Datetime.format_datetime("%A") |> String.capitalize()
    end
  end

  def short_date(date), do: Datetime.format_datetime(date, "%d.%m.%y")
  def time(datetime), do: Datetime.format_datetime(datetime, "%H:%M")

  @doc "When the event happened, relative to today when that's shorter: `Today 14:32` or `01.10.26 17:05`."
  def when_label(datetime) do
    date = local_date(datetime)
    today = DateTime.utc_now() |> DateTime.shift_zone!(Brando.timezone()) |> DateTime.to_date()

    if Date.diff(today, date) in [0, 1],
      do: day_label(date) <> " " <> time(datetime),
      else: short_date(date) <> " " <> time(datetime)
  end

  ## Labels

  def action_label(%{action: :created}), do: gettext("Created")
  def action_label(%{action: :updated}), do: gettext("Updated")
  def action_label(%{action: :published}), do: gettext("Published")
  def action_label(%{action: :unpublished}), do: gettext("Unpublished")
  def action_label(%{action: :trashed}), do: gettext("Moved to trash")
  def action_label(%{action: :restored}), do: gettext("Restored from trash")
  def action_label(%{action: :deleted}), do: gettext("Deleted permanently")

  def action_label(%{action: :revision_restored, revision: revision}),
    do: gettext("Restored revision #%{revision}", revision: revision)

  def action_label(%{action: :duplicated}), do: gettext("Duplicated")
  def action_label(%{action: :imported}), do: gettext("Imported")
  def action_label(%{action: :reordered}), do: gettext("Reordered")
  def action_label(%{action: :note_added}), do: gettext("Added a note")
  def action_label(%{action: :note_resolved}), do: gettext("Resolved a note")
  def action_label(%{action: :note_reopened}), do: gettext("Reopened a note")
  def action_label(%{action: :tool_called}), do: gettext("Used a tool")

  @doc "The filter options for actions: `[{label, value}]`."
  def action_options do
    [
      {gettext("Created"), "created"},
      {gettext("Updated"), "updated"},
      {gettext("Published"), "published"},
      {gettext("Unpublished"), "unpublished"},
      {gettext("Moved to trash"), "trashed"},
      {gettext("Restored from trash"), "restored"},
      {gettext("Deleted permanently"), "deleted"},
      {gettext("Restored a revision"), "revision_restored"},
      {gettext("Duplicated"), "duplicated"},
      {gettext("Imported"), "imported"},
      {gettext("Reordered"), "reordered"},
      {gettext("Added a note"), "note_added"},
      {gettext("Resolved a note"), "note_resolved"},
      {gettext("Reopened a note"), "note_reopened"},
      {gettext("Used a tool"), "tool_called"}
    ]
  end

  @doc "The badge for a kind of actor (`Brando.Activity.actor_kind/1`); a person's change has none."
  def kind_label(:assistant), do: gettext("AI")
  def kind_label(:mcp), do: gettext("MCP")
  def kind_label(:task), do: gettext("Automatic")
  def kind_label(_kind), do: nil

  @doc """
  The filter options for who made a change: `[{label, value}]`, a kind of
  actor, and each MCP client in `clients` as `mcp:<name>`.
  """
  def actor_options(clients) do
    [
      {gettext("People"), "person"},
      {gettext("Assistant"), "assistant"},
      {gettext("Connected tools (MCP)"), "mcp"}
    ] ++
      Enum.map(clients, &{gettext("%{client} via MCP", client: &1), "mcp:" <> &1}) ++
      [{gettext("Automatic jobs"), "task"}]
  end

  @doc """
  Who is looking, for links only they can follow: their id, and whether they
  may use the Assistant, where a proposal is reviewed.
  """
  def viewer(%{id: id} = user), do: %{user_id: id, assistant?: Brando.AI.Agent.allowed?(user)}
  def viewer(_user), do: %{user_id: nil, assistant?: false}

  @doc """
  Where the proposal a change came from is reviewed: for the user who
  applied it, while they may use the Assistant. A conversation's proposal
  opens in its conversation.
  """
  def proposal_path(%{proposal_id: id, approver_id: approver_id}, %{user_id: approver_id, assistant?: true})
      when is_binary(id) and is_integer(approver_id),
      do: "/admin/assistant/connected/#{id}"

  def proposal_path(_event, _viewer), do: nil

  defp tone(:published), do: "is-published"
  defp tone(:created), do: "is-created"
  defp tone(:duplicated), do: "is-created"
  defp tone(:imported), do: "is-created"
  defp tone(:updated), do: "is-updated"
  defp tone(:restored), do: "is-restored"
  defp tone(:revision_restored), do: "is-restored"
  defp tone(:trashed), do: "is-trashed"
  defp tone(:deleted), do: "is-deleted"
  defp tone(:note_added), do: "is-note"
  defp tone(:note_resolved), do: "is-note"
  defp tone(:note_reopened), do: "is-note"
  defp tone(_), do: "is-neutral"

  defp setting_label(@webhook), do: gettext("Webhook")
  defp setting_label(@route), do: gettext("Notification route")
  defp setting_label(@mcp_grant), do: gettext("Connected app")
  defp setting_label(@mcp_setting), do: gettext("MCP endpoint")
  defp setting_label(_schema), do: nil

  @doc "A content type's name in the admin's language."
  def type_label(nil), do: nil

  def type_label(schema) do
    Labels.schema(schema)
  rescue
    _ -> nil
  end

  defp plural_label(schema) do
    Brando.Blueprint.get_plural(schema)
  rescue
    _ -> nil
  end

  defp status_label("published"), do: gettext("Published")
  defp status_label("draft"), do: gettext("Draft")
  defp status_label("pending"), do: gettext("Pending")
  defp status_label("disabled"), do: gettext("Deactivated")
  defp status_label(status), do: status

  @doc "The changed fields as one phrase: `title, blocks and SEO description`."
  def fields_phrase(schema, fields) do
    fields
    |> Enum.reject(&(&1 == "status"))
    |> Enum.map(&field_label(schema, &1))
    |> sentence()
  end

  defp field_label(nil, field), do: field |> Phoenix.Naming.humanize() |> downcase_first()
  defp field_label(schema, field), do: schema |> Labels.field(field) |> downcase_first()

  # "Title" reads as "title" mid-sentence; "SEO title" and "URI" keep their capitals.
  defp downcase_first(<<_first::utf8, second::utf8, _::binary>> = label) when second in ?A..?Z or second in ?0..?9,
    do: label

  defp downcase_first(<<first::utf8, rest::binary>>), do: String.downcase(<<first::utf8>>) <> rest
  defp downcase_first(label), do: label

  defp sentence([]), do: nil
  defp sentence([one]), do: one

  defp sentence(items) do
    {init, [last]} = Enum.split(items, -1)
    Enum.join(init, ", ") <> " " <> gettext("and") <> " " <> last
  end

  ## Paths

  @doc "The entry's edit page, while the entry exists and isn't in the trash."
  def entry_path(%{entry_id: nil}, _states), do: nil

  def entry_path(event, states) do
    if states[{event.schema, event.entry_id}] == :live, do: update_path(event.schema, event.entry_id)
  end

  @doc "The listing's trash, for an entry that is in it."
  def trash_path(%{entry_id: nil}, _states), do: nil

  def trash_path(event, states) do
    if states[{event.schema, event.entry_id}] == :trashed do
      case update_path(event.schema, event.entry_id) do
        nil -> nil
        path -> String.replace(path, ~r{/update/\d+$}, "") <> "?status=deleted"
      end
    end
  end

  defp update_path(schema_name, id) do
    case schema(schema_name) do
      nil -> nil
      schema -> schema.__admin_route__(:update, [id])
    end
  rescue
    _ -> nil
  end

  ## Components

  attr :event, :map, required: true

  def action(assigns) do
    ~H"""
    <span class={["activity-action", tone(@event.action)]}><i aria-hidden="true"></i>{action_label(@event)}</span>
    """
  end

  attr :event, :map, required: true
  attr :compact, :boolean, default: false

  @doc """
  Who did it: the person, or the source with its kind and the person behind
  it (who approved it, set it or ran it) underneath.
  """
  def person(assigns) do
    assigns = assign(assigns, :source, source(assigns.event))

    ~H"""
    <div class={["activity-person", @source && "is-source"]}>
      <%= if @source do %>
        <span class="activity-avatar is-source" aria-hidden="true"><.icon name={@source.icon} /></span>
        <span class="activity-person-name">
          <span class="activity-person-line">{@source.label}<.kind_badge event={@event} /></span>
          <small :if={@source.caption}>{@source.caption}</small>
        </span>
      <% else %>
        <.avatar user={@event.user} />
        <span class="activity-person-name">{(@event.user && @event.user.name) || gettext("Unknown")}</span>
      <% end %>
    </div>
    """
  end

  attr :event, :map, required: true

  @doc "The person's avatar, or the source's icon, alone."
  def marker(assigns) do
    assigns = assign(assigns, :source, source(assigns.event))

    ~H"""
    <span :if={@source} class="activity-avatar is-source" aria-hidden="true"><.icon name={@source.icon} /></span>
    <.avatar :if={!@source} user={@event.user} />
    """
  end

  attr :event, :map, required: true

  @doc "The kind of actor behind an event, as a small badge: AI, MCP or Automatic. Nothing for a person."
  def kind_badge(assigns) do
    kind = Brando.Activity.actor_kind(assigns.event)
    assigns = assign(assigns, kind: kind, label: kind_label(kind))

    ~H"""
    <span :if={@label} class="activity-kind" data-kind={@kind}>{@label}</span>
    """
  end

  attr :user, :any, required: true

  def avatar(assigns) do
    image =
      case assigns.user && Map.get(assigns.user, :avatar) do
        %{status: :processed} = image -> image
        _ -> nil
      end

    assigns = assign(assigns, image: image, initials: initials(assigns.user), tone: avatar_tone(assigns.user))

    ~H"""
    <span class={["activity-avatar", @tone]} aria-hidden="true">
      <img :if={@image} src={Brando.Utils.img_url(@image, :thumb, prefix: Brando.Utils.media_url())} alt="" />
      <span :if={!@image}>{@initials}</span>
    </span>
    """
  end

  defp initials(%{name: name}) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  defp initials(_), do: "?"

  defp avatar_tone(%{id: id}) when is_integer(id), do: Enum.at(["", "is-blue", "is-sand"], rem(id, 3))
  defp avatar_tone(_), do: nil

  defp source(%{source: :scheduler} = event),
    do: %{icon: "clock", label: gettext("Scheduled publishing"), caption: by(event, :scheduler)}

  defp source(%{source: :assistant} = event),
    do: %{icon: "sparkles", label: gettext("Assistant"), caption: approved_by(event)}

  # A tool's own call, as the person who connected it
  defp source(%{source: :mcp, action: :tool_called} = event),
    do: %{icon: "plug", label: mcp_label(event), caption: by(event, :mcp)}

  defp source(%{source: :mcp} = event),
    do: %{icon: "plug", label: mcp_label(event), caption: approved_by(event)}

  defp source(%{source: :import} = event),
    do: %{icon: "download", label: gettext("Content transfer"), caption: by(event, :import)}

  defp source(%{source: :system, user: nil}), do: %{icon: "settings", label: gettext("System"), caption: nil}
  # Made by hand by a user whose account has since been removed.
  defp source(%{user: nil}), do: %{icon: "user", label: gettext("Deleted user"), caption: nil}
  defp source(_), do: nil

  # Without an approver (a user since removed), the person it was made as
  defp approved_by(event), do: approver_label(event) || by(event, :assistant)

  @doc "Who approved and applied an agent's change, or undid it: `Approved by Ola Hansen`. `nil` for no one."
  def approver_label(%{approver: %{name: name}, details: %{"undo_proposal" => true}}),
    do: gettext("Undone by %{name}", name: name)

  def approver_label(%{approver: %{name: name}}), do: gettext("Approved by %{name}", name: name)
  def approver_label(_event), do: nil

  defp by(%{user: nil}, _), do: nil
  defp by(%{user: user}, :scheduler), do: gettext("Set by %{name}", name: user.name)
  defp by(%{user: user}, :assistant), do: gettext("Approved by %{name}", name: user.name)
  defp by(%{user: user}, :import), do: gettext("Run by %{name}", name: user.name)
  defp by(%{user: user}, :mcp), do: gettext("As %{name}", name: user.name)

  # The badge says MCP
  defp mcp_label(%{details: %{"client" => client}}) when is_binary(client), do: client
  defp mcp_label(_event), do: gettext("A connected tool")

  @doc "The person, or the source, as a short phrase for the entry history: `by Ola Hansen`."
  def by_phrase(%{source: :scheduler}), do: gettext("by scheduled publishing")
  def by_phrase(%{source: :assistant}), do: gettext("by the assistant")

  def by_phrase(%{source: :mcp, details: %{"client" => client}}) when is_binary(client),
    do: gettext("by %{client}", client: client)

  def by_phrase(%{source: :mcp}), do: gettext("by a connected tool")
  def by_phrase(%{source: :import}), do: gettext("by a content transfer")
  def by_phrase(%{source: :system, user: nil}), do: gettext("by the system")
  def by_phrase(%{user: nil}), do: gettext("by a deleted user")
  def by_phrase(%{user: user}), do: gettext("by %{name}", name: user.name)

  attr :event, :map, required: true
  attr :states, :map, required: true

  @doc "The entry an event happened to, linked while it can be opened, with its type and language."
  def entry(assigns) do
    schema = schema(assigns.event.schema)

    assigns =
      assign(assigns,
        path: entry_path(assigns.event, assigns.states),
        gone?:
          assigns.event.schema not in [@webhook, @route, @mcp_grant, @mcp_setting] && assigns.event.entry_id &&
            is_nil(assigns.states[{assigns.event.schema, assigns.event.entry_id}]),
        title: assigns.event.title || plural_label(schema) || assigns.event.schema,
        type: if(assigns.event.entry_id, do: type_label(schema) || setting_label(assigns.event.schema)),
        language: assigns.event.language && String.upcase(assigns.event.language)
      )

    ~H"""
    <.link :if={@path} navigate={@path} class="activity-entry">{@title}</.link>
    <span :if={!@path && @gone?} class="activity-entry is-gone">{@title}</span>
    <span :if={!@path && !@gone?} class="activity-entry">{@title}</span>
    <span :if={@type} class="activity-type">{Enum.join(Enum.reject([@type, @language], &is_nil/1), " · ")}</span>
    """
  end

  attr :event, :map, required: true
  attr :states, :map, required: true

  @doc "The line under an event: what changed, or what the action means for the entry now."
  def details(assigns) do
    assigns = assign(assigns, :lines, detail_lines(assigns.event, assigns.states))

    ~H"""
    <p :for={line <- @lines} class="activity-detail">{line}</p>
    """
  end

  defp detail_lines(event, states) do
    fields = fields_phrase(schema(event.schema), event.fields || [])
    event |> lines(fields, states) |> Enum.reject(&is_nil/1)
  end

  # Webhooks (`Brando.Webhooks`) are settings, not entries
  defp lines(%{schema: @webhook, details: %{"webhook" => "secret_rotated"}}, _fields, _states),
    do: [gettext("Rotated the signing secret")]

  defp lines(%{schema: @webhook, details: %{"webhook" => "paused", "reason" => "failures"}}, _fields, _states),
    do: [gettext("Paused after its deliveries kept failing")]

  defp lines(%{schema: @webhook, details: %{"webhook" => "paused", "reason" => "environment_copy"}}, _fields, _states),
    do: [gettext("Paused because this environment was copied or restored")]

  defp lines(%{schema: @webhook, details: %{"webhook" => "resumed", "reason" => "went_live"}}, _fields, _states),
    do: [gettext("Resumed when this environment went live")]

  defp lines(%{schema: @webhook, details: %{"webhook" => "paused"}}, _fields, _states), do: [gettext("Paused")]
  defp lines(%{schema: @webhook, details: %{"webhook" => "resumed"}}, _fields, _states), do: [gettext("Resumed")]

  defp lines(%{schema: @webhook, action: :created, details: %{"url_host" => host}}, _fields, _states),
    do: [gettext("Sends to %{host}", host: host)]

  defp lines(%{schema: @webhook, action: :deleted}, _fields, _states),
    do: [gettext("Deleted with its delivery log")]

  defp lines(%{schema: @webhook}, fields, _states), do: [fields && fields_line(fields)]

  # Notification routes (`Brando.Notifications.Routing`) are settings too
  defp lines(%{schema: @route, details: %{"route" => "paused", "reason" => "failures"}}, _fields, _states),
    do: [gettext("Paused after its messages kept failing")]

  defp lines(%{schema: @route, details: %{"route" => "paused", "reason" => "environment_copy"}}, _fields, _states),
    do: [gettext("Paused because this environment was copied or restored")]

  defp lines(%{schema: @route, details: %{"route" => "resumed", "reason" => "went_live"}}, _fields, _states),
    do: [gettext("Resumed when this environment went live")]

  defp lines(%{schema: @route, details: %{"route" => "paused"}}, _fields, _states), do: [gettext("Paused")]
  defp lines(%{schema: @route, details: %{"route" => "resumed"}}, _fields, _states), do: [gettext("Resumed")]

  defp lines(%{schema: @route, action: :deleted}, _fields, _states),
    do: [gettext("Deleted with its delivery log")]

  defp lines(%{schema: @route}, fields, _states), do: [fields && fields_line(fields)]

  defp lines(%{schema: @mcp_grant, action: :tool_called, details: %{"tool" => tool, "ok" => false}}, _fields, _states),
    do: [gettext("%{tool}, which failed", tool: tool)]

  defp lines(%{schema: @mcp_grant, action: :tool_called, details: %{"tool" => tool}}, _fields, _states), do: [tool]

  defp lines(%{schema: @mcp_grant, details: %{"mcp" => "connected"}}, _fields, _states),
    do: [gettext("Connected over MCP")]

  defp lines(%{schema: @mcp_grant, details: %{"mcp" => "revoked", "reason" => reason}}, _fields, _states)
       when reason in ["refresh_token_reuse", "code_reuse"],
       do: [gettext("Disconnected: a used token was presented again")]

  defp lines(%{schema: @mcp_grant, details: %{"mcp" => "revoked"}}, _fields, _states), do: [gettext("Disconnected")]

  defp lines(%{schema: @mcp_setting, details: %{"mcp" => "enabled"}}, _fields, _states),
    do: [gettext("Turned the MCP endpoint on")]

  defp lines(%{schema: @mcp_setting, details: %{"mcp" => "disabled", "revoked" => count}}, _fields, _states)
       when is_integer(count) and count > 0,
       do: [
         ngettext(
           "Turned the MCP endpoint off and disconnected %{count} app",
           "Turned the MCP endpoint off and disconnected %{count} apps",
           count
         )
       ]

  defp lines(%{schema: @mcp_setting, details: %{"mcp" => "disabled"}}, _fields, _states),
    do: [gettext("Turned the MCP endpoint off")]

  defp lines(%{schema: schema}, _fields, _states) when schema in [@mcp_grant, @mcp_setting], do: []

  defp lines(%{action: :created} = event, _fields, _states), do: [status_saved(event.details)]

  defp lines(%{action: action, details: details}, _fields, _states)
       when action in [:note_added, :note_resolved, :note_reopened] do
    excerpt = if details["excerpt"] not in [nil, ""], do: "“" <> details["excerpt"] <> "”"

    case Enum.reject([details["anchor"], excerpt], &(&1 in [nil, ""])) do
      [] -> []
      parts -> [Enum.join(parts, " · ")]
    end
  end

  defp lines(%{action: :reordered, details: details}, _fields, _states) do
    count = details["count"] || 0
    moved = ngettext("Moved %{count} entry", "Moved %{count} entries", count, count: count)

    if details["first"],
      do: [moved <> "; " <> gettext("%{title} is now first", title: details["first"])],
      else: [moved]
  end

  defp lines(%{action: :trashed} = event, _fields, states) do
    if states[{event.schema, event.entry_id}] == :trashed do
      until = DateTime.add(event.inserted_at, @trash_days * 86_400, :second)
      [gettext("Can be restored from the trash until %{date}", date: short_date(until))]
    else
      []
    end
  end

  defp lines(%{action: :deleted, details: %{"purged" => true}}, _fields, _states),
    do: [gettext("Removed from the trash after %{days} days", days: @trash_days)]

  defp lines(%{action: :deleted, details: %{"undo_proposal" => true}}, _fields, _states),
    do: [gettext("Removed by undoing the proposal that created it")]

  defp lines(%{details: %{"undo_proposal" => true}}, _fields, _states),
    do: [gettext("Set back by undoing the proposal")]

  defp lines(%{action: :deleted, details: %{"undo_import" => true}}, _fields, _states),
    do: [gettext("Removed by undoing the import that created it")]

  defp lines(%{action: :deleted}, _fields, _states), do: [gettext("The entry no longer exists")]

  defp lines(%{action: :updated, details: %{"undo_import" => true}}, _fields, _states),
    do: [gettext("Set back by undoing an import")]

  defp lines(%{details: %{"stale_blocks" => resolved}}, _fields, _states), do: stale_blocks_lines(resolved)

  defp lines(%{details: %{"schedule_refused" => refused}}, _fields, _states), do: schedule_refused_lines(refused)

  defp lines(%{action: :revision_restored, details: %{"replaced" => replaced}, revision: revision}, fields, _states)
       when replaced != revision,
       do: [gettext("Replaced revision #%{revision}", revision: replaced), also_changed(fields)]

  defp lines(%{action: :published, details: %{"scheduled" => true}, revision: nil}, _fields, _states),
    do: [gettext("As scheduled")]

  defp lines(%{action: :published, details: %{"scheduled" => true}, revision: revision}, _fields, _states),
    do: [gettext("Activated revision #%{revision}, as scheduled", revision: revision)]

  defp lines(%{action: :duplicated, details: %{"copied_from" => %{"title" => title}}}, _fields, _states),
    do: [gettext("Copied from %{title}", title: title)]

  defp lines(%{action: :imported, details: details}, fields, _states),
    do: [import_line(details), fields && gettext("Replaced %{fields}", fields: fields)]

  defp lines(%{details: %{"status" => %{"from" => from, "to" => to}}}, fields, _states) do
    [
      gettext("Status changed from %{from} to %{to}", from: status_label(from), to: status_label(to)),
      also_changed(fields)
    ]
  end

  defp lines(_event, fields, _states), do: [fields_line(fields)]

  # `Brando.Content.StaleBlocks`: leftovers dropped or moved, `kind:key` and
  # `kind:key→target`.
  defp stale_blocks_lines(resolved) do
    count = length(resolved["blocks"] || [])

    keys = fn list ->
      Enum.map_join(list, ", ", &(&1 |> String.split(":", parts: 2) |> List.last() |> String.replace("→", " → ")))
    end

    [
      ngettext(
        "Brought %{count} %{module} block up to date",
        "Brought %{count} %{module} blocks up to date",
        count,
        count: count,
        module: resolved["module"]
      ),
      resolved["dropped"] not in [nil, []] && gettext("Dropped %{keys}", keys: keys.(resolved["dropped"])),
      resolved["mapped"] not in [nil, []] && gettext("Moved %{keys}", keys: keys.(resolved["mapped"]))
    ]
    |> Enum.filter(& &1)
  end

  # `Brando.Worker.EntryPublisher`: a publication whose user may no longer
  # make it, or whose account is gone, taken back; an expiry carried out by
  # the system instead
  defp schedule_refused_lines(%{"action" => "publish", "reason" => "forbidden"}),
    do: [
      gettext("Not published as scheduled: the user who scheduled it may no longer publish it"),
      gettext("Set back to draft")
    ]

  defp schedule_refused_lines(%{"action" => "publish"}),
    do: [
      gettext("Not published as scheduled: the user who scheduled it is deactivated or deleted"),
      gettext("Set back to draft")
    ]

  defp schedule_refused_lines(%{"reason" => "forbidden"}),
    do: [gettext("Deactivated as scheduled, by the system: the user who set the expiry may no longer deactivate it")]

  defp schedule_refused_lines(_refused),
    do: [gettext("Deactivated as scheduled, by the system: the user who set the expiry is deactivated or deleted")]

  defp status_saved(%{"status" => %{"to" => status}}),
    do: gettext("Saved as %{status}", status: status |> status_label() |> downcase_first())

  defp status_saved(_), do: nil

  defp fields_line(nil), do: nil
  defp fields_line(fields), do: gettext("Changed %{fields}", fields: fields)

  defp also_changed(nil), do: nil
  defp also_changed(fields), do: gettext("Also changed %{fields}", fields: fields)

  defp import_line(%{"mode" => "create", "from" => from}), do: gettext("Created from %{source}", source: from)
  defp import_line(%{"mode" => "create"}), do: gettext("Created by the import")
  defp import_line(%{"from" => from}), do: gettext("Updated from %{source}", source: from)
  defp import_line(_), do: gettext("Updated by the import")

  attr :id, :string, required: true
  attr :comparison, :any, required: true, doc: "`{:ok, %{from:, to:, sections:}}` or `:error`"

  @doc "Two revisions side by side: every field and block field that differs."
  def comparison(%{comparison: :error} = assigns) do
    ~H"""
    <p class="activity-compare-empty">
      {gettext("One of these revisions is no longer kept, so they can't be compared.")}
    </p>
    """
  end

  def comparison(%{comparison: {:ok, result}} = assigns) do
    assigns =
      assign(assigns,
        result: result,
        description: gettext("Revision #%{from} → revision #%{to}", from: result.from, to: result.to),
        changed: Enum.reject(result.sections, &(&1[:kind] != :order and &1.before == &1.after))
      )

    ~H"""
    <div id={@id} class="activity-compare">
      <p :if={@changed == []} class="activity-compare-empty">
        {gettext("These revisions have the same content.")}
      </p>
      <%= for {section, index} <- Enum.with_index(@changed) do %>
        <section :if={section[:kind] == :order} class="draft-order-diff" aria-labelledby={"#{@id}-order-#{index}"}>
          <header>
            <h4 id={"#{@id}-order-#{index}"}>{section.title}</h4>
            <span class="draft-order-badge">{gettext("Order changed")}</span>
          </header>
          <ol>
            <li :for={move <- section.moves}>
              <div class="draft-order-item"><span>{move.title}</span></div>
              <span
                class="draft-order-positions"
                aria-label={gettext("Moved from position %{from} to %{to}", from: move.from, to: move.to)}
              >
                <span>{move.from}</span> <span aria-hidden="true">→</span> <span>{move.to}</span>
              </span>
            </li>
          </ol>
        </section>
        <TextDiff.diff
          :if={section[:kind] != :order}
          id={"#{@id}-section-#{index}"}
          label={section.title}
          before={section.before}
          after={section.after}
          description={@description}
        />
      <% end %>
    </div>
    """
  end
end
