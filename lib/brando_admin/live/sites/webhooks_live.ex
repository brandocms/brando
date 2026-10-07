defmodule BrandoAdmin.Sites.WebhooksLive do
  @moduledoc """
  Configuration → Integrations → Webhooks (`Brando.Webhooks`): the list,
  the form, and the delivery log, for the current site environment.

  Everything that changes a webhook or sends to it — saving, deleting,
  pausing, rotating the secret, redelivering, a test event — asks for the
  password again when the session has not confirmed lately
  (`BrandoAdmin.Reauth`). A new secret reaches the browser as a push event
  for the `Brando.WebhookSecret` hook, never through the LiveView's assigns.
  """
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias Brando.ContentEvents.Event
  alias Brando.Webhooks
  alias Brando.Webhooks.Webhook
  alias BrandoAdmin.Components.Workspace
  alias BrandoAdmin.Toast

  on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, __MODULE__}})
  on_mount({BrandoAdmin.Reauth, events: ~w(save delete rotate_secret pause resume redeliver send_test)})

  @log_limit 100

  def __authorization__, do: {:manage, :webhooks}

  def mount(_params, _session, socket) do
    if Webhooks.can_manage?(socket.assigns.current_user) do
      if connected?(socket), do: Phoenix.PubSub.subscribe(Brando.pubsub(), Webhooks.topic())

      {:ok,
       socket
       |> assign(:socket_connected, connected?(socket))
       |> assign(:event_options, event_options())
       |> assign(:entry_type_options, entry_type_options())
       |> assign(:language_options, Enum.map(Webhooks.language_values(), &{String.upcase(&1), &1}))
       |> assign(:webhook, nil)
       |> assign(:deliveries, [])
       |> assign(:entry_titles, %{})}
    else
      {:ok, redirect(socket, to: "/admin/access-denied")}
    end
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, gettext("Webhooks"))
    |> assign(:webhook, nil)
    |> assign(:webhooks, Webhooks.list_webhooks())
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, gettext("New webhook"))
    |> assign(:webhook, nil)
    |> assign_form(Webhooks.change_webhook(%Webhook{}, %{}, resolve: false), "all")
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    with_webhook(socket, id, fn socket, webhook ->
      socket
      |> assign(:page_title, gettext("Edit webhook"))
      |> assign(:webhook, webhook)
      |> assign_form(Webhooks.change_webhook(webhook, %{}, resolve: false), events_mode(webhook.events))
    end)
  end

  defp apply_action(socket, :deliveries, %{"id" => id}) do
    with_webhook(socket, id, fn socket, webhook ->
      socket
      |> assign(:page_title, gettext("Delivery log"))
      |> assign(:webhook, webhook)
      |> assign_deliveries(Webhooks.list_deliveries(webhook, limit: @log_limit))
    end)
  end

  defp apply_action(socket, :deliveries, _params) do
    socket
    |> assign(:page_title, gettext("Delivery log"))
    |> assign(:webhook, nil)
    |> assign(:webhooks, Webhooks.list_webhooks())
    |> assign_deliveries(Webhooks.list_all_deliveries(limit: @log_limit))
  end

  defp assign_deliveries(socket, deliveries) do
    socket
    |> assign(:deliveries, deliveries)
    |> assign(:entry_titles, Webhooks.entry_titles(deliveries))
  end

  # Ids come from the URL: only a webhook of this environment is found.
  defp with_webhook(socket, id, fun) do
    case Webhooks.get_webhook(id) do
      {:ok, webhook} ->
        fun.(socket, webhook)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, gettext("That webhook does not exist in this environment."))
        |> push_navigate(to: "/admin/config/webhooks")
    end
  end

  defp assign_form(socket, changeset, mode) do
    socket
    |> assign(:form, to_form(changeset, as: :webhook))
    |> assign(:events_mode, mode)
  end

  defp events_mode([]), do: "all"
  defp events_mode(_events), do: "chosen"

  ## Events

  def handle_event("validate", %{"webhook" => params}, socket) do
    params = normalize(params)
    changeset = Webhooks.change_webhook(socket.assigns.webhook || %Webhook{}, params, resolve: false)
    {:noreply, assign_form(socket, %{changeset | action: :validate}, params["events_mode"])}
  end

  def handle_event("save", %{"webhook" => params}, socket) do
    params = normalize(params)
    user = socket.assigns.current_user

    case socket.assigns.webhook do
      nil ->
        case Webhooks.create_webhook(params, user) do
          {:ok, webhook, secret} ->
            {:noreply,
             socket
             |> push_patch(to: "/admin/config/webhooks/#{webhook.id}/edit")
             |> push_event("brando:webhook-secret", %{secret: secret})}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset, params["events_mode"])}

          {:error, _} ->
            {:noreply, error(socket)}
        end

      %Webhook{} = webhook ->
        case Webhooks.update_webhook(webhook, params, user) do
          {:ok, webhook} ->
            Toast.send_to(user, gettext("The webhook was saved."))

            {:noreply,
             socket
             |> assign(:webhook, webhook)
             |> assign_form(Webhooks.change_webhook(webhook, %{}, resolve: false), events_mode(webhook.events))}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset, params["events_mode"])}

          {:error, _} ->
            {:noreply, error(socket)}
        end
    end
  end

  def handle_event("rotate_secret", _params, %{assigns: %{webhook: %Webhook{} = webhook}} = socket) do
    case Webhooks.rotate_secret(webhook, socket.assigns.current_user) do
      {:ok, webhook, secret} ->
        {:noreply,
         socket
         |> assign(:webhook, webhook)
         |> push_event("brando:webhook-secret", %{secret: secret})}

      _ ->
        {:noreply, error(socket)}
    end
  end

  def handle_event("pause", _params, %{assigns: %{webhook: %Webhook{} = webhook}} = socket) do
    {:noreply, after_change(socket, Webhooks.pause(webhook, :manual, socket.assigns.current_user))}
  end

  def handle_event("resume", _params, %{assigns: %{webhook: %Webhook{} = webhook}} = socket) do
    {:noreply, after_change(socket, Webhooks.resume(webhook, socket.assigns.current_user))}
  end

  def handle_event("delete", _params, %{assigns: %{webhook: %Webhook{} = webhook}} = socket) do
    case Webhooks.delete_webhook(webhook, socket.assigns.current_user) do
      {:ok, _} ->
        Toast.send_to(socket.assigns.current_user, gettext("The webhook was deleted."))
        {:noreply, push_navigate(socket, to: "/admin/config/webhooks")}

      _ ->
        {:noreply, error(socket)}
    end
  end

  def handle_event("send_test", _params, %{assigns: %{webhook: %Webhook{} = webhook}} = socket) do
    case Webhooks.send_test(webhook, socket.assigns.current_user) do
      {:ok, _delivery} ->
        Toast.send_to(socket.assigns.current_user, gettext("A test event was sent."))
        {:noreply, reload(socket)}

      {:error, :paused} ->
        {:noreply, error(socket, gettext("Resume the webhook to send to it."))}

      _ ->
        {:noreply, error(socket)}
    end
  end

  def handle_event("redeliver", %{"id" => id}, socket) do
    with {:ok, delivery} <- Webhooks.get_delivery(id),
         {:ok, _delivery} <- Webhooks.redeliver(delivery, socket.assigns.current_user) do
      Toast.send_to(socket.assigns.current_user, gettext("The delivery was sent again."))
      {:noreply, reload(socket)}
    else
      {:error, :paused} -> {:noreply, error(socket, gettext("Resume the webhook to send to it."))}
      _ -> {:noreply, error(socket)}
    end
  end

  def handle_info({Webhooks, _message}, socket), do: {:noreply, reload(socket)}

  defp after_change(socket, {:ok, webhook}), do: assign(socket, :webhook, webhook)
  defp after_change(socket, _error), do: error(socket)

  defp reload(%{assigns: %{live_action: :index}} = socket),
    do: assign(socket, :webhooks, Webhooks.list_webhooks())

  defp reload(%{assigns: %{live_action: :deliveries, webhook: %Webhook{} = webhook}} = socket) do
    case Webhooks.get_webhook(webhook.id) do
      {:ok, webhook} ->
        socket
        |> assign(:webhook, webhook)
        |> assign_deliveries(Webhooks.list_deliveries(webhook, limit: @log_limit))

      _ ->
        socket
    end
  end

  defp reload(%{assigns: %{live_action: :deliveries}} = socket),
    do: assign_deliveries(socket, Webhooks.list_all_deliveries(limit: @log_limit))

  defp reload(%{assigns: %{live_action: :edit, webhook: %Webhook{} = webhook}} = socket) do
    case Webhooks.get_webhook(webhook.id) do
      {:ok, webhook} -> assign(socket, :webhook, webhook)
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

  # Unchecking every box sends only the hidden "" — no events chosen means
  # all, which is what "All events" says.
  defp normalize(params) do
    params =
      Enum.reduce(~w(events entry_types languages), params, fn key, params ->
        Map.update(params, key, [], fn values -> values |> List.wrap() |> Enum.reject(&(&1 == "")) end)
      end)

    if params["events_mode"] == "chosen", do: params, else: Map.put(params, "events", [])
  end

  ## Options

  defp event_options do
    Enum.map(Brando.ContentEvents.types(), &{event_label(&1), &1})
  end

  defp entry_type_options do
    Webhooks.entry_schemas()
    |> Enum.map(&{Brando.Blueprint.get_plural(&1), Event.entry_type(&1)})
    |> Enum.reject(fn {_label, value} -> is_nil(value) end)
    |> Enum.sort_by(fn {label, _} -> String.downcase(to_string(label)) end)
  end

  @doc false
  def event_label("entry.created"), do: gettext("Created")
  def event_label("entry.updated"), do: gettext("Updated")
  def event_label("entry.published"), do: gettext("Published")
  def event_label("entry.unpublished"), do: gettext("Unpublished")
  def event_label("entry.deleted"), do: gettext("Deleted")
  def event_label("entry.restored"), do: gettext("Restored")
  def event_label("webhook.test"), do: gettext("Test event")
  def event_label(other), do: other

  ## Render

  def render(%{live_action: :index} = assigns) do
    ~H"""
    <div class="admin-workspace integrations-workspace">
      <.back_link to="/admin/config/integrations" label={gettext("Integrations")} />
      <Workspace.header
        title={gettext("Webhooks")}
        subtitle={gettext("Signed requests to other systems when content changes in this environment.")}
      >
        <.link :if={@webhooks != []} navigate="/admin/config/webhooks/deliveries" class="workspace-button">
          {gettext("Delivery log")}
        </.link>
        <.link navigate="/admin/config/webhooks/new" class="workspace-button primary" data-testid="webhook-new">
          <.icon name="plus" />{gettext("Add webhook")}
        </.link>
      </Workspace.header>

      <div :if={@webhooks == []} class="integrations-list">
        <Workspace.empty
          title={gettext("No webhooks")}
          description={
            gettext(
              "A webhook tells another system — a static site build, a cache, a search index — when content is published or changes."
            )
          }
        />
      </div>

      <div :if={@webhooks != []} class="integrations-list" data-testid="webhook-list">
        <article :for={webhook <- @webhooks} class="integrations-row" id={"webhook-#{webhook.id}"}>
          <span class="integrations-icon" aria-hidden="true"><.icon name="webhook" /></span>
          <div class="integrations-text">
            <h3>{webhook.name} <.state webhook={webhook} /></h3>
            <p>
              <span class="workspace-mono">{Webhooks.host(webhook)}</span>
              · {events_summary(webhook)}{filters_summary(webhook, @entry_type_options)}
            </p>
            <p :if={webhook.last_delivery_at} class="integrations-meta">
              {last_delivery(webhook)}
            </p>
          </div>
          <div class="integrations-actions">
            <.link navigate={"/admin/config/webhooks/#{webhook.id}/deliveries"} class="workspace-button">
              {gettext("Delivery log")}
            </.link>
            <.link navigate={"/admin/config/webhooks/#{webhook.id}/edit"} class="workspace-button">
              {gettext("Edit")}
            </.link>
          </div>
        </article>
      </div>
    </div>
    """
  end

  def render(%{live_action: action} = assigns) when action in [:new, :edit] do
    ~H"""
    <div class="admin-workspace integrations-workspace">
      <.back_link to="/admin/config/webhooks" label={gettext("Webhooks")} />
      <Workspace.header
        title={if @webhook, do: @webhook.name, else: gettext("New webhook")}
        subtitle={
          if @webhook,
            do: Webhooks.host(@webhook),
            else: gettext("Where to send events, and which ones. The secret to verify them is shown once, after saving.")
        }
      >
        <span :if={@webhook}><.state webhook={@webhook} /></span>
        <.link :if={@webhook} navigate={"/admin/config/webhooks/#{@webhook.id}/deliveries"} class="workspace-button">
          {gettext("Delivery log")}
        </.link>
      </Workspace.header>

      <.secret_panel />

      <.form
        for={@form}
        id="webhook-form"
        class="workspace-panel webhook-form"
        phx-change="validate"
        phx-submit="save"
        data-testid="webhook-form"
      >
        <div class="webhook-fields">
          <div class="webhook-field">
            <label for="webhook-name">{gettext("Name")}</label>
            <input
              id="webhook-name"
              type="text"
              name={@form[:name].name}
              value={@form[:name].value}
              placeholder={gettext("Shop cache")}
              required
              maxlength="120"
              phx-debounce="300"
            />
            <.field_errors field={@form[:name]} />
          </div>
          <div class="webhook-field">
            <label for="webhook-url">{gettext("URL")}</label>
            <input
              id="webhook-url"
              type="url"
              name={@form[:url].name}
              value={@form[:url].value}
              placeholder="https://example.com/brando-webhook"
              required
              autocomplete="off"
              spellcheck="false"
              phx-debounce="500"
            />
            <p class="webhook-hint">
              {gettext("An https address on the public internet. Redirects are not followed.")}
            </p>
            <.field_errors field={@form[:url]} />
          </div>

          <fieldset class="webhook-field">
            <legend>{gettext("Events")}</legend>
            <div class="webhook-modes">
              <label class="webhook-choice">
                <input type="radio" name="webhook[events_mode]" value="all" checked={@events_mode != "chosen"} />
                <span>{gettext("All events")}</span>
              </label>
              <label class="webhook-choice">
                <input
                  type="radio"
                  name="webhook[events_mode]"
                  value="chosen"
                  checked={@events_mode == "chosen"}
                  data-testid="webhook-events-chosen"
                />
                <span>{gettext("Only these")}</span>
              </label>
            </div>
            <div :if={@events_mode == "chosen"} class="webhook-checks">
              <input type="hidden" name="webhook[events][]" value="" />
              <label :for={{label, value} <- @event_options} class="webhook-choice">
                <input
                  type="checkbox"
                  name="webhook[events][]"
                  value={value}
                  checked={value in (@form[:events].value || [])}
                />
                <span>{label} <code class="workspace-mono">{value}</code></span>
              </label>
            </div>
            <.field_errors field={@form[:events]} />
          </fieldset>

          <fieldset :if={@entry_type_options != []} class="webhook-field">
            <legend>{gettext("Content types")}</legend>
            <p class="webhook-hint">{gettext("None chosen sends events for every content type.")}</p>
            <div class="webhook-checks">
              <input type="hidden" name="webhook[entry_types][]" value="" />
              <label :for={{label, value} <- @entry_type_options} class="webhook-choice">
                <input
                  type="checkbox"
                  name="webhook[entry_types][]"
                  value={value}
                  checked={value in (@form[:entry_types].value || [])}
                />
                <span>{label}</span>
              </label>
            </div>
          </fieldset>

          <fieldset :if={length(@language_options) > 1} class="webhook-field">
            <legend>{gettext("Languages")}</legend>
            <p class="webhook-hint">{gettext("None chosen sends events in every language.")}</p>
            <div class="webhook-checks webhook-checks-inline">
              <input type="hidden" name="webhook[languages][]" value="" />
              <label :for={{label, value} <- @language_options} class="webhook-choice">
                <input
                  type="checkbox"
                  name="webhook[languages][]"
                  value={value}
                  checked={value in (@form[:languages].value || [])}
                />
                <span>{label}</span>
              </label>
            </div>
          </fieldset>
        </div>

        <div class="webhook-form-footer">
          <button type="submit" class="workspace-button primary" data-testid="webhook-save">
            {if @webhook, do: gettext("Save webhook"), else: gettext("Create webhook")}
          </button>
        </div>
      </.form>

      <section :if={@webhook} class="integrations-list webhook-settings" aria-label={gettext("Webhook settings")}>
        <article class="integrations-row plain">
          <div class="integrations-text">
            <h3>{gettext("Signing secret")}</h3>
            <p>
              {gettext("Ends in %{hint}.", hint: @webhook.secret_hint)}
              <span :if={@webhook.secret_rotated_at}>
                {gettext("Rotated %{date}.", date: BrandoAdmin.Dates.long(@webhook.secret_rotated_at))}
              </span>
              {gettext("A new secret replaces this one at once; update the receiver straight after.")}
            </p>
          </div>
          <div class="integrations-actions">
            <button
              type="button"
              class="workspace-button"
              phx-click="rotate_secret"
              data-confirm-title={gettext("Rotate the secret?")}
              data-confirm={
                gettext(
                  "The current secret stops working at once. Deliveries fail to verify until the receiver has the new one."
                )
              }
              data-confirm-ok={gettext("Rotate secret")}
              data-testid="webhook-rotate"
            >
              <.icon name="key-round" />{gettext("Rotate secret")}
            </button>
          </div>
        </article>
        <article class="integrations-row plain">
          <div class="integrations-text">
            <h3>{if @webhook.active, do: gettext("Sending"), else: gettext("Paused")}</h3>
            <p>{pause_text(@webhook)}</p>
          </div>
          <div class="integrations-actions">
            <button
              :if={@webhook.active}
              type="button"
              class="workspace-button"
              phx-click="pause"
              data-testid="webhook-pause"
            >
              <.icon name="pause" />{gettext("Pause")}
            </button>
            <button
              :if={!@webhook.active}
              type="button"
              class="workspace-button"
              phx-click="resume"
              data-testid="webhook-resume"
            >
              <.icon name="play" />{gettext("Resume")}
            </button>
          </div>
        </article>
        <article class="integrations-row plain">
          <div class="integrations-text">
            <h3>{gettext("Delete webhook")}</h3>
            <p>{gettext("Stops all deliveries and removes the delivery log.")}</p>
          </div>
          <div class="integrations-actions">
            <button
              type="button"
              class="workspace-button destructive"
              phx-click="delete"
              data-confirm-title={gettext("Delete this webhook?")}
              data-confirm={gettext("Nothing more is sent to it, and its delivery log is removed.")}
              data-confirm-ok={gettext("Delete webhook")}
              data-confirm-destructive
              data-testid="webhook-delete"
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
      <.back_link to="/admin/config/webhooks" label={gettext("Webhooks")} />
      <Workspace.header
        title={gettext("Delivery log")}
        subtitle={
          if @webhook,
            do: "#{@webhook.name} · #{Webhooks.host(@webhook)}",
            else: gettext("What was sent to every webhook in this environment, newest first.")
        }
      >
        <span :if={@webhook}><.state webhook={@webhook} /></span>
        <button
          :if={@webhook}
          type="button"
          class="workspace-button"
          phx-click="send_test"
          disabled={!@webhook.active}
          data-testid="webhook-send-test"
        >
          <.icon name="send" />{gettext("Send test event")}
        </button>
        <.link :if={@webhook} navigate={"/admin/config/webhooks/#{@webhook.id}/edit"} class="workspace-button">
          {gettext("Edit")}
        </.link>
      </Workspace.header>

      <p :if={@webhook && !@webhook.active} class="webhook-paused-note" role="status">{pause_text(@webhook)}</p>

      <section class="workspace-panel">
        <div :if={@deliveries == []}>
          <Workspace.empty
            title={gettext("Nothing sent yet")}
            description={gettext("Deliveries show here when content changes, or when you send a test event.")}
          />
        </div>
        <div :if={@deliveries != []} class="workspace-table-scroll">
          <table class="workspace-table webhook-log" data-testid="webhook-log">
            <thead>
              <tr>
                <th scope="col">{gettext("Time")}</th>
                <th :if={!@webhook} scope="col">{gettext("Webhook")}</th>
                <th scope="col">{gettext("Event")}</th>
                <th scope="col">{gettext("Entry")}</th>
                <th scope="col">{gettext("Response")}</th>
                <th scope="col">{gettext("Duration")}</th>
                <th scope="col"><span class="workspace-sr-only">{gettext("Actions")}</span></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={delivery <- @deliveries} id={"delivery-#{delivery.id}"} data-state={delivery.state}>
                <td><BrandoAdmin.Dates.time at={delivery.inserted_at} format={:short} /></td>
                <td :if={!@webhook}>{delivery.webhook && delivery.webhook.name}</td>
                <td>
                  {event_label(delivery.event)}
                  <small class="workspace-mono">{delivery.event}</small>
                </td>
                <td><.entry delivery={delivery} types={@entry_type_options} titles={@entry_titles} /></td>
                <td>
                  <.delivery_state delivery={delivery} />
                  <small :if={delivery.error} class="webhook-error">{error_text(delivery.error)}</small>
                  <small :if={delivery.response_body not in [nil, ""]} class="webhook-response" title={delivery.response_body}>
                    {String.slice(delivery.response_body, 0, 120)}
                  </small>
                </td>
                <td class="webhook-duration">{duration(delivery.duration_ms)}</td>
                <td class="row-actions">
                  <button
                    :if={delivery.state not in ["pending", "sending"]}
                    type="button"
                    class="workspace-button"
                    phx-click="redeliver"
                    phx-value-id={delivery.id}
                    data-testid="webhook-redeliver"
                  >
                    <.icon name="refresh-cw" />{gettext("Redeliver")}
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

  ## Components

  attr :to, :string, required: true
  attr :label, :string, required: true

  defp back_link(assigns) do
    ~H"""
    <.link navigate={@to} class="integrations-back"><.icon name="arrow-left" />{@label}</.link>
    """
  end

  defp secret_panel(assigns) do
    ~H"""
    <section
      id="webhook-secret"
      class="workspace-panel webhook-secret"
      phx-hook="Brando.WebhookSecret"
      phx-update="ignore"
      aria-labelledby="webhook-secret-title"
      data-testid="webhook-secret"
      hidden
    >
      <div class="webhook-secret-text">
        <h2 id="webhook-secret-title">{gettext("Copy the signing secret now")}</h2>
        <p>
          {gettext("It is shown only this once. The receiver uses it to check the Brando-Signature header of every request.")}
        </p>
      </div>
      <div class="webhook-secret-value">
        <input
          type="text"
          readonly
          aria-label={gettext("Signing secret")}
          spellcheck="false"
          autocomplete="off"
          data-webhook-secret-value
          data-testid="webhook-secret-value"
        />
        <button
          type="button"
          class="workspace-button"
          data-webhook-secret-copy
          data-copy={gettext("Copy")}
          data-copied={gettext("Copied")}
        >
          {gettext("Copy")}
        </button>
        <button type="button" class="workspace-button primary" data-webhook-secret-done data-testid="webhook-secret-done">
          {gettext("Done")}
        </button>
      </div>
    </section>
    """
  end

  attr :webhook, Webhook, required: true

  defp state(assigns) do
    ~H"""
    <span :if={@webhook.active} class="workspace-badge positive" data-testid="webhook-state">{gettext("Active")}</span>
    <span
      :if={!@webhook.active}
      class={["workspace-badge", if(@webhook.paused_reason == :failures, do: "negative", else: "warning")]}
      data-testid="webhook-state"
    >
      {paused_label(@webhook.paused_reason)}
    </span>
    """
  end

  defp paused_label(:failures), do: gettext("Paused after failures")
  defp paused_label(:environment_copy), do: gettext("Paused: copied environment")
  defp paused_label(_), do: gettext("Paused")

  defp pause_text(%Webhook{active: true}),
    do: gettext("Events are sent as content changes. Pausing stops them until you resume.")

  defp pause_text(%Webhook{paused_reason: :failures}),
    do: gettext("Paused because its deliveries kept failing for a day. Check the receiver, then resume.")

  defp pause_text(%Webhook{paused_reason: :environment_copy}),
    do:
      gettext(
        "Paused because this environment was copied or restored from another one. It resumes when this environment goes live; resume it sooner only if this environment should call this URL."
      )

  defp pause_text(_webhook), do: gettext("Nothing is sent while it is paused. Changes made meanwhile are not sent later.")

  attr :delivery, :map, required: true

  defp delivery_state(assigns) do
    ~H"""
    <span class={["workspace-badge", state_tone(@delivery.state)]} data-testid="delivery-state">
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
  defp state_label(state), do: state

  defp error_text("timeout"), do: gettext("No answer within 10 seconds")
  defp error_text("connection_failed"), do: gettext("Could not connect")
  defp error_text("unresolvable"), do: gettext("The host name could not be found")
  defp error_text("private_address"), do: gettext("The address is on a private network")
  defp error_text("https_required"), do: gettext("The URL is not https")
  defp error_text("secret_unreadable"), do: gettext("The secret could not be read; rotate it")
  defp error_text("webhook_paused"), do: gettext("The webhook was paused")
  defp error_text("invalid_response"), do: gettext("Not a valid HTTP response")
  defp error_text(other), do: other

  defp duration(nil), do: ""
  defp duration(ms) when ms < 1000, do: "#{ms} ms"
  defp duration(ms), do: "#{Float.round(ms / 1000, 1)} s"

  attr :delivery, :map, required: true
  attr :types, :list, required: true
  attr :titles, :map, required: true

  defp entry(%{delivery: %{entry_id: nil}} = assigns) do
    ~H"""
    <span class="webhook-muted">—</span>
    """
  end

  defp entry(assigns) do
    delivery = assigns.delivery
    type = type_label(assigns.types, delivery.entry_type) || delivery.entry_type

    assigns =
      assign(assigns,
        title: assigns.titles[{delivery.entry_schema, delivery.entry_id}] || "#{type} ##{delivery.entry_id}",
        details: Enum.reject([type, delivery.language && String.upcase(delivery.language)], &is_nil/1),
        path: entry_path(delivery)
      )

    ~H"""
    <.link :if={@path} navigate={@path}>{@title}</.link>
    <span :if={!@path}>{@title}</span>
    <small>{Enum.join(@details, " · ")}</small>
    """
  end

  defp type_label(types, entry_type) do
    case List.keyfind(types, entry_type, 1) do
      {label, _} -> label
      nil -> entry_type
    end
  end

  defp entry_path(%{entry_schema: schema, entry_id: id}) when is_binary(schema) do
    case BrandoAdmin.Components.Activity.schema(schema) do
      nil -> nil
      module -> module.__admin_route__(:update, [id])
    end
  rescue
    _ -> nil
  end

  defp entry_path(_delivery), do: nil

  attr :field, Phoenix.HTML.FormField, required: true

  defp field_errors(assigns) do
    ~H"""
    <p :for={{_message, opts} <- @field.errors} :if={@field.errors != []} class="webhook-error" role="alert">
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
      other -> validation_error(other)
    end
  end

  defp validation_error(:required), do: gettext("Fill this in.")
  defp validation_error(:length), do: gettext("This is too long.")
  defp validation_error(_), do: gettext("Check this value.")

  ## Summaries

  defp events_summary(%Webhook{events: []}), do: gettext("All events")
  defp events_summary(%Webhook{events: events}), do: Enum.map_join(events, ", ", &event_label/1)

  defp filters_summary(%Webhook{entry_types: [], languages: []}, _types), do: nil

  defp filters_summary(%Webhook{} = webhook, types) do
    parts =
      Enum.map(webhook.entry_types, &type_label(types, &1)) ++ Enum.map(webhook.languages, &String.upcase/1)

    " · " <> Enum.join(parts, ", ")
  end

  defp last_delivery(%Webhook{last_delivery_state: "succeeded"} = webhook),
    do: gettext("Last delivered %{time}", time: BrandoAdmin.Dates.clock(webhook.last_delivery_at))

  defp last_delivery(%Webhook{} = webhook),
    do: gettext("Last delivery failed %{time}", time: BrandoAdmin.Dates.clock(webhook.last_delivery_at))
end
