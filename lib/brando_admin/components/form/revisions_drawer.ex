defmodule BrandoAdmin.Components.Form.RevisionsDrawer do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Button
  alias BrandoAdmin.Components.CircleDropdown
  alias BrandoAdmin.Components.Content

  # prop form, :form, required: true
  # prop current_user, :any, required: true
  # prop blueprint, :any, required: true
  # prop status, :atom, default: :closed
  # prop close, :event

  # data revisions, :list
  # data active_revision, :any

  def update(%{action: :refresh_revisions}, socket) do
    entry_id = socket.assigns.entry_id
    entry_type = socket.assigns.entry_type

    {:ok,
     socket
     |> assign_async([:revisions, :active_revision], fn ->
       list_opts = %{
         filter: %{entry_id: entry_id, entry_type: entry_type},
         preload: [:creator],
         order: [{:desc, :revision}]
       }

       case Brando.Revisions.list_revisions(list_opts) do
         {:ok, revisions} ->
           active_revision =
             case Enum.find(revisions, & &1.active) do
               nil -> nil
               %{revision: revision} -> revision
             end

           {:ok, %{revisions: revisions, active_revision: active_revision}}

         {:error, _} ->
           {:error, :failed_to_load_revisions}
       end
     end)}
  end

  def update(%{action: :fetch_revisions}, socket) do
    entry_id = socket.assigns.entry_id
    entry_type = socket.assigns.entry_type

    {:ok,
     socket
     |> assign_async([:revisions, :active_revision], fn ->
       list_opts = %{
         filter: %{entry_id: entry_id, entry_type: entry_type},
         preload: [:creator],
         order: [{:desc, :revision}]
       }

       case Brando.Revisions.list_revisions(list_opts) do
         {:ok, revisions} ->
           active_revision =
             case Enum.find(revisions, & &1.active) do
               nil -> nil
               %{revision: revision} -> revision
             end

           {:ok, %{revisions: revisions, active_revision: active_revision}}

         {:error, _} ->
           {:error, :failed_to_load_revisions}
       end
     end)}
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
     |> assign_new(:revisions, fn -> Phoenix.LiveView.AsyncResult.loading() end)
     |> assign_new(:active_revision, fn -> Phoenix.LiveView.AsyncResult.loading() end)}
  end

  defp refresh_revisions(socket) do
    send_update(__MODULE__,
      id: socket.assigns.id,
      action: :refresh_revisions
    )

    socket
  end

  def render(assigns) do
    ~H"""
    <div>
      <Content.drawer id={@id} title={gettext("Entry revisions")} close={@close}>
        <:info>
          <p>
            {gettext("This is a list of this entry's revisions. Click a row to preview.")}
          </p>
          <p>
            {gettext(
              "You may also store a new version of the entry without activating it. This might be useful for scheduling content publishing, or sharing previews of unpublished entries."
            )}
          </p>
          <div class="button-group">
            <button type="button" class="secondary" phx-click={JS.push("store_revision", target: @myself)}>
              {gettext("Save version without activating")}
            </button>

            <button
              type="button"
              class="secondary"
              id="revisions-drawer-confirm-purge"
              phx-hook="Brando.ConfirmClick"
              phx-confirm-click-message={
                gettext("Are you sure you want to purge unprotected and non active revisions of this entry?")
              }
              phx-confirm-click={JS.push("purge_inactive_revisions", target: @myself)}
            >
              {gettext("Purge inactive versions")}
            </button>
          </div>
        </:info>
        <%= if @status == :open do %>
          <.async_result :let={revisions} assign={@revisions}>
            <:loading>
              <div class="revisions-loading">
                <svg class="spinner" viewBox="0 0 24 24" width="24" height="24">
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
              <div class="revisions-error">
                <span>{gettext("Failed to load revisions. Please try again.")}</span>
              </div>
            </:failed>
            <.async_result :let={active_revision} assign={@active_revision}>
              <:loading></:loading>
              <:failed></:failed>
              <div class="current-schema-version">
                {gettext("Current schema version")}: <span class="version">v{@schema_version}</span>
              </div>
              <table class="revisions-table">
                <%= for revision <- revisions do %>
                  <tr
                    id={"revision-line-#{revision.revision}"}
                    class={[
                      "revisions-line",
                      active_revision == revision.revision && "active",
                      revision.schema_version != @schema_version && "outdated"
                    ]}
                    phx-hook="Brando.ConfirmClick"
                    phx-confirm-click-message={
                      if revision.schema_version != @schema_version,
                        do:
                          gettext(
                            "Discrepancy between current schema version and revision's schema version. There might be changes in the schema that will prevent correct loading of the revision. Activate anyway?"
                          ),
                        else: gettext("Are you sure you want to activate this version?")
                    }
                    phx-confirm-click={JS.push("select_revision", value: %{revision: revision.revision}, target: @myself)}
                    phx-click={JS.push("select_revision", target: @myself)}
                  >
                    <td class="fit">
                      #{revision.revision}
                    </td>
                    <td class="fit">
                      <%= if revision.active do %>
                        &#9679;
                      <% end %>
                    </td>
                    <td class="fit">
                      <%= if revision.protected do %>
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16">
                          <path fill="none" d="M0 0h24v24H0z" /><path d="M6 8V7a6 6 0 1 1 12 0v1h2a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1h2zm13 2H5v10h14V10zm-8 5.732a2 2 0 1 1 2 0V18h-2v-2.268zM8 8h8V7a4 4 0 1 0-8 0v1z" />
                        </svg>
                      <% end %>
                    </td>
                    <td class="date fit">
                      {Brando.Utils.Datetime.format_datetime(revision.inserted_at, "%d/%m/%y, %H:%M")}
                    </td>
                    <td class="schema-version fit">
                      <%= if revision.schema_version do %>
                        v{revision.schema_version}
                      <% end %>
                    </td>
                    <td class="user">{revision.creator.name}</td>
                    <td class="activate fit">
                      <CircleDropdown.render id={"revision-dropdown-#{revision.revision}"}>
                        <Button.dropdown
                          confirm={
                            if revision.schema_version != @schema_version,
                              do:
                                gettext(
                                  "Discrepancy between current schema version and revision's schema version. There might be changes in the schema that will prevent correct loading of the revision. Activate anyway?"
                                ),
                              else: gettext("Are you sure you want to activate this version?")
                          }
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
                        <%= if revision.protected do %>
                          <Button.dropdown
                            event={
                              JS.push("unprotect_revision",
                                target: @myself,
                                value: %{value: revision.revision}
                              )
                            }
                            value={revision.revision}
                            loading
                          >
                            {gettext("Unprotect version")}
                          </Button.dropdown>
                        <% else %>
                          <Button.dropdown
                            event={
                              JS.push("protect_revision",
                                target: @myself,
                                value: %{value: revision.revision}
                              )
                            }
                            value={revision.revision}
                            loading
                          >
                            {gettext("Protect version")}
                          </Button.dropdown>
                        <% end %>
                        <%= unless revision.active do %>
                          <Button.dropdown
                            event={
                              JS.push("show_publish_at",
                                target: @myself,
                                value: %{value: revision.revision}
                              )
                            }
                            value={revision.revision}
                            loading
                          >
                            {gettext("Schedule version")}
                          </Button.dropdown>
                        <% end %>
                        <%= if !revision.protected && !revision.active do %>
                          <Button.dropdown
                            confirm={gettext("Are you sure you want to delete this?")}
                            event={
                              JS.push("delete_revision",
                                target: @myself,
                                value: %{value: revision.revision}
                              )
                            }
                            value={revision.revision}
                            loading
                          >
                            {gettext("Delete version")}
                          </Button.dropdown>
                        <% end %>
                      </CircleDropdown.render>
                      <!--
                    <li>
                      <button
                        type="button"
                        @click="$parent.sharePreview(revision)">
                        Share preview
                      </button>
                    </li>
                    <li>
                      <button
                        type="button"
                        @click="openDescribeModal(revision)">
                        Describe revision
                      </button>
                      <KModal
                        v-if="showDescribeModal && revision === modalRevision"
                        :ref="`describeModal${revision.revision}`"
                        v-shortkey="['esc', 'enter']"
                        :ok-text="$t('close')"
                        @shortkey.native="describeRevision(revision)"
                        @ok="describeRevision(revision)">
                        <template #header>
                          {{ $t('describe-revision') }}
                        </template>
                        <KInput
                          v-model="description"
                          name="description"
                          :label="$t('description-label')"
                          :help-text="$t('description-helpText')" />
                      </KModal>
                    </li>
                  </CircleDropdown>
                  -->
                    </td>
                  </tr>
                  <%= if @show_publish_at == revision.revision do %>
                    <tr class={[
                      "revisions-line",
                      active_revision == revision.revision && "active"
                    ]}>
                      <td colspan="4"></td>
                      <td colspan="3" class="revision-publish_at">
                        <div class="field-wrapper">
                          <label>
                            {gettext("Publish at")}
                          </label>
                          <div class="datepicker-and-button">
                            <div
                              id={"revision-#{revision.revision}-datetimepicker"}
                              class="datetime-wrapper"
                              phx-hook="Brando.Scheduler"
                              data-locale={Gettext.get_locale()}
                              data-revision={revision.revision}
                            >
                              <div id={"revision-#{revision.revision}-datetimepicker-flatpickr"} phx-update="ignore">
                                <input type={:hidden} class="flatpickr" />
                              </div>
                            </div>
                            <button type="button">
                              {gettext("Schedule")}
                            </button>
                          </div>
                        </div>
                      </td>
                    </tr>
                  <% end %>
                  <%= if revision.description do %>
                    <tr class={[
                      "revisions-line",
                      active_revision == revision.revision && "active"
                    ]}>
                      <td colspan="4"></td>
                      <td colspan="3" class="revision-description">&uarr; {revision.description}</td>
                    </tr>
                  <% end %>
                <% end %>
              </table>
            </.async_result>
          </.async_result>
        <% end %>
      </Content.drawer>
    </div>
    """
  end

  def handle_event("purge_inactive_revisions", _, %{assigns: %{entry_id: entry_id, form: %{source: changeset}}} = socket) do
    schema = changeset.data.__struct__
    Brando.Revisions.purge_revisions(schema, entry_id)

    {:noreply, refresh_revisions(socket)}
  end

  def handle_event(
        "delete_revision",
        %{"value" => selected_revision_id},
        %{assigns: %{entry_id: entry_id, form: %{source: changeset}}} = socket
      ) do
    schema = changeset.data.__struct__
    Brando.Revisions.delete_revision(schema, entry_id, selected_revision_id)

    {:noreply, refresh_revisions(socket)}
  end

  def handle_event(
        "protect_revision",
        %{"value" => selected_revision_id},
        %{assigns: %{entry_id: entry_id, form: %{source: changeset}}} = socket
      ) do
    schema = changeset.data.__struct__
    Brando.Revisions.protect_revision(schema, entry_id, selected_revision_id, true)

    {:noreply, refresh_revisions(socket)}
  end

  def handle_event(
        "schedule",
        %{"revision" => revision, "publish_at" => publish_at},
        %{assigns: %{current_user: current_user, entry_id: entry_id, form: %{source: changeset}}} = socket
      ) do
    schema = changeset.data.__struct__

    Brando.Publisher.schedule_revision(
      Module.concat([schema]),
      entry_id,
      revision,
      publish_at,
      current_user
    )

    send(self(), {:toast, gettext("Scheduled revision for publishing")})

    {:noreply,
     socket
     |> assign(:show_publish_at, nil)
     |> refresh_revisions()}
  end

  def handle_event("show_publish_at", %{"value" => selected_revision_id}, socket) do
    {:noreply, assign(socket, :show_publish_at, selected_revision_id)}
  end

  def handle_event(
        "unprotect_revision",
        %{"value" => selected_revision_id},
        %{assigns: %{entry_id: entry_id, form: %{source: changeset}}} = socket
      ) do
    schema = changeset.data.__struct__
    Brando.Revisions.protect_revision(schema, entry_id, selected_revision_id, false)

    {:noreply, refresh_revisions(socket)}
  end

  def handle_event("store_revision", _, socket) do
    changeset = socket.assigns.form.source
    current_user = socket.assigns.current_user

    if changeset.errors == [] do
      entry = Ecto.Changeset.apply_changes(changeset)
      {:ok, _revision} = Brando.Revisions.create_revision(entry, current_user, false)

      {:noreply, refresh_revisions(socket)}
    else
      error_title = gettext("Error")

      error_notice =
        gettext("Error while saving form. Please correct marked fields and resubmit")

      {:noreply, push_event(socket, "b:alert", %{title: error_title, message: error_notice, type: "error"})}
    end
  end

  def handle_event("select_revision", %{"revision" => selected_revision_id}, socket) do
    %{entry_id: entry_id, entry_type: entry_type} = socket.assigns
    form_id = socket.assigns.form_id

    {:ok, {_revision, {_revision_id, decoded_entry}}} =
      Brando.Revisions.get_revision(entry_type, entry_id, selected_revision_id)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_entry_hard_reset,
      updated_entry: decoded_entry
    )

    {:noreply, socket}
  end

  def handle_event(
        "activate_revision",
        %{"value" => selected_revision_id},
        %{assigns: %{entry_id: entry_id, form: form, current_user: current_user}} = socket
      ) do
    module = form.source.data.__struct__
    form_id = socket.assigns.form_id

    {:ok, new_entry} =
      Brando.Revisions.set_entry_to_revision(module, entry_id, selected_revision_id, current_user)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_entry_hard_reset,
      updated_entry: new_entry
    )

    {:noreply, refresh_revisions(socket)}
  end
end
