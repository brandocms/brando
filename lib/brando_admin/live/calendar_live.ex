defmodule BrandoAdmin.CalendarLive do
  @moduledoc """
  The calendar, `/admin/calendar`: what is planned for entries by day, a
  month or a week at a time, across the content types with scheduled
  publishing, with a filter for one type. It shows entries to be published
  (`publish_at`), revisions scheduled to be published and expiries
  (`unpublish_at`), only those the user may read (`BrandoAdmin.Schedule`),
  in the site's time zone (`Brando.timezone/0`).

  An item the user may reschedule can be dragged to another day, or moved
  with its "Move to…" button, which opens a dialog with a date field: the
  keyboard's way, and the phone's. Either way the time of day is kept and the
  move is confirmed first; `BrandoAdmin.Schedule.reschedule/3` makes it the
  way the entry form or the revisions drawer would.

  Everything that selects what is shown is in the URL (`view`, `date`,
  `type`), so a view can be shared and the back button works. On a phone the
  days are a list of the days that have something planned.
  """
  use BrandoAdmin, :live_view
  use BrandoAdmin.Toast
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Workspace
  alias BrandoAdmin.Schedule

  @views ~w(month week)

  def __authorization__, do: {:access, :backend}

  def mount(_params, %{"user_token" => token}, socket) do
    if connected?(socket) do
      socket = assign_new(socket, :current_user, fn -> Brando.Users.get_user_by_session_token(token) end)
      put_locale(socket.assigns.current_user)

      {:ok,
       socket
       |> assign(:socket_connected, true)
       |> assign(:timezone, Brando.timezone())
       |> assign(:types, Schedule.types(socket.assigns.current_user))
       |> assign(:moving, nil)}
    else
      {:ok, assign(socket, :socket_connected, false)}
    end
  end

  defp put_locale(%{language: language}) when not is_nil(language), do: Gettext.put_locale(to_string(language))
  defp put_locale(_), do: nil

  def handle_params(params, _url, %{assigns: %{socket_connected: true}} = socket) do
    today = today()
    view = if params["view"] in @views, do: params["view"], else: "month"
    date = parse_date(params["date"]) || today
    type = Enum.find(socket.assigns.types, &(&1.key == params["type"]))

    {:noreply,
     socket
     |> assign(view: view, date: date, type: type, today: today, moving: nil)
     |> assign(:page_title, gettext("Calendar"))
     |> load()}
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  defp load(%{assigns: assigns} = socket) do
    {first, last} = span(assigns.view, assigns.date)
    days = Enum.to_list(Date.range(first, last))
    # From the first day's midnight up to the midnight after the last
    {from, to} = {midnight(first), midnight(Date.add(last, 1))}

    items =
      Schedule.items(assigns.current_user, from, to, schemas: schemas(assigns))
      |> Enum.group_by(&local_date(&1.at))

    focus = if assigns.date in days, do: assigns.date, else: hd(days)

    socket
    |> assign(:days, days)
    |> assign(:span, {first, last})
    |> assign(:items, items)
    |> assign(:count, items |> Map.values() |> Enum.map(&length/1) |> Enum.sum())
    |> assign(:focus, focus)
  end

  defp schemas(%{type: nil, types: types}), do: Enum.map(types, & &1.schema)
  defp schemas(%{type: type}), do: [type.schema]

  ## Dates, in the site's time zone

  defp today, do: Brando.timezone() |> DateTime.now!() |> DateTime.to_date()

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  # The first and last day the view shows: whole weeks, Monday first
  defp span("week", date), do: {Date.beginning_of_week(date), Date.end_of_week(date)}

  defp span("month", date),
    do: {Date.beginning_of_week(Date.beginning_of_month(date)), Date.end_of_week(Date.end_of_month(date))}

  # A day's first moment in the site's time zone, in UTC
  defp midnight(date), do: date |> local_datetime(~T[00:00:00]) |> DateTime.shift_zone!("Etc/UTC")

  # A wall-clock time that a daylight saving change skips or repeats takes
  # the time after the gap, or the first of the two
  defp local_datetime(date, time) do
    case DateTime.new(date, time, Brando.timezone()) do
      {:ok, datetime} -> datetime
      {:ambiguous, first, _second} -> first
      {:gap, _before, just_after} -> just_after
    end
  end

  defp local(at), do: DateTime.shift_zone!(at, Brando.timezone())
  defp local_date(at), do: at |> local() |> DateTime.to_date()

  # The item's time of day on `date`, in UTC
  defp moved_at(item, date) do
    time = item.at |> local() |> DateTime.to_time()
    date |> local_datetime(time) |> DateTime.shift_zone!("Etc/UTC")
  end

  defp step(%{view: "month", date: date}, direction), do: Date.shift(Date.beginning_of_month(date), month: direction)
  defp step(%{view: "week", date: date}, direction), do: Date.add(date, 7 * direction)

  defp path(assigns, changes) do
    params =
      Map.merge(%{view: assigns.view, date: assigns.date, type: assigns.type && assigns.type.key}, Map.new(changes))

    query =
      [
        {"view", if(params.view != "month", do: params.view)},
        {"date", if(params.date != assigns.today, do: Date.to_iso8601(params.date))},
        {"type", params.type}
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> URI.encode_query()

    if query == "", do: "/admin/calendar", else: "/admin/calendar?" <> query
  end

  ## Events

  def handle_event("filter", %{"type" => type}, socket) do
    type = if type == "", do: nil, else: type
    {:noreply, push_patch(socket, to: path(socket.assigns, type: type))}
  end

  def handle_event("start_move", %{"item" => id}, socket) do
    case find(socket, id) do
      %{movable?: true} = item -> {:noreply, assign(socket, :moving, %{item: item, date: local_date(item.at)})}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("cancel_move", _params, socket), do: {:noreply, assign(socket, :moving, nil)}

  def handle_event("move_date", %{"date" => date}, %{assigns: %{moving: %{} = moving}} = socket) do
    case parse_date(date) do
      nil -> {:noreply, socket}
      date -> {:noreply, assign(socket, :moving, %{moving | date: date})}
    end
  end

  def handle_event("move_date", _params, socket), do: {:noreply, socket}

  # A drag asks what dropping would do, and the hook asks the user that
  def handle_event("describe_move", %{"item" => id, "date" => date}, socket) do
    with %{movable?: true} = item <- find(socket, id),
         %Date{} = date <- parse_date(date) do
      {:reply,
       %{
         title: escape(gettext("Move “%{title}”?", title: item.title)),
         message: escape(move_summary(item, date)),
         confirm: gettext("Move")
       }, socket}
    else
      _ -> {:reply, %{error: true}, socket}
    end
  end

  def handle_event("move", %{"item" => id, "date" => date}, socket) do
    user = socket.assigns.current_user

    with %{movable?: true} = item <- find(socket, id),
         %Date{} = date <- parse_date(date),
         {:ok, moved} <- Schedule.reschedule(user, item, moved_at(item, date)) do
      send(
        self(),
        {:toast, gettext("“%{title}” moved to %{date}", title: item.title, date: BrandoAdmin.Dates.long(moved.at))}
      )

      {:noreply, socket |> assign(:moving, nil) |> load()}
    else
      {:error, :changed} = error ->
        # Someone changed it since the calendar was read: show what is planned now
        {:noreply,
         socket
         |> assign(:moving, nil)
         |> load()
         |> push_event("b:alert", %{
           type: "warning",
           title: escape(gettext("Not moved")),
           message: escape(move_error(error))
         })}

      error ->
        {:noreply,
         push_event(socket, "b:alert", %{
           type: "error",
           title: escape(gettext("Not moved")),
           message: escape(move_error(error))
         })}
    end
  end

  defp find(socket, id) do
    socket.assigns.items |> Map.values() |> List.flatten() |> Enum.find(&(&1.id == id))
  end

  defp move_error({:error, :in_the_past}), do: gettext("Choose a day and time that has not passed.")

  defp move_error({:error, :changed}),
    do: gettext("It was changed since the calendar was loaded. The calendar now shows what is planned.")

  defp move_error({:error, %Ecto.Changeset{errors: errors}}) when errors != [] do
    Enum.map_join(errors, " ", fn {_field, {message, opts}} ->
      BrandoAdmin.Components.Form.Primitives.translate_error({message, opts})
    end)
  end

  defp move_error({:error, :forbidden}), do: gettext("You may not reschedule this entry.")
  defp move_error(_error), do: gettext("The entry could not be moved. Reload the calendar and try again.")

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  ## Copy

  defp move_summary(item, date) do
    from = BrandoAdmin.Dates.long(item.at)
    to = BrandoAdmin.Dates.long(moved_at(item, date))

    case item.kind do
      :publish -> gettext("Publishing moves from %{from} to %{to}.", from: from, to: to)
      :revision -> gettext("The scheduled revision moves from %{from} to %{to}.", from: from, to: to)
      :expire -> gettext("The expiry moves from %{from} to %{to}.", from: from, to: to)
    end
  end

  defp kind_label(:publish), do: gettext("Publishes")
  defp kind_label(:revision), do: gettext("Revision is published")
  defp kind_label(:expire), do: gettext("Expires")

  defp kind_icon(:publish), do: "send"
  defp kind_icon(:revision), do: "rotate-ccw-clock"
  defp kind_icon(:expire), do: "calendar-x"

  defp locale, do: Gettext.get_locale(Brando.Gettext)

  defp month_name(month), do: Brando.Utils.Datetime.get_month_name(month, locale())

  defp weekday(date, length),
    do: date |> Date.day_of_week() |> Brando.Utils.Datetime.get_day_name(locale()) |> shorten(length)

  defp shorten(name, :short), do: String.slice(name, 0, 3)
  defp shorten(name, :long), do: name

  defp heading(%{view: "month", date: date}), do: "#{String.capitalize(month_name(date.month))} #{date.year}"

  defp heading(%{view: "week", span: {first, last}}) do
    cond do
      first.month == last.month -> "#{day_number(first)}–#{day_number(last)} #{month_name(last.month)} #{last.year}"
      first.year == last.year -> "#{day_month(first)} – #{day_month(last)} #{last.year}"
      true -> "#{day_month(first)} #{first.year} – #{day_month(last)} #{last.year}"
    end
  end

  defp day_number(date), do: if(locale() == "en", do: "#{date.day}", else: "#{date.day}.")
  defp day_month(date), do: "#{day_number(date)} #{month_name(date.month)}"

  # "Wednesday 14 October 2026, 2 items"
  defp day_label(date, count) do
    "#{String.capitalize(weekday(date, :long))} #{day_month(date)} #{date.year}, " <>
      ngettext("%{count} item", "%{count} items", count)
  end

  defp time(at), do: at |> local() |> Calendar.strftime("%H:%M")

  defp step_label("month", -1), do: gettext("Previous month")
  defp step_label("month", 1), do: gettext("Next month")
  defp step_label("week", -1), do: gettext("Previous week")
  defp step_label("week", 1), do: gettext("Next week")

  defp view_label("month"), do: gettext("Month")
  defp view_label("week"), do: gettext("Week")

  defp empty_label("month"), do: gettext("Nothing is planned this month.")
  defp empty_label("week"), do: gettext("Nothing is planned this week.")

  ## Rendering

  def render(%{socket_connected: false} = assigns) do
    ~H"""
    """
  end

  def render(assigns) do
    assigns = assign(assigns, :views, @views)

    ~H"""
    <div class="admin-workspace calendar-workspace" id="calendar-workspace">
      <Workspace.header
        title={gettext("Calendar")}
        subtitle={
          gettext("Publishing, scheduled revisions and expiries you can read, in %{timezone} time.", timezone: @timezone)
        }
      />

      <div class="calendar-toolbar">
        <div class="calendar-nav">
          <.link
            patch={path(assigns, date: step(assigns, -1))}
            class="calendar-step"
            id="calendar-previous"
            aria-label={step_label(@view, -1)}
            title={step_label(@view, -1)}
          >
            <.icon name="chevron-left" />
          </.link>
          <h2 id="calendar-title" aria-live="polite">{heading(assigns)}</h2>
          <.link
            patch={path(assigns, date: step(assigns, 1))}
            class="calendar-step"
            id="calendar-next"
            aria-label={step_label(@view, 1)}
            title={step_label(@view, 1)}
          >
            <.icon name="chevron-right" />
          </.link>
          <.link patch={path(assigns, date: @today)} class="workspace-button calendar-today" id="calendar-today">
            {gettext("Today")}
          </.link>
        </div>
        <div class="calendar-controls">
          <nav class="calendar-views" aria-label={gettext("Calendar view")}>
            <.link
              :for={view <- @views}
              patch={path(assigns, view: view)}
              id={"calendar-view-#{view}"}
              aria-current={view == @view && "page"}
              class={view == @view && "active"}
            >
              {view_label(view)}
            </.link>
          </nav>
          <form id="calendar-filter" phx-change="filter">
            <label>
              <span class="visually-hidden">{gettext("Content type")}</span>
              <select id="calendar-type" name="type" class="admin-select">
                <option value="">{gettext("All content types")}</option>
                <option :for={type <- @types} value={type.key} selected={@type && @type.key == type.key}>
                  {type.label}
                </option>
              </select>
            </label>
          </form>
        </div>
      </div>

      <ul class="calendar-legend" aria-label={gettext("What the icons mean")}>
        <li :for={kind <- [:publish, :revision, :expire]} class={"is-#{kind}"}>
          <.icon name={kind_icon(kind)} />{kind_label(kind)}
        </li>
      </ul>

      <div
        id="calendar"
        class={["calendar", "calendar--#{@view}"]}
        phx-hook="Brando.Calendar"
        data-view={@view}
      >
        <div class="calendar-weekdays" aria-hidden="true">
          <span :for={day <- Enum.take(@days, 7)}>{weekday(day, :short)}</span>
        </div>
        <ol class="calendar-days" aria-labelledby="calendar-title">
          <li
            :for={day <- @days}
            id={"calendar-day-#{day}"}
            class={[
              "calendar-day",
              @view == "month" && day.month != @date.month && "is-outside",
              day == @today && "is-today",
              Map.get(@items, day, []) == [] && "is-empty"
            ]}
            data-calendar-day={Date.to_iso8601(day)}
            tabindex={if day == @focus, do: "0", else: "-1"}
            aria-label={day_label(day, length(Map.get(@items, day, [])))}
            aria-current={day == @today && "date"}
          >
            <div class="calendar-day-heading" aria-hidden="true">
              <span class="calendar-day-number">{day.day}</span>
              <span class="calendar-day-date">{String.capitalize(weekday(day, :long))} {day_month(day)}</span>
              <span :if={day == @today} class="calendar-day-today">{gettext("Today")}</span>
            </div>
            <ul :if={Map.get(@items, day, []) != []} class="calendar-items">
              <.item :for={item <- Map.get(@items, day, [])} item={item} view={@view} />
            </ul>
          </li>
        </ol>
        <p :if={@count == 0} class="calendar-empty" id="calendar-empty" role="status">{empty_label(@view)}</p>
      </div>

      <Content.modal
        :if={@moving}
        id="calendar-move"
        title={gettext("Move to another day")}
        subtitle={@moving.item.title}
        icon="move"
        narrow
        show
        close={JS.push("cancel_move")}
      >
        <form id="calendar-move-form" class="calendar-move" phx-change="move_date" phx-submit="move">
          <input type="hidden" name="item" value={@moving.item.id} />
          <label for="calendar-move-date">{gettext("Day")}</label>
          <input
            id="calendar-move-date"
            class="calendar-move-date"
            type="date"
            name="date"
            value={Date.to_iso8601(@moving.date)}
            min={Date.to_iso8601(@today)}
            required
          />
          <p class="calendar-move-summary" id="calendar-move-summary" aria-live="polite">
            {move_summary(@moving.item, @moving.date)}
          </p>
          <div class="calendar-move-actions">
            <button type="button" class="workspace-button" phx-click="cancel_move">{gettext("Cancel")}</button>
            <button type="submit" class="workspace-button primary" id="calendar-move-submit">{gettext("Move")}</button>
          </div>
        </form>
      </Content.modal>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :view, :string, required: true

  defp item(assigns) do
    ~H"""
    <li
      id={"calendar-item-#{@item.id}"}
      class={["calendar-item", "is-#{@item.kind}", @item.movable? && "is-movable"]}
      data-calendar-item={@item.id}
      data-kind={@item.kind}
      draggable={@item.movable? && "true"}
      title={"#{kind_label(@item.kind)} · #{@item.type} · #{BrandoAdmin.Dates.full(@item.at)}"}
    >
      <span class="calendar-item-head">
        <.icon name={kind_icon(@item.kind)} class="calendar-item-icon" />
        <time class="calendar-item-time" datetime={DateTime.to_iso8601(@item.at)}>{time(@item.at)}</time>
        <span class="visually-hidden">{kind_label(@item.kind)}:</span>
      </span>
      <.link
        :if={@item.path}
        navigate={@item.path}
        class="calendar-item-title"
        draggable={@item.movable? && "false"}
      >
        {@item.title}
      </.link>
      <span :if={!@item.path} class="calendar-item-title">{@item.title}</span>
      <span class="calendar-item-meta">
        {@item.type}<span :if={@item.language}> · {String.upcase(@item.language)}</span>
      </span>
      <%!-- After the title, so Tab reaches it from the link; drawn in the
           top corner --%>
      <button
        :if={@item.movable?}
        type="button"
        class="calendar-item-move"
        phx-click="start_move"
        phx-value-item={@item.id}
        aria-label={gettext("Move “%{title}” to another day", title: @item.title)}
        title={gettext("Move to…")}
      >
        <.icon name="move" />
      </button>
    </li>
    """
  end
end
