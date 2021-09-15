defmodule BrandoAdmin.Components.Form.RevisionsDrawer do
  use Surface.LiveComponent
  alias BrandoAdmin.Components.CircleDropdown
  alias BrandoAdmin.Components.DropdownButton

  prop form, :form, required: true
  prop current_user, :any, required: true
  prop blueprint, :any, required: true
  prop status, :atom, default: :closed
  prop close, :event

  data revisions, :list
  data active_revision, :any

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_revisions()
     |> assign_active_revision()
     |> assign_form_id()}
  end

  defp assign_form_id(%{assigns: %{form: form}} = socket) do
    module = form.source.data.__struct__
    form_id = "#{module.__naming__.singular}_form"

    assign(socket, :form_id, form_id)
  end

  defp assign_revisions(%{assigns: %{form: form}} = socket) do
    entry_type = form.source.data.__struct__

    case Ecto.Changeset.get_field(form.source, :id) do
      nil ->
        socket
        |> assign(revisions: [], entry_id: nil, entry_type: entry_type)

      entry_id ->
        socket
        |> assign_new(:revisions, fn ->
          list_opts = %{
            filter: %{entry_id: entry_id, entry_type: entry_type},
            preload: [:creator],
            order: [{:desc, :revision}]
          }

          {:ok, revisions} = Brando.Revisions.list_revisions(list_opts)

          revisions
        end)
        |> assign(:entry_id, entry_id)
        |> assign(:entry_type, entry_type)
    end
  end

  defp assign_refreshed_revisions(
         %{assigns: %{entry_id: entry_id, entry_type: entry_type}} = socket
       ) do
    list_opts = %{
      filter: %{entry_id: entry_id, entry_type: entry_type},
      preload: [:creator],
      order: [{:desc, :revision}]
    }

    {:ok, revisions} = Brando.Revisions.list_revisions(list_opts)

    assign(socket, :revisions, revisions)
  end

  defp assign_active_revision(%{assigns: %{revisions: revisions}} = socket) do
    socket
    |> assign_new(:active_revision, fn ->
      case Enum.find(revisions, & &1.active) do
        nil ->
          nil

        %{revision: revision} ->
          revision
      end
    end)
  end

  def render(assigns) do
    ~F"""
    <div class={"drawer", "revisions-drawer", open: @status == :open}>
      {#if @status == :open}
        <div class="inner">
          <div class="drawer-header">
            <h2>
              Entry revisions
            </h2>
            <button
              :on-click={@close}
              type="button"
              class="drawer-close-button">
              Close
            </button>
          </div>
          <div class="drawer-info">
            <p>
              This is a list of this entry's revisions. Click a row to preview.
            </p>
            <p>
              You may also store a new version of the entry without activating it.
              This might be useful for scheduling content publishing,
              or sharing previews of unpublished entries.
            </p>
            <div class="button-group">
              <button
                type="button"
                class="secondary"
                :on-click="store_revision">
                Save version without activating
              </button>

              <button
                type="button"
                class="secondary"
                id={"revisions-drawer-confirm-purge"}
                phx-hook="Brando.ConfirmClick"
                phx-confirm-click-message={"Are you sure you want to purge unprotected and non active revisions of this entry?"}
                phx-confirm-click="purge_inactive_revisions"
                phx-target={@myself}>
                Purge inactive versions
              </button>
            </div>
          </div>
          {#if true}
            <table class="revisions-table">
              {#for revision <- @revisions}
                <tr
                  class={"revisions-line", active: @active_revision == revision.revision}
                  :on-click="select_revision"
                  phx-value-revision={revision.revision}
                  phx-page-loading>
                  <td class="fit">
                    #{revision.revision}
                  </td>
                  <td class="fit">
                    {#if revision.active}
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M12 17l-5.878 3.59 1.598-6.7-5.23-4.48 6.865-.55L12 2.5l2.645 6.36 6.866.55-5.231 4.48 1.598 6.7z"/></svg>
                    {/if}
                  </td>
                  <td class="fit">
                    {#if revision.protected}
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M6 8V7a6 6 0 1 1 12 0v1h2a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1h2zm13 2H5v10h14V10zm-8 5.732a2 2 0 1 1 2 0V18h-2v-2.268zM8 8h8V7a4 4 0 1 0-8 0v1z"/></svg>
                    {/if}
                  </td>
                  <td class="date fit">
                    {Calendar.strftime(revision.inserted_at, "%d/%m/%y")}, {Calendar.strftime(revision.inserted_at, "%H:%M")}
                  </td>
                  <td class="user">{revision.creator.name}</td>
                  <td class="activate fit">
                    <CircleDropdown
                      id={"revision-dropdown-#{revision.revision}"}>
                      <DropdownButton
                        confirm="Are you sure you want to activate this version?"
                        event="activate_revision"
                        value={revision.revision}>
                        Activate revision
                      </DropdownButton>
                      {#if revision.protected}
                        <DropdownButton
                          event="unprotect_revision"
                          value={revision.revision}
                          loading>
                          Unprotect version
                        </DropdownButton>
                      {#else}
                        <DropdownButton
                          event="protect_revision"
                          value={revision.revision}
                          loading>
                          Protect version
                        </DropdownButton>
                      {/if}
                      {#if !revision.protected && !revision.active}
                        <DropdownButton
                          confirm="Are you sure you want to delete this?"
                          event="delete_revision"
                          value={revision.revision}
                          loading>
                          Delete version
                        </DropdownButton>
                      {/if}
                    </CircleDropdown>
                    {!--
                    <CircleDropdown>
                      <li v-if="!revision.active">
                        <button
                          type="button"
                          @click="openPublishModal(revision)">
                          {{ $t('schedule-revision') }}
                        </button>
                        <KModal
                          v-if="showPublishModal && revision === modalRevision"
                          :ref="`publishModal${revision.revision}`"
                          v-shortkey="['esc', 'enter']"
                          :ok-text="$t('close')"
                          @shortkey.native="schedulePublishing(revision)"
                          @ok="schedulePublishing(revision)">
                          <template #header>
                            {{ $t('schedule-revision') }}
                          </template>
                          <KInputDatetime
                            v-model="publishAt"
                            name="publishAt"
                            :label="$t('publishAt-label')"
                            :help-text="$t('publishAt-helpText')" />
                        </KModal>
                      </li>
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
                    --}
                  </td>
                </tr>
                {#if revision.description}
                  <tr
                    :key="`${revision.entryName}_${revision.entryId}_${revision.revision}_description`"
                    :class="{ active: $parent.activeRevision.revision === revision.revision }"
                    class="revisions-line">
                    <td colspan="3"></td>
                    <td colspan="3" class="revision-description">&uarr; {revision.description}</td>
                  </tr>
                {/if}
              {/for}
            </table>
          {/if}
        </div>
      {/if}
    </div>
    """
  end

  def handle_event(
        "purge_inactive_revisions",
        _,
        %{assigns: %{entry_id: entry_id, form: %{source: changeset}}} = socket
      ) do
    schema = changeset.data.__struct__
    Brando.Revisions.purge_revisions(schema, entry_id)

    {:noreply,
     socket
     |> assign_refreshed_revisions()}
  end

  def handle_event(
        "delete_revision",
        %{"value" => selected_revision_id},
        %{assigns: %{entry_id: entry_id, form: %{source: changeset}}} = socket
      ) do
    schema = changeset.data.__struct__
    Brando.Revisions.delete_revision(schema, entry_id, selected_revision_id)

    {:noreply,
     socket
     |> assign_refreshed_revisions()}
  end

  def handle_event(
        "protect_revision",
        %{"value" => selected_revision_id},
        %{assigns: %{entry_id: entry_id, form: %{source: changeset}}} = socket
      ) do
    schema = changeset.data.__struct__
    Brando.Revisions.protect_revision(schema, entry_id, selected_revision_id, true)

    {:noreply,
     socket
     |> assign_refreshed_revisions()}
  end

  def handle_event(
        "unprotect_revision",
        %{"value" => selected_revision_id},
        %{assigns: %{entry_id: entry_id, form: %{source: changeset}}} = socket
      ) do
    schema = changeset.data.__struct__
    Brando.Revisions.protect_revision(schema, entry_id, selected_revision_id, false)

    {:noreply,
     socket
     |> assign_refreshed_revisions()}
  end

  def handle_event(
        "store_revision",
        _,
        %{assigns: %{form: %{source: changeset}, current_user: current_user}} = socket
      ) do
    entry = Ecto.Changeset.apply_changes(changeset)
    {:ok, revision} = Brando.Revisions.create_revision(entry, current_user, false)

    {:noreply,
     socket
     |> assign_refreshed_revisions()
     |> assign(:active_revision, revision.revision)}
  end

  def handle_event(
        "select_revision",
        %{"revision" => selected_revision_id},
        %{assigns: %{entry_id: entry_id, entry_type: entry_type, form_id: form_id}} = socket
      ) do
    {:ok, {_revision, {revision_id, decoded_entry}}} =
      Brando.Revisions.get_revision(entry_type, entry_id, selected_revision_id)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_entry: decoded_entry
    )

    {:noreply, assign(socket, :active_revision, revision_id)}
  end

  def handle_event(
        "activate_revision",
        %{"value" => selected_revision_id},
        %{
          assigns: %{entry_id: entry_id, form: form, form_id: form_id, current_user: current_user}
        } = socket
      ) do
    module = form.source.data.__struct__

    {:ok, new_entry} =
      Brando.Revisions.set_entry_to_revision(module, entry_id, selected_revision_id, current_user)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_entry: new_entry
    )

    {:noreply,
     socket
     |> assign(:active_revision, String.to_integer(selected_revision_id))
     |> assign_refreshed_revisions()}
  end
end
