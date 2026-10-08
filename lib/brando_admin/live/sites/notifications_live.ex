defmodule BrandoAdmin.Sites.NotificationsLive do
  @moduledoc """
  Configuration → Integrations → Notifications
  (`Brando.Notifications.Routing`): the routes, the route form and the
  delivery log, for the current site environment. Laid out like the
  webhook screens (`BrandoAdmin.Sites.WebhooksLive`).

  Everything that changes a route or sends on it — saving, deleting,
  pausing, resuming, a test notification — asks for the password again when
  the session has not confirmed lately (`BrandoAdmin.Reauth`). A saved
  webhook URL never reaches the browser again: the form shows its host and
  last characters, and replacing it starts from an empty field.
  """
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias Brando.ContentEvents.Event
  alias Brando.Notifications.Message
  alias Brando.Notifications.Route
  alias Brando.Notifications.Routing
  alias Brando.Webhooks
  alias BrandoAdmin.Components.Workspace
  alias BrandoAdmin.Toast

  on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, __MODULE__}})
  on_mount({BrandoAdmin.Reauth, events: ~w(save delete pause resume send_test)})

  @log_limit 100

  def __authorization__, do: {:manage, :notifications}

  def mount(_params, _session, socket) do
    if Routing.can_manage?(socket.assigns.current_user) do
      if connected?(socket), do: Phoenix.PubSub.subscribe(Brando.pubsub(), Routing.topic())

      {:ok,
       socket
       |> assign(:socket_connected, connected?(socket))
       |> assign(:event_options, event_options())
       |> assign(:kind_options, kind_options())
       |> assign(:type_labels, type_labels())
       |> assign(:entry_type_options, entry_type_options())
       |> assign(:recipient_options, Routing.recipient_options())
       |> assign(:replace_url?, false)
       |> assign(:submitted?, false)
       |> assign(:route, nil)
       |> assign(:deliveries, [])}
    else
      {:ok, redirect(socket, to: "/admin/access-denied")}
    end
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, gettext("Notifications"))
    |> assign(:route, nil)
    |> assign(:routes, Routing.list_routes())
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, gettext("New notification route"))
    |> assign(:route, nil)
    |> assign(:submitted?, false)
    |> assign_form(Routing.change_route(%Route{kind: :slack}, %{}, resolve: false))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    with_route(socket, id, fn socket, route ->
      socket
      |> assign(:page_title, gettext("Edit notification route"))
      |> assign(:route, route)
      |> assign(:replace_url?, false)
      |> assign(:submitted?, false)
      |> assign_form(Routing.change_route(route, %{}, resolve: false))
    end)
  end

  defp apply_action(socket, :deliveries, %{"id" => id}) do
    with_route(socket, id, fn socket, route ->
      socket
      |> assign(:page_title, gettext("Delivery log"))
      |> assign(:route, route)
      |> assign(:deliveries, Routing.list_deliveries(route, limit: @log_limit))
    end)
  end

  defp apply_action(socket, :deliveries, _params) do
    socket
    |> assign(:page_title, gettext("Delivery log"))
    |> assign(:route, nil)
    |> assign(:deliveries, Routing.list_all_deliveries(limit: @log_limit))
  end

  # Ids come from the URL: only a route of this environment is found.
  defp with_route(socket, id, fun) do
    case Routing.get_route(id) do
      {:ok, route} ->
        fun.(socket, route)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, gettext("That notification route does not exist in this environment."))
        |> push_navigate(to: "/admin/config/notifications")
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: :route))

  # Errors show for the fields a person has used, and for all once they save
  defp submitted(socket, changeset), do: socket |> assign(:submitted?, true) |> assign_form(changeset)

  ## Events

  def handle_event("validate", %{"route" => params}, socket) do
    params = normalize(params)
    changeset = Routing.change_route(socket.assigns.route || %Route{}, params, resolve: false)
    {:noreply, assign_form(socket, %{changeset | action: :validate})}
  end

  def handle_event("save", %{"route" => params}, socket) do
    params = normalize(params)
    user = socket.assigns.current_user

    result =
      case socket.assigns.route do
        nil -> Routing.create_route(params, user)
        %Route{} = route -> Routing.update_route(route, params, user)
      end

    case result do
      {:ok, route} ->
        Toast.send_to(user, gettext("The notification route was saved."))

        {:noreply,
         socket
         |> assign(:route, route)
         |> assign(:replace_url?, false)
         |> assign(:submitted?, false)
         |> assign_form(Routing.change_route(route, %{}, resolve: false))
         |> then(
           &if(socket.assigns.route, do: &1, else: push_patch(&1, to: "/admin/config/notifications/#{route.id}/edit"))
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, submitted(socket, changeset)}

      {:error, _} ->
        {:noreply, error(socket)}
    end
  end

  def handle_event("replace_url", _params, socket), do: {:noreply, assign(socket, :replace_url?, true)}

  def handle_event("pause", _params, %{assigns: %{route: %Route{} = route}} = socket) do
    {:noreply, after_change(socket, Routing.pause(route, :manual, socket.assigns.current_user))}
  end

  def handle_event("resume", _params, %{assigns: %{route: %Route{} = route}} = socket) do
    {:noreply, after_change(socket, Routing.resume(route, socket.assigns.current_user))}
  end

  def handle_event("delete", _params, %{assigns: %{route: %Route{} = route}} = socket) do
    case Routing.delete_route(route, socket.assigns.current_user) do
      {:ok, _} ->
        Toast.send_to(socket.assigns.current_user, gettext("The notification route was deleted."))
        {:noreply, push_navigate(socket, to: "/admin/config/notifications")}

      _ ->
        {:noreply, error(socket)}
    end
  end

  def handle_event("send_test", _params, %{assigns: %{route: %Route{} = route}} = socket) do
    case Routing.send_test(route, socket.assigns.current_user) do
      {:ok, _deliveries} ->
        Toast.send_to(socket.assigns.current_user, gettext("A test notification was sent."))
        {:noreply, reload(socket)}

      {:error, :paused} ->
        {:noreply, error(socket, gettext("Resume the route to send on it."))}

      _ ->
        {:noreply, error(socket)}
    end
  end

  def handle_info({Routing, _message}, socket), do: {:noreply, reload(socket)}

  defp after_change(socket, {:ok, route}), do: assign(socket, :route, route)
  defp after_change(socket, _error), do: error(socket)

  defp reload(%{assigns: %{live_action: :index}} = socket), do: assign(socket, :routes, Routing.list_routes())

  defp reload(%{assigns: %{live_action: :deliveries, route: %Route{} = route}} = socket) do
    case Routing.get_route(route.id) do
      {:ok, route} ->
        socket
        |> assign(:route, route)
        |> assign(:deliveries, Routing.list_deliveries(route, limit: @log_limit))

      _ ->
        socket
    end
  end

  defp reload(%{assigns: %{live_action: :deliveries}} = socket),
    do: assign(socket, :deliveries, Routing.list_all_deliveries(limit: @log_limit))

  defp reload(%{assigns: %{live_action: :edit, route: %Route{} = route}} = socket) do
    case Routing.get_route(route.id) do
      {:ok, route} -> assign(socket, :route, route)
      _ -> socket
    end
  end

  defp reload(socket), do: socket

  defp error(socket, message \\ nil) do
    Toast.send_to(
      socket.assigns.current_user,
      message || gettext("That did not work. Reload the page and try again."),
      %{level: :error, type: :notification}
    )

    socket
  end

  # Unchecking every box sends only the hidden "". An empty URL field on a
  # saved route keeps the saved URL.
  defp normalize(params) do
    params =
      Enum.reduce(~w(events entry_types recipient_ids), params, fn key, params ->
        Map.update(params, key, [], fn values -> values |> List.wrap() |> Enum.reject(&(&1 == "")) end)
      end)

    if params["url"] in [nil, ""], do: Map.delete(params, "url"), else: params
  end

  ## Options

  defp event_options, do: Enum.map(Route.events(), &{event_label(&1), &1})

  defp kind_options, do: Enum.map(Route.kinds(), &{kind_label(&1), &1})

  # Every content type's name, for labels
  defp type_labels do
    Webhooks.entry_schemas()
    |> Enum.map(&{Brando.Blueprint.get_plural(&1), Event.entry_type(&1)})
    |> Enum.reject(fn {_label, value} -> is_nil(value) end)
    |> Enum.sort_by(fn {label, _} -> String.downcase(to_string(label)) end)
  end

  # The filter offers the content types the user may read. A type already
  # chosen that they may not read is kept by a hidden input.
  defp entry_type_options do
    readable =
      Webhooks.entry_schemas()
      |> Enum.filter(&BrandoAdmin.Authorization.allowed?(:read, &1))
      |> MapSet.new(&Event.entry_type/1)

    Enum.filter(type_labels(), fn {_label, value} -> value in readable end)
  end

  @doc false
  def event_label("mention"), do: gettext("Mentions")
  def event_label("scheduled_publish"), do: gettext("Published on schedule")
  def event_label("scheduled_unpublish"), do: gettext("Unpublished on schedule")
  def event_label("failed_job"), do: gettext("Failed jobs")
  def event_label("test"), do: gettext("Test notification")
  def event_label(other), do: other

  defp event_hint("mention"), do: gettext("Someone is mentioned in a note.")
  defp event_hint("scheduled_publish"), do: gettext("An entry is published at its scheduled time.")
  defp event_hint("scheduled_unpublish"), do: gettext("An entry is unpublished at its scheduled time.")

  defp event_hint("failed_job"),
    do: gettext("A background job is given up, or a webhook is paused after its deliveries kept failing.")

  @doc false
  def kind_label(:slack), do: "Slack"
  def kind_label(:teams), do: "Microsoft Teams"
  def kind_label(:email), do: gettext("Email")
  def kind_label(other), do: to_string(other)

  defp kind_icon(:email), do: "mail"
  defp kind_icon(_), do: "message-square"

  defp url_hint(:teams),
    do:
      gettext(
        "The URL of a Teams workflow that posts to a channel when a webhook request is received. It is stored encrypted and not shown again."
      )

  defp url_hint(_),
    do:
      gettext(
        "A Slack incoming webhook URL, starting with https://hooks.slack.com/services/. It is stored encrypted and not shown again."
      )

  ## Render

  def render(%{live_action: :index} = assigns) do
    ~H"""
    <div class="admin-workspace integrations-workspace">
      <.back_link to="/admin/config/integrations" label={gettext("Integrations")} />
      <Workspace.header
        title={gettext("Notifications")}
        subtitle={gettext("Messages to Slack, Microsoft Teams or email when something happens in this environment.")}
      >
        <.link :if={@routes != []} navigate="/admin/config/notifications/deliveries" class="workspace-button">
          {gettext("Delivery log")}
        </.link>
        <.link
          navigate="/admin/config/notifications/new"
          class="workspace-button primary"
          data-testid="notification-route-new"
        >
          <.icon name="plus" />{gettext("Add route")}
        </.link>
      </Workspace.header>

      <div :if={@routes == []} class="integrations-list">
        <Workspace.empty
          title={gettext("No notification routes")}
          description={
            gettext(
              "A route sends mentions, scheduled publishing and failed jobs to a Slack or Teams channel, or by email to the people you choose."
            )
          }
        />
      </div>

      <div :if={@routes != []} class="integrations-list" data-testid="notification-route-list">
        <article :for={route <- @routes} class="integrations-row" id={"notification-route-#{route.id}"}>
          <span class="integrations-icon" aria-hidden="true"><.icon name={kind_icon(route.kind)} /></span>
          <div class="integrations-text">
            <h3>{route.name} <.state route={route} /></h3>
            <p>
              {destination(route, @recipient_options)} · {events_summary(route)}{filters_summary(route, @type_labels)}
            </p>
            <p :if={route.last_delivery_at} class="integrations-meta">{last_delivery(route)}</p>
          </div>
          <div class="integrations-actions">
            <.link navigate={"/admin/config/notifications/#{route.id}/deliveries"} class="workspace-button">
              {gettext("Delivery log")}
            </.link>
            <.link navigate={"/admin/config/notifications/#{route.id}/edit"} class="workspace-button">
              {gettext("Edit")}
            </.link>
          </div>
        </article>
      </div>
    </div>
    """
  end

  def render(%{live_action: action} = assigns) when action in [:new, :edit] do
    assigns = assign(assigns, :kind, Phoenix.HTML.Form.input_value(assigns.form, :kind) |> to_kind())

    ~H"""
    <div class="admin-workspace integrations-workspace">
      <.back_link to="/admin/config/notifications" label={gettext("Notifications")} />
      <Workspace.header
        title={if @route, do: @route.name, else: gettext("New notification route")}
        subtitle={
          if @route,
            do: kind_label(@route.kind),
            else: gettext("Where to send notifications, and which ones.")
        }
      >
        <span :if={@route}><.state route={@route} /></span>
        <.link
          :if={@route}
          navigate={"/admin/config/notifications/#{@route.id}/deliveries"}
          class="workspace-button"
        >
          {gettext("Delivery log")}
        </.link>
      </Workspace.header>

      <.form
        for={@form}
        id="notification-route-form"
        class="workspace-panel webhook-form"
        phx-change="validate"
        phx-submit="save"
        data-testid="notification-route-form"
      >
        <div class="webhook-fields">
          <div class="webhook-field">
            <label for="route-name">{gettext("Name")}</label>
            <input
              id="route-name"
              type="text"
              name={@form[:name].name}
              value={@form[:name].value}
              placeholder={gettext("Editors' channel")}
              required
              maxlength="120"
              phx-debounce="300"
            />
            <.field_errors field={@form[:name]} show={@submitted? or used_input?(@form[:name])} />
          </div>

          <fieldset class="webhook-field">
            <legend>{gettext("Send to")}</legend>
            <div class="webhook-modes">
              <label :for={{label, value} <- @kind_options} class="webhook-choice">
                <input
                  type="radio"
                  name={@form[:kind].name}
                  value={value}
                  checked={@kind == value}
                  data-testid={"notification-kind-#{value}"}
                />
                <span>{label}</span>
              </label>
            </div>
          </fieldset>

          <div :if={@kind != :email and url_saved?(@route, @kind) and !@replace_url?} class="webhook-field">
            <span class="webhook-label">{gettext("Webhook URL")}</span>
            <div class="webhook-url-masked">
              <code class="workspace-mono" data-testid="notification-url-masked">{@route.url_hint}</code>
              <button
                type="button"
                class="workspace-button"
                phx-click="replace_url"
                data-testid="notification-replace-url"
              >
                {gettext("Replace URL")}
              </button>
            </div>
            <p class="webhook-hint">{gettext("The URL is a secret: only its host and last characters are shown.")}</p>
          </div>
          <div :if={@kind != :email and (!url_saved?(@route, @kind) or @replace_url?)} class="webhook-field">
            <label for="route-url">{gettext("Webhook URL")}</label>
            <input
              id="route-url"
              type="url"
              name={@form[:url].name}
              value={@form[:url].value}
              placeholder={if @kind == :teams, do: "https://…/workflows/…", else: "https://hooks.slack.com/services/…"}
              required
              autocomplete="off"
              spellcheck="false"
              phx-debounce="500"
            />
            <p class="webhook-hint">{url_hint(@kind)}</p>
            <.field_errors field={@form[:url]} show={@submitted? or used_input?(@form[:url])} />
          </div>

          <fieldset :if={@kind == :email} class="webhook-field" data-testid="notification-recipients">
            <legend>{gettext("Recipients")}</legend>
            <p class="webhook-hint">
              {gettext(
                "Each gets an email in their own language, or their daily or weekly summary if they chose one in their profile. Notifications about an entry go only to those who may read it."
              )}
            </p>
            <div class="webhook-checks webhook-checks-described">
              <input type="hidden" name="route[recipient_ids][]" value="" />
              <label :for={user <- @recipient_options} class="webhook-choice">
                <input
                  type="checkbox"
                  name="route[recipient_ids][]"
                  value={user.id}
                  checked={user.id in ids(@form[:recipient_ids].value)}
                />
                <span>{user.name} <small class="webhook-muted">{user.email}</small></span>
              </label>
            </div>
            <.field_errors field={@form[:recipient_ids]} show={@submitted?} />
          </fieldset>

          <fieldset class="webhook-field" data-testid="notification-events">
            <legend>{gettext("Events")}</legend>
            <div class="webhook-checks webhook-checks-described">
              <input type="hidden" name="route[events][]" value="" />
              <label :for={{label, value} <- @event_options} class="webhook-choice">
                <input
                  type="checkbox"
                  name="route[events][]"
                  value={value}
                  checked={value in (@form[:events].value || [])}
                />
                <span>{label} <small class="webhook-muted">{event_hint(value)}</small></span>
              </label>
            </div>
            <.field_errors field={@form[:events]} show={@submitted?} />
          </fieldset>

          <%!-- Chosen types this user may not read are kept as they are --%>
          <input type="hidden" name="route[entry_types][]" value="" />
          <input
            :for={value <- hidden_types(@form[:entry_types].value, @entry_type_options)}
            type="hidden"
            name="route[entry_types][]"
            value={value}
          />
          <fieldset :if={@entry_type_options != []} class="webhook-field">
            <legend>{gettext("Content types")}</legend>
            <p class="webhook-hint">
              {gettext("None chosen sends events for every content type. Failed jobs are always sent.")}
            </p>
            <div class="webhook-checks">
              <label :for={{label, value} <- @entry_type_options} class="webhook-choice">
                <input
                  type="checkbox"
                  name="route[entry_types][]"
                  value={value}
                  checked={value in (@form[:entry_types].value || [])}
                />
                <span>{label}</span>
              </label>
            </div>
          </fieldset>
        </div>

        <div class="webhook-form-footer">
          <button type="submit" class="workspace-button primary" data-testid="notification-route-save">
            {if @route, do: gettext("Save route"), else: gettext("Create route")}
          </button>
        </div>
      </.form>

      <section
        :if={@route}
        class="integrations-list webhook-settings"
        aria-label={gettext("Notification route settings")}
      >
        <article class="integrations-row plain">
          <div class="integrations-text">
            <h3>{gettext("Test notification")}</h3>
            <p>{gettext("Sends a short test message, so you can see where and how notifications arrive.")}</p>
          </div>
          <div class="integrations-actions">
            <button
              type="button"
              class="workspace-button"
              phx-click="send_test"
              disabled={!@route.active}
              data-testid="notification-send-test"
            >
              <.icon name="send" />{gettext("Send test")}
            </button>
          </div>
        </article>
        <article class="integrations-row plain">
          <div class="integrations-text">
            <h3>{if @route.active, do: gettext("Sending"), else: gettext("Paused")}</h3>
            <p>{pause_text(@route)}</p>
          </div>
          <div class="integrations-actions">
            <button
              :if={@route.active}
              type="button"
              class="workspace-button"
              phx-click="pause"
              data-testid="notification-pause"
            >
              <.icon name="pause" />{gettext("Pause")}
            </button>
            <button
              :if={!@route.active}
              type="button"
              class="workspace-button"
              phx-click="resume"
              data-testid="notification-resume"
            >
              <.icon name="play" />{gettext("Resume")}
            </button>
          </div>
        </article>
        <article class="integrations-row plain">
          <div class="integrations-text">
            <h3>{gettext("Delete route")}</h3>
            <p>{gettext("Stops all notifications on it and removes its delivery log.")}</p>
          </div>
          <div class="integrations-actions">
            <button
              type="button"
              class="workspace-button destructive"
              phx-click="delete"
              data-confirm-title={gettext("Delete this notification route?")}
              data-confirm={gettext("Nothing more is sent on it, and its delivery log is removed.")}
              data-confirm-ok={gettext("Delete route")}
              data-confirm-destructive
              data-testid="notification-delete"
            >
              {gettext("Delete")}
            </button>
          </div>
        </article>
      </section>
    </div>
    """
  end

  def render(%{live_action: :deliveries} = assigns) do
    ~H"""
    <div class="admin-workspace integrations-workspace">
      <.back_link to="/admin/config/notifications" label={gettext("Notifications")} />
      <Workspace.header
        title={gettext("Delivery log")}
        subtitle={
          if @route,
            do: "#{@route.name} · #{kind_label(@route.kind)}",
            else: gettext("What was sent on every notification route in this environment, newest first.")
        }
      >
        <span :if={@route}><.state route={@route} /></span>
        <button
          :if={@route}
          type="button"
          class="workspace-button"
          phx-click="send_test"
          disabled={!@route.active}
          data-testid="notification-send-test"
        >
          <.icon name="send" />{gettext("Send test")}
        </button>
        <.link :if={@route} navigate={"/admin/config/notifications/#{@route.id}/edit"} class="workspace-button">
          {gettext("Edit")}
        </.link>
      </Workspace.header>

      <p :if={@route && !@route.active} class="webhook-paused-note" role="status">{pause_text(@route)}</p>

      <section class="workspace-panel">
        <div :if={@deliveries == []}>
          <Workspace.empty
            title={gettext("Nothing sent yet")}
            description={gettext("Notifications show here when they are sent, or when you send a test.")}
          />
        </div>
        <div :if={@deliveries != []} class="workspace-table-scroll">
          <table class="workspace-table webhook-log" data-testid="notification-log">
            <thead>
              <tr>
                <th scope="col">{gettext("Time")}</th>
                <th :if={!@route} scope="col">{gettext("Route")}</th>
                <th scope="col">{gettext("Event")}</th>
                <th scope="col">{gettext("Message")}</th>
                <th scope="col">{gettext("Result")}</th>
                <th scope="col">{gettext("Duration")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={delivery <- @deliveries} id={"notification-delivery-#{delivery.id}"} data-state={delivery.state}>
                <td><BrandoAdmin.Dates.time at={delivery.inserted_at} format={:short} /></td>
                <td :if={!@route}>{delivery.route && delivery.route.name}</td>
                <td>{event_label(delivery.event)}</td>
                <td>
                  <.message delivery={delivery} />
                </td>
                <td>
                  <.delivery_state delivery={delivery} />
                  <small :if={delivery.error} class="webhook-error">{error_text(delivery.error)}</small>
                </td>
                <td class="webhook-duration">{duration(delivery.duration_ms)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
    """
  end

  ## Components

  attr :to, :string, required: true
  attr :label, :string, required: true

  defp back_link(assigns) do
    ~H"""
    <.link navigate={@to} class="integrations-back"><.icon name="arrow-left" />{@label}</.link>
    """
  end

  attr :route, Route, required: true

  defp state(assigns) do
    ~H"""
    <span :if={@route.active} class="workspace-badge positive" data-testid="notification-route-state">
      {gettext("Active")}
    </span>
    <span
      :if={!@route.active}
      class={["workspace-badge", if(@route.paused_reason == :failures, do: "negative", else: "warning")]}
      data-testid="notification-route-state"
    >
      {paused_label(@route.paused_reason)}
    </span>
    """
  end

  defp paused_label(:failures), do: gettext("Paused after failures")
  defp paused_label(:environment_copy), do: gettext("Paused: copied environment")
  defp paused_label(_), do: gettext("Paused")

  defp pause_text(%Route{active: true}),
    do: gettext("Notifications are sent as things happen. Pausing stops them until you resume.")

  defp pause_text(%Route{paused_reason: :failures}),
    do: gettext("Paused because its messages kept failing. Check the webhook URL, then resume.")

  defp pause_text(%Route{paused_reason: :environment_copy}),
    do:
      gettext(
        "Paused because this environment was copied or restored from another one. It resumes when this environment goes live; resume it sooner only if this environment should send here."
      )

  defp pause_text(_route), do: gettext("Nothing is sent while it is paused. What happens meanwhile is not sent later.")

  attr :delivery, :map, required: true

  defp message(assigns) do
    content = Message.content(assigns.delivery.notification, Gettext.get_locale(Brando.Gettext))
    assigns = assign(assigns, title: content.title, recipient: assigns.delivery.recipient)

    ~H"""
    <span>{@title}</span>
    <small :if={@recipient}>{gettext("To %{name}", name: @recipient.name)}</small>
    """
  end

  attr :delivery, :map, required: true

  defp delivery_state(assigns) do
    ~H"""
    <span class={["workspace-badge", state_tone(@delivery.state)]} data-testid="notification-delivery-state">
      {if @delivery.response_status, do: @delivery.response_status, else: state_label(@delivery.state)}
      <span :if={@delivery.response_status}>· {state_label(@delivery.state)}</span>
    </span>
    """
  end

  defp state_tone("succeeded"), do: "positive"
  defp state_tone("retrying"), do: "warning"
  defp state_tone("failed"), do: "negative"
  defp state_tone(_), do: nil

  defp state_label("pending"), do: gettext("Queued")
  defp state_label("sending"), do: gettext("Sending")
  defp state_label("succeeded"), do: gettext("Delivered")
  defp state_label("retrying"), do: gettext("Retrying")
  defp state_label("failed"), do: gettext("Failed")
  defp state_label("cancelled"), do: gettext("Not sent")
  defp state_label("digest"), do: gettext("In summary")
  defp state_label(state), do: state

  defp error_text("timeout"), do: gettext("No answer within 10 seconds")
  defp error_text("connection_failed"), do: gettext("Could not connect")
  defp error_text("unresolvable"), do: gettext("The host name could not be found")
  defp error_text("private_address"), do: gettext("The address is on a private network")
  defp error_text("https_required"), do: gettext("The URL is not https")
  defp error_text("url_unreadable"), do: gettext("The URL could not be read; replace it")
  defp error_text("route_paused"), do: gettext("The route was paused")
  defp error_text("recipient_unavailable"), do: gettext("The recipient is inactive or may not read the entry")
  defp error_text("no_mailer"), do: gettext("This site cannot send email")
  defp error_text("no_sender"), do: gettext("This site cannot send email")
  defp error_text("invalid_response"), do: gettext("Not a valid HTTP response")
  defp error_text("result_not_recorded"), do: gettext("Sent, but the answer could not be saved")
  defp error_text(other), do: other

  defp duration(nil), do: ""
  defp duration(ms) when ms < 1000, do: "#{ms} ms"
  defp duration(ms), do: "#{Float.round(ms / 1000, 1)} s"

  attr :field, Phoenix.HTML.FormField, required: true
  attr :show, :boolean, default: true

  defp field_errors(assigns) do
    ~H"""
    <p :for={{_message, opts} <- @field.errors} :if={@show and @field.errors != []} class="webhook-error" role="alert">
      {field_error(opts)}
    </p>
    """
  end

  defp field_error(opts) do
    case Keyword.get(opts, :reason) || Keyword.get(opts, :validation) do
      reason when reason in [:https_required, :scheme_not_allowed] -> gettext("Use an https:// address.")
      :credentials_in_url -> gettext("Leave the user name and password out of the address.")
      :unresolvable -> gettext("This host name could not be found.")
      :private_address -> gettext("This address is on a private or local network, which webhooks may not call.")
      :invalid_url -> gettext("This is not a valid address.")
      :required -> gettext("Fill this in.")
      :length -> length_error(opts)
      _ -> gettext("Check this value.")
    end
  end

  defp length_error(opts) do
    if Keyword.get(opts, :kind) == :min, do: gettext("Choose at least one."), else: gettext("This is too long.")
  end

  ## Helpers

  defp to_kind(kind) when is_atom(kind), do: kind
  defp to_kind("email"), do: :email
  defp to_kind("teams"), do: :teams
  defp to_kind(_), do: :slack

  # A saved route has a URL for its own kind only
  defp url_saved?(%Route{kind: kind, url_hint: hint}, kind) when is_binary(hint), do: true
  defp url_saved?(_route, _kind), do: false

  defp ids(values), do: values |> List.wrap() |> Enum.flat_map(&id/1)

  defp id(value) when is_integer(value), do: [value]

  defp id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> [id]
      _ -> []
    end
  end

  defp id(_), do: []

  defp hidden_types(chosen, options) do
    offered = Enum.map(options, &elem(&1, 1))
    Enum.reject(List.wrap(chosen), &(&1 in offered or &1 == ""))
  end

  defp destination(%Route{kind: :email, recipient_ids: ids}, users) do
    names = users |> Enum.filter(&(&1.id in ids)) |> Enum.map(& &1.name)

    case names do
      [] -> gettext("Email")
      names when length(names) <= 3 -> gettext("Email to %{names}", names: Enum.join(names, ", "))
      names -> ngettext("Email to %{count} person", "Email to %{count} people", length(names))
    end
  end

  defp destination(%Route{} = route, _users), do: kind_label(route.kind)

  defp events_summary(%Route{events: events}), do: Enum.map_join(events, ", ", &event_label/1)

  defp filters_summary(%Route{entry_types: []}, _types), do: nil

  defp filters_summary(%Route{entry_types: types}, labels) do
    " · " <>
      Enum.map_join(types, ", ", fn type ->
        case List.keyfind(labels, type, 1) do
          {label, _} -> label
          nil -> type
        end
      end)
  end

  defp last_delivery(%Route{last_delivery_state: "succeeded"} = route),
    do: gettext("Last delivered %{time}", time: BrandoAdmin.Dates.clock(route.last_delivery_at))

  defp last_delivery(%Route{} = route),
    do: gettext("Last delivery failed %{time}", time: BrandoAdmin.Dates.clock(route.last_delivery_at))
end
