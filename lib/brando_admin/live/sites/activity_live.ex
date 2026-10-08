defmodule BrandoAdmin.Sites.ActivityLive do
  @moduledoc """
  Configuration → Activity: who created, changed, published, trashed,
  restored and deleted content, and when (`Brando.Activity`). Filters live in
  the URL, so a filtered view can be shared. Compare shows what a change did,
  from the revisions it saved.

  The Security view (`?view=security`) lists every user's sign-in security
  events (`Brando.Users.SecurityLog`) to those `SecurityLog.readable_by?/1`
  allows, checked again on every load; anyone else gets the content log.
  """
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias Brando.Activity
  alias Brando.Users.SecurityLog
  alias BrandoAdmin.Components.Activity, as: Events
  alias BrandoAdmin.Components.Activity.Comparison
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.TwoFactor, as: Security

  on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, __MODULE__}})

  @page_size 50
  @periods ~w(1 7 30 365 all)

  def __authorization__, do: {:read, :activity}

  def mount(_params, %{"user_token" => token}, socket) do
    if connected?(socket) do
      socket = assign_current_user(socket, token)

      if allowed?(socket.assigns.current_user) do
        {:ok,
         socket
         |> assign(:socket_connected, true)
         |> set_admin_locale()
         |> assign(:limit, @page_size)
         |> assign(:comparison, nil)
         |> assign(:readable, readable_schemas())
         |> assign_options()}
      else
        {:ok, redirect(socket, to: "/admin/access-denied")}
      end
    else
      {:ok, assign(socket, :socket_connected, false)}
    end
  end

  defp assign_current_user(socket, token),
    do: assign_new(socket, :current_user, fn -> Brando.Users.get_user_by_session_token(token) end)

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language |> to_string() |> Gettext.put_locale()
    socket
  end

  # Without group authorization, the log is for administrators; with it, the
  # `brando.activity.read` permission decides (`__authorization__/0`).
  defp allowed?(user) do
    Brando.Authorization.enabled?() or match?(%{role: role} when role in [:admin, :superuser], user)
  end

  # Events of schemas the user may not read stay out of the log; changes to
  # webhooks show to those who manage them.
  defp readable_schemas do
    if Brando.Authorization.enabled?() do
      readable = Enum.filter(Activity.schemas(), &BrandoAdmin.Authorization.allowed?(:read, &1))

      readable =
        if BrandoAdmin.Authorization.allowed?(:manage, :webhooks),
          do: [Brando.Webhooks.Webhook | readable],
          else: readable

      # Connected AI tools: connections, their tool calls and the switch
      if BrandoAdmin.Authorization.allowed?(:manage, :mcp),
        do: [Brando.MCP.Grant, Brando.MCP.Setting | readable],
        else: readable
    end
  end

  defp assign_options(socket) do
    socket
    |> assign(:people, Activity.users())
    |> assign(:types, Activity.schemas() |> Enum.map(&{Events.type_label(&1) || inspect(&1), to_string(&1)}))
    |> assign(:actions, Events.action_options())
    |> assign(:periods, [
      {gettext("Today"), "1"},
      {gettext("Last 7 days"), "7"},
      {gettext("Last 30 days"), "30"},
      {gettext("Last 12 months"), "365"},
      {gettext("All kept activity"), "all"}
    ])
  end

  def handle_params(params, _url, %{assigns: %{socket_connected: true}} = socket) do
    security_log? = SecurityLog.readable_by?(socket.assigns.current_user)
    socket = assign(socket, :security_log?, security_log?)

    if params["view"] == "security" and security_log?,
      do: security_params(params, socket),
      else: content_params(params, socket)
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  defp content_params(params, socket) do
    filters = %{
      "q" => params["q"] || "",
      "user" => params["user"] || "",
      "type" => params["type"] || "",
      "action" => params["action"] || "",
      "period" => if(params["period"] in @periods, do: params["period"], else: "7")
    }

    {:noreply, socket |> assign(view: :content, filters: filters, limit: @page_size) |> load()}
  end

  defp security_params(params, socket) do
    filters = %{
      "user" => params["user"] || "",
      "event" => if(parse_event(params["event"]), do: params["event"], else: ""),
      "period" => if(params["period"] in @periods, do: params["period"], else: "7")
    }

    {:noreply,
     socket
     |> assign(view: :security, filters: filters, limit: @page_size)
     |> assign_new(:security_people, &SecurityLog.users/0)
     |> assign_new(:security_actions, &Security.action_options/0)
     |> load()}
  end

  defp parse_event(value), do: Enum.find(Brando.Users.SecurityEvent.actions(), &(to_string(&1) == value))
  # Read again on every load: the permission may have gone since the view opened.
  defp load(%{assigns: %{view: :security, current_user: user, filters: filters}} = socket) do
    if SecurityLog.readable_by?(user) do
      query = %{
        user_id: parse_id(filters["user"]),
        action: parse_event(filters["event"]),
        since: since(filters["period"])
      }

      events = SecurityLog.list_all(query, limit: socket.assigns.limit)

      socket
      |> assign(:count, SecurityLog.count_all(query))
      |> assign(:events, events)
      |> assign(:days, events |> Enum.map(&{:event, &1}) |> Events.by_day())
    else
      socket |> assign(security_log?: false, view: :content, count: 0, events: [], days: [])
    end
  end

  defp load(socket) do
    filters = query_filters(socket.assigns.filters, socket.assigns.readable)
    events = Activity.list(filters, limit: socket.assigns.limit)

    socket
    |> assign(:count, Activity.count(filters))
    |> assign(:events, events)
    |> assign(:states, Events.states(events))
    |> assign(:days, events |> Events.items() |> Events.by_day())
  end

  defp query_filters(filters, readable) do
    %{
      q: filters["q"],
      user_id: parse_id(filters["user"]),
      schema: filters["type"],
      action: parse_action(filters["action"]),
      since: since(filters["period"]),
      schema_in: readable
    }
  end

  defp parse_id(""), do: nil

  defp parse_id(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp parse_action(value) do
    Enum.find(Brando.Activity.Event.actions(), &(to_string(&1) == value))
  end

  defp since("all"), do: nil
  defp since(days), do: DateTime.add(DateTime.utc_now(), -String.to_integer(days) * 86_400, :second)

  def handle_event("filter", params, socket) do
    query =
      params
      |> Map.take(~w(q user type action period))
      |> Enum.reject(fn {key, value} -> value == "" or (key == "period" and value == "7") end)

    {:noreply, push_patch(socket, to: "/admin/config/activity?" <> URI.encode_query(query))}
  end

  def handle_event("filter_security", params, socket) do
    query =
      params
      |> Map.take(~w(user event period))
      |> Enum.reject(fn {key, value} -> value == "" or (key == "period" and value == "7") end)
      |> Enum.concat([{"view", "security"}])

    {:noreply, push_patch(socket, to: "/admin/config/activity?" <> URI.encode_query(query))}
  end

  def handle_event("load_more", _, socket) do
    {:noreply, socket |> assign(:limit, socket.assigns.limit + @page_size) |> load()}
  end

  def handle_event("compare", %{"id" => id}, socket) do
    with :content <- socket.assigns.view,
         event when not is_nil(event) <- Enum.find(socket.assigns.events, &(to_string(&1.id) == id)),
         schema when not is_nil(schema) <- Events.schema(event.schema),
         {from, to} <- Comparison.revisions(event) do
      result = Comparison.build(schema, event.entry_id, from, to, socket.assigns.current_user)
      {:noreply, assign(socket, :comparison, %{event: event, result: result})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("close_compare", _, socket), do: {:noreply, assign(socket, :comparison, nil)}

  def render(%{socket_connected: false} = assigns) do
    ~H"""
    """
  end

  def render(assigns) do
    ~H"""
    <div class="utils-workspace activity-workspace">
      <header class="utils-page-heading">
        <div>
          <span class="utils-eyebrow">{gettext("Configuration")}</span>
          <h1>{gettext("Activity")}</h1>
          <p :if={@view == :content}>
            {gettext(
              "Who created, changed, published and deleted content, and when. Changes that saved a revision can be compared with the one before."
            )}
          </p>
          <p :if={@view == :security}>
            {gettext(
              "Every user's sign-ins, failed attempts and lockouts, and changes to passwords, two-factor authentication, passkeys, sessions and connected apps."
            )}
          </p>
        </div>
        <span class="utils-version">
          {ngettext("Kept for %{count} day", "Kept for %{count} days", Activity.retention_days())}
        </span>
      </header>

      <nav :if={@security_log?} class="pill-tabs activity-views" aria-label={gettext("Activity views")}>
        <.link patch="/admin/config/activity" aria-current={@view == :content && "page"}>
          <.icon name="file-text" />{gettext("Content")}
        </.link>
        <.link patch="/admin/config/activity?view=security" aria-current={@view == :security && "page"}>
          <.icon name="shield" />{gettext("Security")}
        </.link>
      </nav>

      <.security_log
        :if={@view == :security}
        filters={@filters}
        people={@security_people}
        actions={@security_actions}
        periods={@periods}
        count={@count}
        events={@events}
        days={@days}
      />

      <form
        :if={@view == :content}
        id="activity-filters"
        class="activity-toolbar"
        role="search"
        phx-change="filter"
        phx-submit="filter"
      >
        <label class="activity-search">
          <span class="sr-only">{gettext("Search entries")}</span>
          <.icon name="search" />
          <input
            type="search"
            name="q"
            value={@filters["q"]}
            placeholder={gettext("Search entries")}
            phx-debounce="300"
            autocomplete="off"
          />
        </label>
        <label>
          <span class="sr-only">{gettext("Person")}</span>
          <select name="user" class="admin-select">
            <option value="">{gettext("Everyone")}</option>
            <option :for={user <- @people} value={user.id} selected={@filters["user"] == to_string(user.id)}>
              {user.name}
            </option>
          </select>
        </label>
        <label>
          <span class="sr-only">{gettext("Content type")}</span>
          <select name="type" class="admin-select">
            <option value="">{gettext("All content types")}</option>
            <option :for={{label, value} <- @types} value={value} selected={@filters["type"] == value}>{label}</option>
          </select>
        </label>
        <label>
          <span class="sr-only">{gettext("Action")}</span>
          <select name="action" class="admin-select">
            <option value="">{gettext("All actions")}</option>
            <option :for={{label, value} <- @actions} value={value} selected={@filters["action"] == value}>
              {label}
            </option>
          </select>
        </label>
        <label>
          <span class="sr-only">{gettext("Period")}</span>
          <select name="period" class="admin-select">
            <option :for={{label, value} <- @periods} value={value} selected={@filters["period"] == value}>
              {label}
            </option>
          </select>
        </label>
        <span class="activity-count" role="status">
          {ngettext("%{count} event", "%{count} events", @count)}
        </span>
      </form>

      <p :if={@view == :content and @days == []} class="activity-empty">
        {gettext("Nothing has happened in this period.")}
      </p>

      <section
        :for={{date, items} <- @days}
        :if={@view == :content}
        class="activity-day"
        aria-labelledby={"activity-day-#{date}"}
      >
        <h2 id={"activity-day-#{date}"}>
          {Events.day_label(date)} <span>{Events.short_date(date)}</span>
        </h2>
        <ol class="activity-list">
          <.item :for={item <- items} item={item} states={@states} />
        </ol>
      </section>

      <div :if={@view == :content and @count > length(@events)} class="activity-more">
        <span>{gettext("Showing %{shown} of %{count}", shown: length(@events), count: @count)}</span>
        <button type="button" class="utils-button" phx-click="load_more">{gettext("Load older activity")}</button>
      </div>

      <Content.modal
        :if={@comparison}
        id="activity-compare-modal"
        title={gettext("Compare revisions")}
        subtitle={@comparison.event.title}
        icon="arrow-left-right"
        show
        wide
        close={JS.push("close_compare")}
      >
        <Events.comparison id="activity-comparison" comparison={@comparison.result} />
      </Content.modal>
    </div>
    """
  end

  attr :filters, :map, required: true
  attr :people, :list, required: true
  attr :actions, :list, required: true
  attr :periods, :list, required: true
  attr :count, :integer, required: true
  attr :events, :list, required: true
  attr :days, :list, required: true

  # Everyone's sign-in security events, in the content log's layout. Only
  # what the user's own security page shows: the event, who else acted, the
  # address and the browser. The rest of `details` is never rendered.
  defp security_log(assigns) do
    ~H"""
    <form
      id="security-filters"
      class="activity-toolbar"
      role="search"
      phx-change="filter_security"
      phx-submit="filter_security"
    >
      <label>
        <span class="sr-only">{gettext("Person")}</span>
        <select name="user" class="admin-select">
          <option value="">{gettext("Everyone")}</option>
          <option :for={user <- @people} value={user.id} selected={@filters["user"] == to_string(user.id)}>
            {user.name}
          </option>
        </select>
      </label>
      <label>
        <span class="sr-only">{gettext("Event")}</span>
        <select name="event" class="admin-select">
          <option value="">{gettext("All events")}</option>
          <option :for={{label, value} <- @actions} value={value} selected={@filters["event"] == value}>{label}</option>
        </select>
      </label>
      <label>
        <span class="sr-only">{gettext("Period")}</span>
        <select name="period" class="admin-select">
          <option :for={{label, value} <- @periods} value={value} selected={@filters["period"] == value}>
            {label}
          </option>
        </select>
      </label>
      <span class="activity-count" role="status">
        {ngettext("%{count} event", "%{count} events", @count)}
      </span>
    </form>

    <div data-testid="security-log">
      <p :if={@days == []} class="activity-empty">
        {gettext("Nothing has happened in this period.")}
      </p>

      <section :for={{date, items} <- @days} class="activity-day" aria-labelledby={"security-day-#{date}"}>
        <h2 id={"security-day-#{date}"}>
          {Events.day_label(date)} <span>{Events.short_date(date)}</span>
        </h2>
        <ol class="activity-list">
          <.security_row :for={{:event, event} <- items} event={event} />
        </ol>
      </section>

      <div :if={@count > length(@events)} class="activity-more">
        <span>{gettext("Showing %{shown} of %{count}", shown: length(@events), count: @count)}</span>
        <button type="button" class="utils-button" phx-click="load_more">{gettext("Load older events")}</button>
      </div>
    </div>
    """
  end

  attr :event, :any, required: true

  defp security_row(assigns) do
    event = assigns.event

    assigns =
      assign(assigns,
        actor: event.actor_id && event.actor_id != event.user_id && event.actor,
        until: event.action == :locked && locked_until(event.details["until"])
      )

    ~H"""
    <li class="activity-row security-log-row" id={"security-event-#{@event.id}"} data-action={@event.action}>
      <time datetime={DateTime.to_iso8601(@event.inserted_at)}>{Events.time(@event.inserted_at)}</time>
      <div class="activity-person">
        <Events.avatar user={@event.user} />
        <span class="activity-person-name">{(@event.user && @event.user.name) || gettext("Unknown account")}</span>
      </div>
      <div class="activity-event">
        <p class="activity-headline">
          <span class={["activity-action", "is-security", Security.negative?(@event.action) && "is-negative"]}>
            <i aria-hidden="true"></i>{Security.event_label(@event)}
          </span>
        </p>
        <p :if={@actor || @until} class="activity-detail">
          {[@actor && gettext("by %{name}", name: @actor.name), @until && gettext("Locked until %{time}", time: @until)]
          |> Enum.filter(& &1)
          |> Enum.join(" · ")}
        </p>
      </div>
      <div :if={@event.ip || @event.user_agent} class="activity-links security-log-origin">
        <span :if={@event.ip} class="security-log-ip">{@event.ip}</span>
        <span :if={@event.user_agent} title={@event.user_agent}>{Security.browser(@event.user_agent)}</span>
      </div>
    </li>
    """
  end

  defp locked_until(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, until, _} -> Events.time(until)
      _ -> nil
    end
  end

  defp locked_until(_), do: nil

  attr :item, :any, required: true
  attr :states, :map, required: true

  defp item(%{item: {:event, event}} = assigns) do
    assigns =
      assign(assigns,
        event: event,
        compare?: not is_nil(Comparison.revisions(event)) and not is_nil(Events.entry_path(event, assigns.states)),
        trash_path: Events.trash_path(event, assigns.states)
      )

    ~H"""
    <li class="activity-row" id={"activity-event-#{@event.id}"}>
      <time datetime={DateTime.to_iso8601(@event.inserted_at)}>{Events.time(@event.inserted_at)}</time>
      <Events.person event={@event} />
      <div class="activity-event">
        <p class="activity-headline">
          <Events.action event={@event} />
          <Events.entry event={@event} states={@states} />
        </p>
        <Events.details event={@event} states={@states} />
      </div>
      <div class="activity-links">
        <button
          :if={@compare?}
          type="button"
          class="utils-button"
          phx-click="compare"
          phx-value-id={@event.id}
        >
          {gettext("Compare")}
        </button>
        <.link :if={@trash_path} navigate={@trash_path} class="utils-button">{gettext("Open trash")}</.link>
        <span :if={@event.revision} class="activity-revision">
          {gettext("Revision #%{revision}", revision: @event.revision)}
        </span>
      </div>
    </li>
    """
  end

  # One content import: the entries it created and updated, together.
  defp item(%{item: {:batch, [first | _] = events}} = assigns) do
    {created, updated} = Enum.split_with(events, &(&1.details["mode"] == "create"))

    assigns =
      assign(assigns,
        event: first,
        events: events,
        created: created,
        updated: updated,
        from: first.details["from"]
      )

    ~H"""
    <li class="activity-row" id={"activity-batch-#{@event.batch_id}"}>
      <time datetime={DateTime.to_iso8601(@event.inserted_at)}>{Events.time(@event.inserted_at)}</time>
      <Events.person event={@event} />
      <div class="activity-event">
        <p class="activity-headline">
          <Events.action event={@event} />
          <span class="activity-entry">
            {ngettext("%{count} entry", "%{count} entries", length(@events))}
          </span>
          <span :if={@from} class="activity-type">{gettext("from %{source}", source: @from)}</span>
        </p>
        <p :if={@created != []} class="activity-detail">
          {gettext("Created")}: <.entry_list events={@created} states={@states} />
        </p>
        <p :if={@updated != []} class="activity-detail">
          {gettext("Updated")}: <.entry_list events={@updated} states={@states} />
        </p>
      </div>
      <div class="activity-links"></div>
    </li>
    """
  end

  attr :events, :list, required: true
  attr :states, :map, required: true

  defp entry_list(assigns) do
    ~H"""
    <%= for {event, index} <- Enum.with_index(@events) do %>
      {if index > 0, do: ", "}<.link
        :if={Events.entry_path(event, @states)}
        navigate={Events.entry_path(event, @states)}
      >{event.title}</.link><span :if={!Events.entry_path(event, @states)}>{event.title}</span>
    <% end %>
    """
  end
end
