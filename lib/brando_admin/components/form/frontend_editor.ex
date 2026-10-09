defmodule BrandoAdmin.Components.Form.FrontendEditor do
  @moduledoc """
  The entry form in frontend edit mode: one block or one field of the entry,
  edited from a sidebar on the published page
  (`BrandoAdmin.FrontendEdit.EditorLive`).

  The form keeps all of its machinery — the block field's op store, media
  pickers and drawers, multi-user block sync, saving through the entry's
  context — and only changes what it shows and where previews go:

    * only the block field holding the selected block is shown, and in it only
      the root holding it, narrowed down to the block (see `focus/2`);
    * the entry's own fields are not shown and not submitted, so a save
      writes the block changes alone — or, for a field (`frontend_edit.input`),
      only that field's input is shown and submitted;
    * preview HTML goes to the page in the parent window, through the
      editor's LiveView (`{:frontend_edit, message}`), not to a live-preview
      session;
    * drafts and pending translations are not opened here; they belong to
      the full editor.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  import Ecto.Changeset, only: [apply_changes: 1, get_assoc: 2]

  alias BrandoAdmin.Components.FilePicker
  alias BrandoAdmin.Components.Form.BlockField
  alias BrandoAdmin.Components.Form.EntrySkeleton
  alias BrandoAdmin.Components.Form.Fieldset
  alias BrandoAdmin.Components.Form.FileDrawer
  alias BrandoAdmin.Components.Form.ImageDrawer
  alias BrandoAdmin.Components.Form.Input.Blocks.TipTapLinkDialog
  alias BrandoAdmin.Components.Form.Primitives
  alias BrandoAdmin.Components.Form.Translation
  alias BrandoAdmin.Components.Form.VideoDrawer
  alias BrandoAdmin.Components.ImagePicker
  alias BrandoAdmin.Components.VideoPicker

  @doc false
  # Once, on the first update with a `frontend_edit` focus.
  def init(%{assigns: %{frontend_edit: %{}, frontend_edit_ready?: true}} = socket), do: socket

  def init(%{assigns: %{frontend_edit: %{}}} = socket) do
    socket
    # Blocks render their preview HTML only while a preview is open.
    |> assign(:live_preview_active?, true)
    |> assign(:live_preview_cache_key, "frontend-edit:" <> socket.assigns.id)
    |> assign(:save_redirect_target, :self)
    |> assign(:frontend_edit_ready?, true)
  end

  def init(socket), do: socket

  @doc """
  Runs `fun` on the socket outside frontend edit mode and returns the socket
  untouched inside it, for form setup that belongs to the full editor only.
  """
  def unless_frontend(%{assigns: %{frontend_edit: %{}}} = socket, _fun), do: socket
  def unless_frontend(socket, fun), do: fun.(socket)

  @doc "Whether the form is in frontend edit mode."
  def frontend?(%{assigns: %{frontend_edit: %{}}}), do: true
  def frontend?(_), do: false

  @doc "Where the form goes after a save: nowhere, in frontend edit mode."
  def save_target(%{assigns: %{frontend_edit: %{}}}), do: :self
  def save_target(_socket), do: :listing

  @doc "A block's new preview HTML, for the page to patch in place."
  def update_block(payload), do: notify({:update_block, payload})

  @doc """
  Renders each block field from the collected changeset, as the page shows
  it in edit mode, for changes a single block cannot be patched with.
  """
  def replace_fields(socket, changeset, mode) do
    %{schema: schema, block_map: block_map} = socket.assigns
    id = Ecto.Changeset.get_field(changeset, :id)

    block_fields =
      Enum.flat_map(block_map, fn {name, _, _, _} ->
        [name, :"entry_#{name}", :"rendered_#{name}", :"rendered_#{name}_at"]
      end)

    entry = changeset |> apply_changes() |> Map.drop(block_fields)

    for {name, _block_module, _entry_blocks, _opts} <- block_map do
      # In edit mode, as the page was rendered: embedded fragments keep their
      # own markers. Nothing rendered here is stored.
      html =
        Brando.FrontendEdit.with_active(fn ->
          changeset
          |> get_assoc(:"entry_#{name}")
          |> Brando.Utils.apply_changes_recursively()
          |> Brando.Villain.parse(entry, annotate_blocks: true)
          |> IO.iodata_to_binary()
        end)

      key = Brando.FrontendEdit.field_key(schema, id, name)
      notify({:replace_field, %{key: key, html: html, media: mode == :live_preview_reload}})
    end

    :ok
  end

  @doc """
  An entry field changed in the form. In field mode the page shows the new
  value at once; blocks reading the field follow with the next preview
  render (`replace_fields/3`).
  """
  def field_changed(%{assigns: %{frontend_edit: %{input: field} = frontend_edit}} = socket) when not is_nil(field) do
    entry = Ecto.Changeset.apply_changes(socket.assigns.form.source)
    notify(:dirty)

    notify(
      {:entry_field,
       %{key: frontend_edit.target, html: IO.iodata_to_binary(Brando.FrontendEdit.Fields.render_value(entry, field))}}
    )
  end

  def field_changed(%{assigns: %{frontend_edit: %{}}}), do: notify(:dirty)
  def field_changed(_socket), do: :ok

  @doc "Tells the editor's LiveView a save has started. Returns the socket."
  def saving(socket), do: tap(socket, fn _ -> notify(:saving) end)

  @doc "Tells the editor's LiveView the save of `entry` succeeded. Returns the socket."
  def saved(socket, entry), do: tap(socket, fn _ -> notify({:saved, entry}) end)

  @doc "Tells the editor's LiveView the save failed with `reason`. Returns the socket."
  def save_failed(socket, reason), do: tap(socket, fn _ -> notify({:save_failed, reason}) end)

  defp notify(message), do: send(self(), {:frontend_edit, message})

  @doc """
  The focus a block field renders with: the selected root, its ancestors
  down to the selected block, and the block. Other block fields of the entry
  get an empty focus — they stay mounted, as saving collects every field.
  """
  def focus(%{field: field} = frontend_edit, field) when not is_nil(field),
    do: %{target: frontend_edit.target, root: frontend_edit.root, path: frontend_edit.path}

  def focus(_frontend_edit, _field), do: %{target: nil, root: nil, path: []}

  defp input(form_blueprint, field), do: Brando.Blueprint.Forms.get_field(field, form_blueprint)

  def render(assigns) do
    ~H"""
    <div class="frontend-edit-form-wrapper">
      <div
        id={"#{@id}-el"}
        class="brando-form frontend-edit-form"
        phx-hook="Brando.Form"
        data-deliver-topic={@deliver_topic}
        data-entry-id={@entry_id}
      >
        <span id={"#{@id}-draft-capture"} data-draft-capture phx-target={@myself} hidden></span>
        <span id={"#{@id}-save-source"} data-save-source phx-target={@myself} hidden></span>
        <div class="form-content">
          <.live_component module={FilePicker} id="file-picker" />
          <.live_component module={ImagePicker} id="image-picker" upload_in_form? />
          <.live_component module={VideoPicker} id="video-picker" current_user={@current_user} />
          <.live_component module={TipTapLinkDialog} id="tiptap-link-dialog" />

          <FileDrawer.render
            file_changeset={@file_changeset}
            myself={@myself}
            schema={@schema}
            edit_file={@edit_file}
            processing={@processing}
          />

          <ImageDrawer.render
            image_changeset={@image_changeset}
            myself={@myself}
            schema={@schema}
            edit_image={@edit_image}
            processing={@processing}
          />

          <ImageDrawer.editor edit_image={@edit_image} myself={@myself} />

          <VideoDrawer.render
            video_changeset={@video_changeset}
            myself={@myself}
            schema={@schema}
            edit_video={@edit_video}
            video_context={@video_context}
          />

          <form
            id={"#{@id}-drawer-recovery"}
            phx-change="noop"
            phx-auto-recover="recover_drawer_state"
            phx-target={@myself}
            class="hidden"
          >
            <input type="hidden" name="drawer[type]" value={@editing_drawer_type} />
            <input type="hidden" name="drawer[resource_id]" value={@editing_resource_id} />
            <input type="hidden" name="drawer[field]" value={@editing_field} />
            <input type="hidden" name="drawer[path]" value={Jason.encode!(@editing_path || [])} />
            <input type="hidden" name="drawer[schema]" value={@editing_schema} />
            <input type="hidden" name="drawer[form_id]" value={@id} />
            <input type="hidden" name="drawer[changes]" value={@editing_drawer_changes} />
          </form>

          <%!-- The entry's own fields are edited in the full editor. The form
                is still submitted, as saving runs through it, but with no
                fields in it the save changes only the blocks. --%>
          <.form
            id={"#{@id}_form"}
            class="main-form"
            for={@form}
            phx-target={@myself}
            phx-submit="save"
            data-save-event="save_form"
            phx-change="validate"
            phx-auto-recover="recover_form"
          >
            <input type="hidden" name={"#{@form.name}[#{:__force_change}]"} phx-debounce="0" />
            <div style="display:none">
              <.live_file_input upload={@uploads[:image_editor_upload]} />
            </div>
            <%!-- Field mode: the one input, as the admin form renders it. --%>
            <Fieldset.render
              :if={@frontend_edit[:input]}
              id={"#{@id}-frontend-field"}
              relations={Brando.Blueprint.Relations.__relations__(@schema)}
              form={@form}
              fieldset={%Brando.Blueprint.Forms.Fieldset{fields: [input(@form_blueprint, @frontend_edit.input)]}}
              current_user={@current_user}
              form_cid={@myself}
              form_id={@id}
            />
          </.form>

          <%!-- A heavy entry's blocks load after the form (`Form.open_entry/1`) --%>
          <div :if={@has_blocks? && !@blocks_ready?} class="frontend-edit-loading">
            <EntrySkeleton.load_state label={
              EntrySkeleton.loading_blocks_label(@block_counts |> Map.values() |> Enum.sum())
            } />
            <EntrySkeleton.blocks count={2} label?={false} />
          </div>
          <.live_component
            :for={{block_field, block_module, entry_blocks, field_opts} <- (@blocks_ready? && @block_map) || []}
            :if={@has_blocks?}
            :key={block_field}
            module={BlockField}
            block_module={block_module}
            block_field={block_field}
            form_name={@form.name}
            opts={field_opts}
            hidden={false}
            focus={focus(@frontend_edit, block_field)}
            id={"#{@id}-blocks-#{block_field}"}
            entry={@entry_for_blocks}
            entry_blocks={entry_blocks}
            templates={[]}
            current_user={@current_user}
            form_id={@id}
            live_preview_active?={@live_preview_active?}
            live_preview_cache_key={@live_preview_cache_key}
            source_locked={Translation.locked?(@translation)}
            source_url={Translation.source_url(@translation)}
          />
        </div>

        <footer class="frontend-edit-actions">
          <p class="frontend-edit-status" role="status" aria-live="polite">
            <%= cond do %>
              <% @processing -> %>
                {gettext("Saving…")}
              <% @frontend_status[:dirty?] -> %>
                <span class="frontend-edit-status-dot is-dirty" aria-hidden="true"></span>{gettext("Unsaved changes")}
              <% @frontend_status[:saved?] -> %>
                <.icon name="circle-check" />{gettext("Saved")}
              <% true -> %>
                {gettext("Changes show on the page as you type")}
            <% end %>
          </p>
          <Primitives.submit_button
            processing={@processing}
            form_id={@id}
            label={gettext("Save")}
            shortcut={%{key: "S"}}
            icon="check"
            class="primary submit-button"
          />
        </footer>
      </div>
    </div>
    """
  end
end
