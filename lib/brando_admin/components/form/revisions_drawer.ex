defmodule BrandoAdmin.Components.Form.RevisionsDrawer do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Button
  alias BrandoAdmin.Components.CircleDropdown
  alias BrandoAdmin.Components.Content
  alias Phoenix.LiveView.AsyncResult

  @page_size 50

  def update(%{action: action}, socket) when action in [:fetch_revisions, :refresh_revisions] do
    {:ok, load_revisions(socket)}
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
     |> assign_new(:show_publish_at, fn -> nil end)
     |> assign_new(:preview_revision, fn -> nil end)
     |> assign_new(:revision_data, fn -> AsyncResult.loading() end)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <Content.drawer id={@id} title={gettext("Entry revisions")} close={@close}>
        <:info>
          <p>
            {gettext(
              "Load a revision into the editor to inspect or reuse it. Loading replaces unsaved editor changes, but does not update the saved entry until you save or activate it."
            )}
          </p>
          <p>
            {gettext(
              "You can also store the editor's current state as an inactive revision for later previewing or scheduled publishing."
            )}
          </p>
          <div class="button-group">
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

        <%= if @status == :open do %>
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
              <thead>
                <tr>
                  <th scope="col">{gettext("Revision")}</th>
                  <th scope="col">{gettext("Status")}</th>
                  <th scope="col">{gettext("Protection")}</th>
                  <th scope="col">{gettext("Schedule")}</th>
                  <th scope="col">{gettext("Created")}</th>
                  <th scope="col">{gettext("Schema")}</th>
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
                    <td class="fit">
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
                    </td>
                    <td class="fit status">
                      <span
                        :if={revision.active}
                        class="revision-active-marker"
                        title={gettext("Active revision")}
                        aria-label={gettext("Active revision")}
                      >
                        &#9679;
                      </span>
                      <span :if={!revision.active}>{gettext("Inactive")}</span>
                    </td>
                    <td class="fit protected">
                      <span
                        :if={revision.protected}
                        title={gettext("Protected revision")}
                        aria-label={gettext("Protected revision")}
                      >
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">
                          <path fill="none" d="M0 0h24v24H0z" /><path d="M6 8V7a6 6 0 1 1 12 0v1h2a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1h2zm13 2H5v10h14V10zm-8 5.732a2 2 0 1 1 2 0V18h-2v-2.268zM8 8h8V7a4 4 0 1 0-8 0v1z" />
                        </svg>
                      </span>
                      <span :if={!revision.protected}>—</span>
                    </td>
                    <td class="fit scheduled">
                      <span :if={revision.scheduled} class="revision-scheduled-badge">
                        {gettext("Scheduled")}
                      </span>
                      <span :if={!revision.scheduled}>—</span>
                    </td>
                    <td class="date fit">
                      {Brando.Utils.Datetime.format_datetime(revision.inserted_at, "%d/%m/%y, %H:%M")}
                    </td>
                    <td class="schema-version fit">
                      <span :if={revision.schema_version}>v{revision.schema_version}</span>
                    </td>
                    <td class="user">{creator_name(revision)}</td>
                    <td class="activate fit">
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
                    <td colspan="8" class="revision-publish_at">
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
                    <td colspan="8" class="revision-description">&uarr; {revision.description}</td>
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
        send_update(BrandoAdmin.Components.Form,
          id: socket.assigns.form_id,
          action: :update_entry_hard_reset,
          updated_entry: decoded_entry
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
        send_update(BrandoAdmin.Components.Form,
          id: socket.assigns.form_id,
          action: :update_entry_hard_reset,
          updated_entry: new_entry
        )

        send(self(), {:toast, gettext("Revision activated")})

        {:noreply,
         socket
         |> assign(:preview_revision, nil)
         |> load_revisions()}

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

  defp creator_name(%{creator: nil}), do: gettext("System")
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
