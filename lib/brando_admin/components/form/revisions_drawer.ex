defmodule BrandoAdmin.Components.Form.RevisionsDrawer do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Activity, as: Events
  alias BrandoAdmin.Components.Activity.Comparison
  alias BrandoAdmin.Components.Button
  alias BrandoAdmin.Components.CircleDropdown
  alias BrandoAdmin.Components.Content
  alias Phoenix.LiveView.AsyncResult

  @page_size 50
  @activity_page_size 30

  def update(%{action: action}, socket) when action in [:fetch_revisions, :refresh_revisions] do
    {:ok, socket |> load_revisions() |> load_activity()}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    {:ok,
     socket
     |> assign_new(:entry_type, fn -> socket.assigns.form.source.data.__struct__ end)
     |> assign_new(:schema_version, fn ->
       entry_type = socket.assigns.form.source.data.__struct__
       Brando.Blueprint.Snapshot.get_current_version(entry_type)
     end)
     |> assign_new(:tab, fn -> :activity end)
     |> assign_new(:activity, fn -> nil end)
     |> assign_new(:comparison, fn -> nil end)
     |> assign_new(:show_publish_at, fn -> nil end)
     |> assign_new(:preview_revision, fn -> nil end)
     |> assign_new(:revision_data, fn -> AsyncResult.loading() end)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <Content.drawer id={@id} title={gettext("Entry history")} close={@close} icon="clock" workspace editor>
        <:info>
          <div class="pill-tabs pill-tabs--small activity-tabs" role="tablist" aria-label={gettext("Entry history")}>
            <button
              type="button"
              role="tab"
              id={"#{@id}-tab-activity"}
              aria-selected={to_string(@tab == :activity)}
              phx-click={JS.push("tab", value: %{tab: "activity"}, target: @myself)}
            >
              {gettext("Activity")}
            </button>
            <button
              type="button"
              role="tab"
              id={"#{@id}-tab-revisions"}
              aria-selected={to_string(@tab == :revisions)}
              phx-click={JS.push("tab", value: %{tab: "revisions"}, target: @myself)}
            >
              {gettext("Revisions")}
              <span :if={revision_count(@revision_data)} class="pill-tabs-count">{revision_count(@revision_data)}</span>
            </button>
          </div>
          <p :if={@tab == :activity}>
            {gettext(
              "Everything that happened to this entry, including publishing, trash and restores. Open a revision to see or reuse its content."
            )}
          </p>
          <p :if={@tab == :revisions}>
            {gettext(
              "Load a revision into the editor to inspect or reuse it. Loading replaces unsaved editor changes, but does not update the saved entry until you save or activate it."
            )}
          </p>
          <p :if={@tab == :revisions}>
            {gettext(
              "You can also store the editor's current state as an inactive revision for later previewing or scheduled publishing."
            )}
          </p>
          <div :if={@tab == :revisions} class="button-group">
            <button
              type="button"
              class="secondary"
              phx-click={JS.push("store_revision", target: @form_cid)}
            >
              {gettext("Store current editor state")}
            </button>

            <button
              type="button"
              class="secondary"
              id="revisions-drawer-confirm-purge"
              phx-hook="Brando.ConfirmClick"
              phx-confirm-click-message={
                gettext("Purge every inactive revision that is not protected or scheduled? This cannot be undone.")
              }
              phx-confirm-click={JS.push("purge_inactive_revisions", target: @myself)}
            >
              {gettext("Purge inactive versions")}
            </button>
          </div>
        </:info>

        <.activity
          :if={@status == :open and @tab == :activity}
          id={"#{@id}-activity"}
          activity={@activity}
          comparison={@comparison}
          schema_version={@schema_version}
          myself={@myself}
        />

        <%= if @status == :open and @tab == :revisions do %>
          <div :if={@preview_revision} class="revision-preview-notice" role="status">
            {gettext(
              "Revision %{revision} is loaded as an unsaved working copy.",
              %{revision: @preview_revision}
            )}
          </div>

          <.async_result :let={data} assign={@revision_data}>
            <:loading>
              <div class="revisions-loading" role="status">
                <svg class="spinner" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
                  <circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="2" fill="none" opacity="0.3" />
                  <path
                    d="M12 2 A10 10 0 0 1 22 12"
                    stroke="currentColor"
                    stroke-width="2"
                    fill="none"
                    stroke-linecap="round"
                  />
                </svg>
                <span>{gettext("Loading revisions...")}</span>
              </div>
            </:loading>
            <:failed :let={_failure}>
              <div class="revisions-error" role="alert">
                <span>{gettext("Failed to load revisions.")}</span>
                <button type="button" class="secondary" phx-click="fetch_revisions" phx-target={@myself}>
                  {gettext("Try again")}
                </button>
              </div>
            </:failed>

            <div class="current-schema-version">
              {gettext("Current schema version")}: <span class="version">v{@schema_version}</span>
            </div>

            <div :if={data.revisions == []} class="revisions-empty">
              {gettext("No revisions have been stored yet.")}
            </div>

            <table :if={data.revisions != []} class="revisions-table">
              <colgroup>
                <col class="revision-column" />
                <col class="status-column" />
                <col class="created-column" />
                <col class="author-column" />
                <col class="actions-column" />
              </colgroup>
              <thead>
                <tr>
                  <th scope="col">{gettext("Revision")}</th>
                  <th scope="col">{gettext("Status")}</th>
                  <th scope="col">{gettext("Created")}</th>
                  <th scope="col">{gettext("Author")}</th>
                  <th scope="col"><span class="sr-only">{gettext("Actions")}</span></th>
                </tr>
              </thead>
              <tbody>
                <%= for revision <- data.revisions do %>
                  <tr
                    id={"revision-line-#{revision.revision}"}
                    class={[
                      "revisions-line",
                      revision.active && "active",
                      revision.schema_version != @schema_version && "outdated"
                    ]}
                  >
                    <td class="revision-number">
                      <button
                        type="button"
                        id={"preview-revision-#{revision.revision}"}
                        class="revision-preview-button"
                        phx-hook="Brando.ConfirmClick"
                        phx-confirm-click-message={preview_confirmation(revision, @schema_version)}
                        phx-confirm-click={
                          JS.push("select_revision",
                            value: %{revision: revision.revision},
                            target: @myself
                          )
                        }
                      >
                        #{revision.revision}
                      </button>
                      <span :if={revision.schema_version} class="revision-schema">{gettext("Schema")} v{revision.schema_version}</span>
                    </td>
                    <td class="status">
                      <div class="revision-statuses">
                        <span class={["revision-status", revision.active && "is-active"]}>
                          {if revision.active, do: gettext("Active"), else: gettext("Inactive")}
                        </span>
                        <span :if={revision.scheduled} class="revision-status is-scheduled">
                          <.icon name="calendar-days" />{gettext("Scheduled")}
                        </span>
                        <span :if={revision.protected} class="revision-protection">
                          <.icon name="lock" />{gettext("Protected")}
                        </span>
                      </div>
                    </td>
                    <td class="date" data-label={gettext("Created")}>
                      <time
                        datetime={revision_datetime(revision.inserted_at)}
                        title={BrandoAdmin.Dates.full(revision.inserted_at)}
                      >
                        {Brando.Utils.Datetime.format_datetime(revision.inserted_at, "%d.%m.%y")}
                        <span class="revision-time">{Brando.Utils.Datetime.format_datetime(revision.inserted_at, "%H:%M")}</span>
                      </time>
                    </td>
                    <td class="user" data-label={gettext("Author")}>
                      <Content.modal_person
                        :if={revision.creator}
                        user={%{revision.creator | name: creator_name(revision)}}
                        compact
                      />
                      <span :if={!revision.creator}>{gettext("System")}</span>
                    </td>
                    <td class="activate">
                      <CircleDropdown.render id={"revision-dropdown-#{revision.revision}"}>
                        <Button.dropdown
                          :if={!revision.active}
                          confirm={activation_confirmation(revision, @schema_version)}
                          value={revision.revision}
                          event={
                            JS.push("activate_revision",
                              target: @myself,
                              value: %{value: revision.revision}
                            )
                          }
                        >
                          {gettext("Activate revision")}
                        </Button.dropdown>

                        <Button.dropdown
                          :if={revision.protected}
                          event={
                            JS.push("unprotect_revision",
                              target: @myself,
                              value: %{value: revision.revision}
                            )
                          }
                          value={revision.revision}
                        >
                          {gettext("Unprotect version")}
                        </Button.dropdown>
                        <Button.dropdown
                          :if={!revision.protected}
                          event={
                            JS.push("protect_revision",
                              target: @myself,
                              value: %{value: revision.revision}
                            )
                          }
                          value={revision.revision}
                        >
                          {gettext("Protect version")}
                        </Button.dropdown>

                        <Button.dropdown
                          :if={!revision.active && !revision.scheduled}
                          event={
                            JS.push("show_publish_at",
                              target: @myself,
                              value: %{value: revision.revision}
                            )
                          }
                          value={revision.revision}
                        >
                          {gettext("Schedule version")}
                        </Button.dropdown>
                        <Button.dropdown
                          :if={revision.scheduled}
                          confirm={gettext("Cancel scheduled publishing for this revision?")}
                          event={
                            JS.push("cancel_scheduled_revision",
                              target: @myself,
                              value: %{value: revision.revision}
                            )
                          }
                          value={revision.revision}
                        >
                          {gettext("Cancel schedule")}
                        </Button.dropdown>

                        <Button.dropdown
                          :if={!revision.protected && !revision.active && !revision.scheduled}
                          confirm={gettext("Delete this revision permanently?")}
                          event={
                            JS.push("delete_revision",
                              target: @myself,
                              value: %{value: revision.revision}
                            )
                          }
                          value={revision.revision}
                        >
                          {gettext("Delete version")}
                        </Button.dropdown>
                      </CircleDropdown.render>
                    </td>
                  </tr>

                  <tr :if={@show_publish_at == revision.revision} class="revisions-line revision-schedule-row">
                    <td colspan="5" class="revision-publish_at">
                      <div class="field-wrapper">
                        <label>{gettext("Publish at")}</label>
                        <div class="datepicker-and-button">
                          <div
                            id={"revision-#{revision.revision}-datetimepicker"}
                            class="datetime-wrapper"
                            phx-hook="Brando.Scheduler"
                            data-locale={Gettext.get_locale()}
                            data-revision={revision.revision}
                          >
                            <div id={"revision-#{revision.revision}-datetimepicker-flatpickr"} phx-update="ignore">
                              <input type="hidden" class="flatpickr" />
                            </div>
                          </div>
                          <button type="button">{gettext("Schedule")}</button>
                        </div>
                      </div>
                    </td>
                  </tr>

                  <tr :if={revision.description} class="revisions-line revision-description-row">
                    <td colspan="5" class="revision-description">{revision.description}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>

            <button
              :if={data.has_more}
              type="button"
              class="secondary revisions-load-more"
              phx-click="load_more"
              phx-target={@myself}
            >
              {gettext("Load more revisions")}
            </button>
          </.async_result>
        <% end %>
      </Content.drawer>
    </div>
    """
  end

  def handle_event("tab", %{"tab" => tab}, socket) when tab in ["activity", "revisions"] do
    {:noreply, socket |> assign(:tab, String.to_existing_atom(tab)) |> assign(:comparison, nil)}
  end

  def handle_event("activity_more", _, socket) do
    {:noreply, load_activity(socket, length(socket.assigns.activity.events) + @activity_page_size)}
  end

  def handle_event("compare", %{"id" => id}, socket) do
    with %{events: events} <- socket.assigns.activity,
         event when not is_nil(event) <- Enum.find(events, &(to_string(&1.id) == id)),
         {from, to} <- Comparison.revisions(event) do
      result = Comparison.build(entry_schema(socket), socket.assigns.entry_id, from, to, socket.assigns.current_user)
      {:noreply, assign(socket, :comparison, %{event: event, result: result})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("close_compare", _, socket), do: {:noreply, assign(socket, :comparison, nil)}

  def handle_event("fetch_revisions", _, socket) do
    {:noreply, load_revisions(socket)}
  end

  def handle_event("load_more", _, socket) do
    case socket.assigns.revision_data do
      %AsyncResult{ok?: true, result: %{revisions: revisions}} ->
        {:noreply, load_revisions(socket, revisions)}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("purge_inactive_revisions", _, socket) do
    {count, _} = Brando.Revisions.purge_revisions(entry_schema(socket), socket.assigns.entry_id)
    send(self(), {:toast, gettext("Purged %{count} revisions", %{count: count})})
    {:noreply, load_revisions(socket)}
  end

  def handle_event("delete_revision", %{"value" => revision}, socket) do
    case Brando.Revisions.delete_revision(entry_schema(socket), socket.assigns.entry_id, revision) do
      {1, _} ->
        send(self(), {:toast, gettext("Revision deleted")})
        {:noreply, load_revisions(socket)}

      {0, _} ->
        {:noreply, alert_error(socket, gettext("Active, protected, or scheduled revisions cannot be deleted."))}
    end
  end

  def handle_event("protect_revision", %{"value" => revision}, socket) do
    update_protection(socket, revision, true)
  end

  def handle_event("unprotect_revision", %{"value" => revision}, socket) do
    update_protection(socket, revision, false)
  end

  def handle_event("show_publish_at", %{"value" => revision}, socket) do
    {:noreply, assign(socket, :show_publish_at, revision)}
  end

  def handle_event(
        "schedule",
        %{"revision" => revision, "publish_at" => publish_at},
        socket
      ) do
    case Brando.Publisher.schedule_revision(
           entry_schema(socket),
           socket.assigns.entry_id,
           revision,
           publish_at,
           socket.assigns.current_user
         ) do
      {:ok, _job} ->
        send(self(), {:toast, gettext("Scheduled revision for publishing")})

        {:noreply,
         socket
         |> assign(:show_publish_at, nil)
         |> load_revisions()}

      {:error, reason} ->
        {:noreply, alert_error(socket, schedule_error(reason))}
    end
  end

  def handle_event("cancel_scheduled_revision", %{"value" => revision}, socket) do
    case Brando.Publisher.cancel_scheduled_revision(
           entry_schema(socket),
           socket.assigns.entry_id,
           revision
         ) do
      :ok ->
        send(self(), {:toast, gettext("Scheduled publishing cancelled")})
        {:noreply, load_revisions(socket)}

      {:error, reason} ->
        {:noreply, alert_error(socket, schedule_error(reason))}
    end
  end

  def handle_event("select_revision", %{"revision" => revision_number}, socket) do
    case Brando.Revisions.get_revision(
           socket.assigns.entry_type,
           socket.assigns.entry_id,
           revision_number
         ) do
      {:ok, {_revision, {_revision_id, decoded_entry}}} ->
        # A previewed revision is this editor's alone: its blocks leave the
        # entry's edit session until it is saved.
        send_update(BrandoAdmin.Components.Form,
          id: socket.assigns.form_id,
          action: :update_entry_hard_reset,
          updated_entry: decoded_entry,
          detached: true
        )

        {:noreply, assign(socket, :preview_revision, revision_number)}

      {:error, _reason} ->
        {:noreply, alert_error(socket, gettext("This revision could not be loaded."))}

      :error ->
        {:noreply, alert_error(socket, gettext("This revision no longer exists."))}
    end
  end

  def handle_event("activate_revision", %{"value" => revision_number}, socket) do
    case Brando.Revisions.set_entry_to_revision(
           entry_schema(socket),
           socket.assigns.entry_id,
           revision_number,
           socket.assigns.current_user
         ) do
      {:ok, new_entry} ->
        # The others editing the entry move onto the activated revision too.
        Brando.EditSession.sync_saved(new_entry)

        send_update(BrandoAdmin.Components.Form,
          id: socket.assigns.form_id,
          action: :update_entry_hard_reset,
          updated_entry: new_entry
        )

        send(self(), {:toast, gettext("Revision activated")})

        {:noreply,
         socket
         |> assign(:preview_revision, nil)
         |> load_revisions()
         |> load_activity()}

      {:error, _reason} ->
        {:noreply, alert_error(socket, gettext("The revision could not be activated."))}
    end
  end

  defp load_revisions(socket, loaded_revisions \\ []) do
    entry_id = socket.assigns.entry_id
    entry_type = socket.assigns.entry_type
    offset = length(loaded_revisions)

    {:ok, revisions} =
      Brando.Revisions.list_revision_metadata(entry_type, entry_id,
        limit: @page_size + 1,
        offset: offset
      )

    revision_data = %{
      revisions: loaded_revisions ++ Enum.take(revisions, @page_size),
      has_more: length(revisions) > @page_size
    }

    assign(socket, :revision_data, AsyncResult.ok(revision_data))
  rescue
    reason ->
      failed_result =
        AsyncResult.loading()
        |> AsyncResult.failed(reason)

      assign(socket, :revision_data, failed_result)
  end

  defp load_activity(socket, limit \\ @activity_page_size) do
    events = Brando.Activity.for_entry(entry_schema(socket), socket.assigns.entry_id, limit: limit + 1)
    shown = Enum.take(events, limit)

    assign(socket, :activity, %{
      events: shown,
      states: Events.states(shown),
      has_more: length(events) > limit
    })
  rescue
    _ -> assign(socket, :activity, %{events: [], states: %{}, has_more: false})
  end

  defp revision_count(%AsyncResult{ok?: true, result: %{revisions: revisions, has_more: true}}),
    do: "#{length(revisions)}+"

  defp revision_count(%AsyncResult{ok?: true, result: %{revisions: revisions}}), do: length(revisions)
  defp revision_count(_), do: nil

  attr :id, :string, required: true
  attr :activity, :any, required: true
  attr :comparison, :any, required: true
  attr :schema_version, :any, required: true
  attr :myself, :any, required: true

  defp activity(%{comparison: %{event: event}} = assigns) do
    {from, to} = Comparison.revisions(event)
    assigns = assign(assigns, from: from, to: to)

    ~H"""
    <div class="activity-drawer-compare">
      <button type="button" class="secondary" phx-click="close_compare" phx-target={@myself}>
        ← {gettext("All activity")}
      </button>
      <h3>{gettext("Revision #%{from} → revision #%{to}", from: @from, to: @to)}</h3>
      <Events.comparison id={"#{@id}-comparison"} comparison={@comparison.result} />
    </div>
    """
  end

  defp activity(%{activity: nil} = assigns) do
    ~H"""
    <div class="revisions-loading" role="status"><span>{gettext("Loading activity...")}</span></div>
    """
  end

  defp activity(assigns) do
    ~H"""
    <p :if={@activity.events == []} class="revisions-empty">
      {gettext("Nothing has been recorded for this entry yet.")}
    </p>
    <ol :if={@activity.events != []} id={@id} class="activity-timeline">
      <li :for={event <- @activity.events} id={"#{@id}-#{event.id}"}>
        <Events.marker event={event} />
        <div>
          <p><Events.action event={event} /> {Events.by_phrase(event)}</p>
          <Events.details event={event} states={@activity.states} />
          <p class="activity-meta">
            <time datetime={DateTime.to_iso8601(event.inserted_at)}>{Events.when_label(event.inserted_at)}</time>
            <button
              :if={event.revision && event.action != :deleted}
              type="button"
              id={"#{@id}-#{event.id}-revision"}
              class="activity-revision"
              phx-hook="Brando.ConfirmClick"
              phx-confirm-click-message={
                gettext("Load revision %{revision} into the editor? Unsaved editor changes will be replaced.",
                  revision: event.revision
                )
              }
              phx-confirm-click={JS.push("select_revision", value: %{revision: event.revision}, target: @myself)}
            >
              {gettext("Revision #%{revision}", revision: event.revision)}
            </button>
            <button
              :if={Comparison.revisions(event)}
              type="button"
              class="activity-compare-link"
              phx-click="compare"
              phx-value-id={event.id}
              phx-target={@myself}
            >
              {gettext("Compare with #%{revision}", revision: elem(Comparison.revisions(event), 0))}
            </button>
          </p>
        </div>
      </li>
    </ol>
    <button
      :if={@activity.has_more}
      type="button"
      class="secondary activity-drawer-more"
      phx-click="activity_more"
      phx-target={@myself}
    >
      {gettext("Show older activity")}
    </button>
    """
  end

  defp update_protection(socket, revision, protect?) do
    case Brando.Revisions.protect_revision(
           entry_schema(socket),
           socket.assigns.entry_id,
           revision,
           protect?
         ) do
      {1, _} -> {:noreply, load_revisions(socket)}
      {0, _} -> {:noreply, alert_error(socket, gettext("This revision no longer exists."))}
    end
  end

  defp entry_schema(socket), do: socket.assigns.form.source.data.__struct__

  defp revision_datetime(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime) <> "Z"
  defp revision_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp creator_name(%{creator: %{name: nil}}), do: gettext("Unknown user")
  defp creator_name(%{creator: %{name: name}}), do: name

  defp preview_confirmation(revision, current_schema_version) do
    confirmation =
      gettext(
        "Load revision %{revision} into the editor? Unsaved editor changes will be replaced.",
        %{revision: revision.revision}
      )

    if revision.schema_version == current_schema_version do
      confirmation
    else
      confirmation <>
        " " <>
        gettext("Its schema version differs from the current schema, so some fields may not load correctly.")
    end
  end

  defp activation_confirmation(revision, current_schema_version) do
    confirmation =
      gettext(
        "Activate revision %{revision}? This immediately replaces the saved entry.",
        %{revision: revision.revision}
      )

    if revision.schema_version == current_schema_version do
      confirmation
    else
      confirmation <>
        " " <>
        gettext("Its schema version differs from the current schema, so some fields may not restore correctly.")
    end
  end

  defp schedule_error(:invalid_publish_at), do: gettext("Choose a valid publishing date and time.")

  defp schedule_error(:publish_at_must_be_in_the_future),
    do: gettext("The publishing date must be in the future.")

  defp schedule_error(:revision_already_active),
    do: gettext("The active revision cannot be scheduled.")

  defp schedule_error(:revision_not_found), do: gettext("This revision no longer exists.")
  defp schedule_error(_reason), do: gettext("Scheduled publishing could not be updated.")

  defp alert_error(socket, message) do
    push_event(socket, "b:alert", %{
      title: gettext("Revision error"),
      message: message,
      type: "error"
    })
  end
end
