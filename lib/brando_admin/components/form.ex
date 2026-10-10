defmodule BrandoAdmin.Components.Form do
  @moduledoc """
  Form component for BrandoAdmin

  This component is used to render forms in BrandoAdmin, and is the heart of the admin interface.

  ## Flow

  ### Entry fields

  When changing form fields for an entry that has a block field, we will signal to update
  each block's liquex splits and also the live preview.

  In the form's "change" event, we extract the "target" and if there are blocks that want
  entry updates, we will send a message to the blocks with the "path" to the field and
  its new value to update their liquex splits and live preview.

  If we change entry fields that are assocs, for instance image fields, file fields, selects
  and multi selects, we will signal to update the entry relation from the live component.

  ### Block variables


  """
  use BrandoAdmin, :live_component
  use BrandoAdmin.Translator

  use Gettext, backend: Brando.Gettext

  import Ecto.Changeset
  import Phoenix.LiveView.TagEngine

  require Logger

  alias Brando.AI.FieldAction
  alias Brando.Blueprint.Callback
  alias Brando.Blueprint.Forms, as: BlueprintForms
  alias Brando.Content.Blocks
  alias Brando.EditSession
  alias Brando.Images
  alias Brando.LivePreview
  alias Brando.Villain
  alias BrandoAdmin.Components.Button
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.FilePicker
  alias BrandoAdmin.Components.Form.AlternatesDrawer
  alias BrandoAdmin.Components.Form.AltTextSuggestion
  alias BrandoAdmin.Components.Form.BlockField
  alias BrandoAdmin.Components.Form.DraftRecoveryComponent
  alias BrandoAdmin.Components.Form.Drafts
  alias BrandoAdmin.Components.Form.EntryHeader
  alias BrandoAdmin.Components.Form.EntrySkeleton
  alias BrandoAdmin.Components.Form.FieldActions
  alias BrandoAdmin.Components.Form.Fieldset
  alias BrandoAdmin.Components.Form.FileDrawer
  alias BrandoAdmin.Components.Form.FrontendEditor
  alias BrandoAdmin.Components.Form.ImageDrawer
  alias BrandoAdmin.Components.Form.Input.Blocks.TipTapLinkDialog
  alias BrandoAdmin.Components.Form.Input.MultiSelect
  alias BrandoAdmin.Components.Form.Input.Select
  alias BrandoAdmin.Components.Form.Input.SubformHelpers
  alias BrandoAdmin.Components.Form.MetaDrawer
  alias BrandoAdmin.Components.Form.NotesDrawer
  alias BrandoAdmin.Components.Form.Preview
  alias BrandoAdmin.Components.Form.Primitives
  alias BrandoAdmin.Components.Form.RevisionsDrawer
  alias BrandoAdmin.Components.Form.RichTextAI
  alias BrandoAdmin.Components.Form.ScheduledPublishingDrawer
  alias BrandoAdmin.Components.Form.Translation
  alias BrandoAdmin.Components.Form.VideoDrawer
  alias BrandoAdmin.Components.Form.Visibility
  alias BrandoAdmin.Components.ImagePicker
  alias BrandoAdmin.Components.SplitDropdown
  alias BrandoAdmin.Components.VideoPicker
  alias Ecto.Changeset

  def mount(socket) do
    # Per-form-INSTANCE topic for asset delivery from the sticky UploadManager
    # (docs/UPLOADER.md §6.3). A UUID — not schema:id — so create forms (no id
    # yet) work and two tabs editing the same entry don't share a topic.
    deliver_topic = "form:" <> Ecto.UUID.generate()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:modules")
      Phoenix.PubSub.subscribe(Brando.pubsub(), deliver_topic)

      # Pairs with the UploadManager's "delivering asset ## to <topic>" line.
      # Because this is minted per MOUNT, a form that remounts mid-upload starts
      # listening on a NEW topic while the in-flight item still carries the old
      # one — and the mismatch was previously invisible. See D2 in
      # `.claude/plans/form-audit/plan.md`.
      Logger.info("==> Form: listening for asset delivery on #{topic_ref(deliver_topic)}")
    end

    # TODO: maybe check oban queue for :processing_images?
    {:ok,
     socket
     |> assign(:edit_image, %{path: [], field: nil, relation_field: nil})
     |> assign(:edit_file, %{path: [], field: nil, relation_field: nil})
     |> assign(:edit_video, %{path: [], field: nil, relation_field: nil})
     |> assign(:updated_entry_assocs, %{})
     |> assign(:file_changeset, nil)
     |> assign(:image_changeset, nil)
     |> assign(:video_changeset, nil)
     |> assign(:initial_update, true)
     |> assign(:tiptap_epoch, Ecto.UUID.generate())
     |> assign(:entry_loading?, false)
     |> assign(:blocks_ready?, true)
     |> assign(:block_counts, %{})
     |> assign(:dirty_fields, [])
     |> assign(:synced_values, %{})
     |> assign(:unshipped_fields, MapSet.new())
     |> assign(:replaced_values, %{})
     |> assign(:held_remote, %{})
     |> assign(:field_clocks, %{})
     |> assign(:blocks_detached?, false)
     |> assign(:hidden_block_fields, [])
     |> assign(:server_owned_assets, %{})
     |> assign(:draft, nil)
     |> assign(:draft_enabled?, false)
     |> assign(:draft_seed, nil)
     |> assign(:translation, nil)
     |> assign(:minor_save?, false)
     |> assign(:draft_save_checked?, false)
     |> assign(:editing_image?, false)
     |> assign(:editing_file?, false)
     |> assign(:editing_video?, false)
     |> assign(:video_context, :asset)
     |> assign(:processing_images, [])
     |> assign(:presences, %{})
     |> assign(:notes_open_count, 0)
     |> assign(:has_meta?, false)
     |> assign(:status_revisions, :closed)
     |> assign(:processing, false)
     |> assign(:save_redirect_target, :listing)
     |> assign(:pending_permalink_redirect, nil)
     |> assign(:permalink_redirect_error, nil)
     |> assign(:live_preview_target, "desktop")
     |> assign(:live_preview_schema_target, nil)
     |> assign(:pending_live_preview_target, nil)
     |> assign(:live_preview_menu_open?, false)
     |> assign(:sharing_preview?, false)
     |> assign(:live_preview_ready?, false)
     |> assign(:live_preview_active?, false)
     |> assign(:live_preview_cache_key, nil)
     |> assign(:preview_update, nil)
     |> assign(:blocks_wanting_entry, %{})
     |> assign(:blocks_ready_for_sharing, false)
     |> assign(:fields_demanding_full_live_preview_rerender, [])
     |> assign(:fields_demanding_live_preview_reassign, [])
     |> assign_new(:footer, fn -> [] end)
     |> assign(:editing_drawer_type, nil)
     |> assign(:editing_resource_id, nil)
     |> assign(:editing_field, nil)
     |> assign(:editing_path, [])
     |> assign(:editing_schema, nil)
     |> assign(:editing_drawer_changes, "{}")
     |> assign(:deliver_topic, deliver_topic)}
  end

  # Ship field changes — triggered by child components (e.g. multi-select on close)
  def update(%{event: "draft_dirty"}, socket), do: {:ok, Drafts.dirty(socket)}

  # A picture block's "Suggest alt text": the block doesn't know the entry's
  # language, the form does. The text goes back to the block, which keeps it
  # as this use's alt text (saved with the entry).
  def update(%{event: "suggest_ref_alt_text", image_id: image_id, reply_to: reply_to}, socket) do
    language =
      case socket.assigns[:entry] do
        %{language: language} when not is_nil(language) -> to_string(language)
        _ -> to_string(Brando.config(:default_language))
      end

    describe = AltTextSuggestion.describe_task(image_id, languages: [language])
    {:ok, start_async(socket, {:suggest_ref_alt_text, reply_to, image_id}, fn -> {language, describe.()} end)}
  end

  def update(%{event: event, field: field} = message, socket)
      when event in ["inspect_field_notes", "field_note_action"] do
    case Brando.Blueprint.Forms.Footnotes.field(socket.assigns.schema, field) do
      nil ->
        :ok

      config ->
        input = socket.assigns.form[config.field]

        send_update(
          BlockField,
          message
          |> Map.put(:id, "#{socket.assigns.id}-blocks-#{config.blocks}")
          |> Map.put(:field, config.field)
          |> Map.put(:html, input.value)
          |> Map.put(:input_id, "#{input.id}-rich-text")
        )
    end

    {:ok, socket}
  end

  # An editor accepted the suggestion of an AI action on `field`
  # (`FieldActions`): it goes into the field as unsaved input.
  # Not on a read-only or disabled field, and not over a value that changed
  # since the action ran (another editor's, say) unless the editor said to
  # replace it.
  def update(%{event: "accept_field_action", field_name: name, field: field, text: text} = message, socket) do
    with {[_ | _], type, opts} <- field_ai_actions(socket, field),
         false <- FieldActions.locked?(opts, socket.assigns.current_user),
         {:ok, path, key, string_path} <- parse_form_field_name(name, socket.assigns.singular) do
      panel = field_action_panel(socket, field, message[:panel])

      if message[:replace] || get_field(socket.assigns.form.source, field) == message[:original] do
        send_update(FieldActions, id: panel, accept_result: :written)
        value = FieldAction.field_value(text, type)
        {:ok, write_ai_text(socket, path, key, string_path, field, value)}
      else
        send_update(FieldActions, id: panel, accept_result: :conflict)
        {:ok, socket}
      end
    else
      _ -> {:ok, socket}
    end
  end

  # Alt text suggested by AI and accepted under its field
  # (`AltTextSuggestion`): it joins the alt text there, as unsaved input.
  # Only for the image the suggestion describes, and not over a language
  # written in since (`AltTextSuggestion.merge/3`).
  def update(%{event: "accept_alt_suggestion", scope: "suggest_entry_alt_text", image_id: id} = message, socket) do
    case socket.assigns[:entry] do
      %Images.Image{id: ^id} when not is_nil(id) ->
        changeset = socket.assigns.form.source
        alt = AltTextSuggestion.merge(Changeset.get_field(changeset, :alt), message.values, message[:original])
        {:ok, put_written_form(socket, to_form(put_change(changeset, :alt, alt), []))}

      _ ->
        {:ok, socket}
    end
  end

  def update(%{event: "accept_alt_suggestion", scope: "suggest_alt_text", image_id: id} = message, socket) do
    case {socket.assigns[:edit_image], socket.assigns[:image_changeset]} do
      {%{image: %{id: ^id}}, %Changeset{} = changeset} when not is_nil(id) ->
        alt = AltTextSuggestion.merge(Changeset.get_field(changeset, :alt), message.values, message[:original])
        {:ok, assign(socket, :image_changeset, Changeset.put_change(changeset, :alt, alt))}

      _ ->
        {:ok, socket}
    end
  end

  def update(%{event: "draft_part", capture_id: id, kind: kind, field: field, data: data}, socket),
    do: {:ok, Drafts.part(socket, id, kind, field, data)}

  def update(%{event: "draft_timeout", capture_id: id}, socket), do: {:ok, Drafts.timeout(socket, id)}

  # Another editor's tab opened the entry, or reconnected (`:editor_joined`
  # in LiveView.Form): what we changed goes to everyone as usual, and the
  # joining tab also gets the unsaved values we hold.
  def update(%{event: "ship_field_changes", to: tab}, socket) do
    {:ok, socket |> ship_all_field_changes() |> ship_fields_to(tab)}
  end

  def update(%{event: "ship_field_changes"}, socket) do
    {:ok, ship_all_field_changes(socket)}
  end

  # A module was saved (`brando:modules`, routed by LiveView.Form.Hooks):
  # the blocks using it take the settings that change their editor, such as
  # Write with AI, without remounting.
  def update(%{event: "module_updated", module_id: module_id}, socket) do
    for %{name: field} <- socket.assigns.form_blueprint.blocks do
      send_update(BlockField, id: "#{socket.assigns.id}-blocks-#{field}", event: "module_updated", module_id: module_id)
    end

    {:ok, socket}
  end

  # Re-broadcast our focused field for a late joiner — field presence
  # indicators are event-driven, so a joiner would otherwise not see the
  # field we're editing as locked (triggered from the :editor_joined
  # handler in LiveView.Form alongside ship_field_changes)
  # An image, video or file field opened its drawer (see `focus_field/2`).
  def update(%{event: "focus_field", field: field}, socket), do: {:ok, focus_field(socket, field)}

  def update(%{event: "reship_active_field"}, socket) do
    entry = socket.assigns[:entry]
    field = socket.assigns[:focused_field]

    if field && entry && entry.id, do: broadcast_active_field(socket, field)

    {:ok, socket}
  end

  # Field changes another editor shipped: the fields they changed. A change
  # to the field we are in waits until we leave it (see "Entry field sync").
  def update(%{event: "apply_remote_field_changes", changes: changes} = message, socket) do
    {:ok, socket |> receive_field_changes(changes) |> merge_clocks(message[:clocks])}
  end

  def update(%{action: :image_processed, image_id: id}, socket) do
    {:ok, update(socket, :processing_images, &Enum.reject(&1, fn proc_id -> proc_id == id end))}
  end

  # edit_file
  def update(
        %{action: :update_edit_file, file: file},
        %{assigns: %{edit_file: edit_file}} = socket
      ) do
    updated_edit_file = Map.merge(edit_file, %{file: file, id: file.id})
    file_changeset = change(file)

    {:ok,
     socket
     |> assign(:edit_file, updated_edit_file)
     |> assign(:file_changeset, file_changeset)
     |> commit_selected_asset(updated_edit_file, file)
     |> assign_drawer_recovery_state()}
  end

  def update(%{action: :update_edit_file, edit_file: %{file: nil} = edit_file}, socket) do
    file_changeset = change(%Brando.Files.File{})

    {:ok,
     socket
     |> assign(:edit_file, edit_file)
     |> assign(:editing_file?, true)
     |> assign(:file_changeset, file_changeset)
     |> assign_drawer_recovery_state()}
  end

  def update(%{action: :update_edit_file, edit_file: %{file: file} = edit_file}, socket) do
    file_changeset = change(file)

    {:ok,
     socket
     |> assign(:edit_file, edit_file)
     |> assign(:editing_file?, true)
     |> assign(:file_changeset, file_changeset)
     |> assign_drawer_recovery_state()}
  end

  # edit_image
  def update(
        %{action: :update_edit_image, image: image},
        %{assigns: %{edit_image: edit_image}} = socket
      ) do
    updated_edit_image = Map.merge(edit_image, %{image: image, id: image.id})
    image_changeset = change(image)

    {:ok,
     socket
     |> assign(:edit_image, updated_edit_image)
     |> assign(:image_changeset, image_changeset)
     |> commit_selected_asset(updated_edit_image, image)
     |> assign_drawer_recovery_state()}
  end

  def update(
        %{action: :update_edit_image, edit_image: %{image: nil} = edit_image},
        socket
      ) do
    image_changeset = change(%Images.Image{})

    {:ok,
     socket
     |> assign(:edit_image, edit_image)
     |> assign(:editing_image?, true)
     |> assign(:image_changeset, image_changeset)
     |> assign_drawer_recovery_state()}
  end

  def update(%{action: :update_edit_image, edit_image: %{image: image} = edit_image}, socket) do
    image_changeset = change(image)

    {:ok,
     socket
     |> assign(:edit_image, edit_image)
     |> assign(:editing_image?, true)
     |> assign(:image_changeset, image_changeset)
     |> assign_drawer_recovery_state()}
  end

  def update(
        %{action: :open_image_editor_from_picker, image: image},
        %{assigns: %{edit_image: edit_image}} = socket
      ) do
    updated_edit_image = Map.merge(edit_image, %{image: image, id: image.id})
    image_changeset = change(image)

    {:ok,
     socket
     |> assign(:edit_image, updated_edit_image)
     |> assign(:editing_image?, true)
     |> assign(:image_changeset, image_changeset)
     |> assign_drawer_recovery_state()
     |> push_event("b:image_editor:init", image_editor_payload(image))}
  end

  # Set edit_image for the save handler when image editor is opened from a block.
  # The block's handle_event pushes b:image_editor:init directly (same render cycle).
  def update(%{action: :set_edit_image_from_block, image: image} = params, socket) do
    {:ok,
     assign(socket, :edit_image, %{
       path: [],
       field: nil,
       relation_field: nil,
       image: image,
       block_target: params[:block_target],
       old_image_id: params[:old_image_id]
     })}
  end

  # edit_video
  def update(
        %{action: :update_edit_video, video: video},
        %{assigns: %{edit_video: edit_video}} = socket
      ) do
    updated_edit_video = Map.merge(edit_video, %{video: video, id: video.id})
    video_changeset = change(video)

    {:ok,
     socket
     |> assign(:edit_video, updated_edit_video)
     |> assign(:video_changeset, video_changeset)
     |> commit_selected_asset(updated_edit_video, video)
     |> assign_drawer_recovery_state()}
  end

  def update(
        %{action: :update_edit_video, edit_video: %{video: nil} = edit_video},
        socket
      ) do
    video_changeset = change(%Brando.Videos.Video{})

    {:ok,
     socket
     |> assign(:edit_video, edit_video)
     |> assign(:editing_video?, true)
     |> assign(:video_changeset, video_changeset)
     |> assign_drawer_recovery_state()}
  end

  def update(%{action: :update_edit_video, edit_video: %{video: video} = edit_video}, socket) do
    video_changeset = change(video)

    {:ok,
     socket
     |> assign(:edit_video, edit_video)
     |> assign(:editing_video?, true)
     |> assign(:video_changeset, video_changeset)
     |> assign_drawer_recovery_state()}
  end

  # Open video drawer with context awareness
  def update(
        %{action: :open_video_drawer, video_context: context, edit_video: edit_video},
        socket
      ) do
    video_changeset =
      if edit_video.video do
        # Apply defaults if this is a new video for :asset context
        video_with_defaults =
          if context == :asset && edit_video.defaults && edit_video.defaults != %{} &&
               is_nil(edit_video.video.id) do
            Map.merge(edit_video.video, edit_video.defaults)
          else
            edit_video.video
          end

        change(video_with_defaults)
      else
        # Create new video with defaults if provided
        new_video =
          if context == :asset && edit_video.defaults && edit_video.defaults != %{} do
            struct(%Brando.Videos.Video{}, edit_video.defaults)
          else
            %Brando.Videos.Video{}
          end

        change(new_video)
      end

    {:ok,
     socket
     |> assign(:video_context, context)
     |> assign(:edit_video, edit_video)
     |> assign(:editing_video?, true)
     |> assign(:video_changeset, video_changeset)
     |> assign_drawer_recovery_state()}
  end

  # Video upload actions - generic, works with any upload strategy
  def update(
        %{
          action: :get_video_upload_url,
          upload_request: %{
            "request_ref" => request_ref,
            "filename" => filename,
            "size" => size,
            "mime_type" => mime_type
          }
        },
        socket
      ) do
    edit_video = socket.assigns.edit_video

    case video_config_target(edit_video, socket.assigns.schema) do
      nil ->
        Logger.error("Failed to build video config target for #{inspect(edit_video[:field])}")

        {:ok,
         push_event(socket, "video_upload_url_error", %{
           error: gettext("Invalid video upload target"),
           filename: filename,
           request_ref: request_ref
         })}

      config_target ->
        start_provider_video_upload(socket, config_target, %{
          filename: filename,
          size: size,
          mime_type: mime_type,
          request_ref: request_ref
        })
    end
  end

  def update(%{action: :get_video_upload_url, upload_request: params}, socket) do
    {:ok,
     push_event(socket, "video_upload_url_error", %{
       error: "Invalid video upload request",
       filename: Map.get(params, "filename", ""),
       request_ref: Map.get(params, "request_ref", "")
     })}
  end

  def update(%{action: :video_upload_complete, video_id: video_id}, socket) do
    # Video uploaded, webhook will update status
    # Reload video to get latest data
    case Brando.Videos.get_video(%{matches: %{id: video_id}, preload: [:thumbnail]}) do
      {:ok, video} ->
        {:ok, video} = Brando.Videos.Uploader.complete_client_upload(video)
        edit_video = Map.put(socket.assigns.edit_video, :video, video)
        video_changeset = change(video)
        relation_key = String.to_existing_atom("#{socket.assigns.edit_video.field}_id")

        {:ok,
         socket
         |> update_changeset(relation_key, video.id)
         |> assign(:edit_video, edit_video)
         |> assign(:video_changeset, video_changeset)}

      {:error, _} ->
        {:ok, socket}
    end
  end

  def update(
        %{action: :video_upload_progress, video_id: _video_id, percentage: percentage},
        socket
      ) do
    # Update processing indicator
    {:ok, assign(socket, :processing, percentage)}
  end

  def update(%{action: :video_upload_error, error: error} = assigns, socket) do
    require Logger
    Logger.error("==> video upload failed for #{inspect(assigns[:filename])}: #{inspect(error)}")

    send(self(), {:toast, gettext("Video upload failed: %{error}", error: error)})

    {:ok, assign(socket, :processing, false)}
  end

  def update(
        %{event: "update_live_preview_block"},
        %{assigns: %{live_preview_cache_key: nil}} = socket
      ) do
    {:ok, socket}
  end

  def update(
        %{event: "update_live_preview_block"},
        %{assigns: %{preview_update: %{} = pending}} = socket
      ) do
    # An incremental edit may have landed after a field supplied its snapshot.
    # Recollect that generation; a still-scheduled batch will read it normally.
    {:ok, Preview.queue(socket, pending.mode, 0)}
  end

  def update(
        %{
          event: "update_live_preview_block",
          rendered_html: rendered_html,
          uid: uid,
          has_children?: has_children?
        },
        socket
      ) do
    payload = %{uid: uid, rendered_html: rendered_html, has_children: has_children?}

    if socket.assigns.frontend_edit do
      FrontendEditor.update_block(payload)
    else
      LivePreview.broadcast(socket.assigns.live_preview_cache_key, "update_block", payload)
    end

    {:ok, socket}
  end

  def update(%{event: "update_live_preview"}, %{assigns: %{live_preview_active?: true}} = socket) do
    # update entire live preview (when deleting or inserting blocks)
    {:ok, fetch_root_blocks(socket, :live_preview_update, 0)}
  end

  def update(%{event: "reload_live_preview"}, %{assigns: %{live_preview_active?: true}} = socket) do
    # a media association changed — reload the iframe so the host frontend re-mounts
    # the new player (morphdom can't run the frontend's JS boot for new media)
    {:ok, fetch_root_blocks(socket, :live_preview_reload, 0)}
  end

  def update(%{event: "reload_live_preview"}, socket) do
    {:ok, socket}
  end

  def update(%{event: "update_live_preview"}, %{assigns: %{live_preview_active?: false}} = socket) do
    {:ok, socket}
  end

  def update(%{event: "flush_live_preview", token: token}, socket) do
    {:ok, Preview.flush(socket, token, &render_preview_update/3)}
  end

  # `fields` is the list of entry fields the block's module reads, or `:all`
  # when that cannot be determined from the source (datasource blocks, HEEx
  # modules — see `Block.entry_fields_read/2`). Keyed by block_ref so a
  # re-registering block replaces rather than duplicates its entry.
  def update(%{event: "register_block_wanting_entry", block_ref: block_ref} = msg, socket) do
    fields = Map.get(msg, :fields, :all)
    {mod, id} = block_ref

    # `entry_for_blocks` is deliberately not rebuilt on every main-form
    # keystroke. Existing consumers receive the changed field through the
    # targeted fan-out below, but a block mounted after that edit would
    # otherwise start with the stale snapshot from the last structural render.
    # Seed each newly registered consumer once from the current changeset;
    # subsequent edits stay on the cheaper field-delta path.
    current_entry = build_entry_for_blocks(socket.assigns.form.source, socket.assigns.block_map)
    send_update(mod, id: id, event: "replace_entry", entry: current_entry)

    {:ok, update(socket, :blocks_wanting_entry, &Map.put(&1, block_ref, fields))}
  end

  # Asset delivery from the sticky UploadManager for entry schema fields
  # (docs/UPLOADER.md Phase 4). Mirrors the old handle_file_progress success
  # branch: set the FK at the field's path and refresh the drawer state.
  # Each clause is commit_entry_field_asset/4 plus its drawer-state assigns.
  #
  # These clauses used to force `editing_*?` to false so the main save was not
  # rejected with "close the drawer first". That was a workaround for the real
  # bug — `reset_image_field` / `reset_file_field` closed their drawer without
  # clearing the flag, stranding the save guard (`reset_video_field` always did
  # it correctly). Both now clear it, so the flag can stay truthful here.
  #
  # It has to: an upload started *inside* a drawer leaves that drawer open, and
  # `assign_drawer_recovery_state/1` gates on exactly these flags — clearing one
  # dropped the drawer's recovery snapshot mid-edit, and let a save through
  # while an image was still processing, which is what the guard exists to stop.
  def update(%{event: "clear_entry_field_asset", field: field, path: path}, socket) do
    relation_key = String.to_existing_atom("#{field}_id")

    changeset =
      socket.assigns.form.source
      |> EctoNestedChangeset.update_at(path ++ [relation_key], fn _ -> nil end)
      |> put_asset_in_data(path, field, nil)

    {:ok,
     socket
     |> put_local_form(to_form(changeset, []))
     |> update_entry_with_relation(path ++ [field], nil)
     |> update_entry_assocs(path ++ [field], nil)
     |> own_asset(path, relation_key, :id)
     |> ship_all_field_changes()
     |> push_event("b:validate", %{})}
  end

  def update(
        %{event: "entry_field_upload_complete", expected_asset_id: expected, field: field, path: path} = assigns,
        socket
      ) do
    current_id = EctoNestedChangeset.get_at(socket.assigns.form.source, path ++ [String.to_existing_atom("#{field}_id")])

    if Brando.Uploads.AssetIntent.current_selection?(expected, current_id) do
      update(Map.delete(assigns, :expected_asset_id), socket)
    else
      {:ok, socket}
    end
  end

  # Processing finished for the image or video an entry field shows
  # (`Input.Image`, `Input.Video`, from `BrandoAdmin.LiveView.Form.ProcessingWatch`),
  # and maybe another editor uploaded it. Not an edit: the field keeps its id,
  # so nothing is marked dirty, owned or shipped. Only the struct the changeset
  # and the entry carry is refreshed, so that the field, a later validate and
  # the live preview all show the processed asset. A nested field's struct
  # comes from its subform; the input keeps showing the copy it was given.
  def update(%{event: "entry_field_asset_processed", field: field, path: [], asset: asset}, socket) do
    relation_key = String.to_existing_atom("#{field}_id")
    changeset = socket.assigns.form.source

    if to_string(get_field(changeset, relation_key)) == to_string(asset.id) do
      {:ok,
       socket
       |> put_form(to_form(put_asset_in_data(changeset, [], field, asset), []))
       |> update_entry_with_relation([field], asset)
       |> refresh_processed_in_preview(field, fn _ -> asset end)}
    else
      {:ok, socket}
    end
  end

  def update(%{event: "entry_field_asset_processed"}, socket), do: {:ok, socket}

  # The same for an image in an entry gallery (`Input.Gallery`): its objects
  # holding the image get the processed copy, in the changeset (stored and
  # unsaved objects alike) and in the entry.
  def update(%{event: "entry_gallery_image_processed", field: key, path: [], image: image}, socket) do
    changeset = socket.assigns.form.source
    refresh = &refresh_gallery_image(&1, image)

    changeset = %{
      changeset
      | data: Map.update!(changeset.data, key, refresh),
        changes:
          if(Map.has_key?(changeset.changes, key),
            do: Map.update!(changeset.changes, key, refresh),
            else: changeset.changes
          )
    }

    entry = socket.assigns.entry

    {:ok,
     socket
     |> put_form(to_form(changeset, []))
     |> assign(:entry, if(entry, do: Map.update!(entry, key, refresh), else: entry))
     |> refresh_processed_in_preview(key, refresh)}
  end

  def update(%{event: "entry_gallery_image_processed"}, socket), do: {:ok, socket}

  def update(
        %{event: "entry_field_upload_complete", asset_type: :file, field: field, path: path, asset: file},
        socket
      ) do
    {:ok, deliver_entry_field_asset(socket, :file, field, path, file)}
  end

  def update(
        %{event: "entry_field_upload_complete", asset_type: :image, field: field, path: path, asset: image},
        socket
      ) do
    socket =
      if image.status != :processed do
        update(socket, :processing_images, &[image.id | &1])
      else
        socket
      end

    send_update(ImagePicker, id: "image-picker", refresh_images: true)

    {:ok, deliver_entry_field_asset(socket, :image, field, path, image)}
  end

  def update(
        %{event: "entry_field_upload_complete", asset_type: :video, field: field, path: path, asset: video},
        socket
      ) do
    {:ok, deliver_entry_field_asset(socket, :video, field, path, video)}
  end

  # Gallery entry fields: append the delivered image to the gallery assoc
  # (lifted from the old handle_gallery_progress success branch).
  def update(
        %{event: "entry_field_upload_complete", asset_type: :gallery, field: key, asset: image} = params,
        socket
      ) do
    path = Map.get(params, :path, [])
    component_id = Map.get(params, :component_id) || "#{socket.assigns.singular}_#{key}"
    config_target = Map.get(params, :config_target)
    gallery = gallery_at(socket.assigns.form.source, path, key)

    new_gallery_image = %{
      image_id: image.id,
      creator_id: socket.assigns.current_user.id,
      gallery_id: gallery && gallery.id,
      image: image
    }

    current_gallery_objects = (gallery && gallery.gallery_objects) || []

    unloaded_image_ids =
      current_gallery_objects
      |> Enum.filter(&(&1.image != nil && &1.image.__struct__ == Ecto.Association.NotLoaded))
      |> Enum.map(& &1.image_id)

    loaded_image_ids =
      current_gallery_objects
      |> Enum.filter(&(&1.image != nil && &1.image.__struct__ != Ecto.Association.NotLoaded))
      |> Enum.map(& &1.image_id)

    selected_images = loaded_image_ids ++ unloaded_image_ids ++ [image.id]

    send_update(ImagePicker, id: "image-picker", selected_images: selected_images)

    send_update(BrandoAdmin.Components.Form.Input.Gallery,
      id: component_id,
      new_image: %{image_id: image.id, image: image},
      selected_images: selected_images
    )

    # Already-processed deliveries (inline-Oban race) get no later [:image,
    # :updated] broadcast — an unconditional add would leave a stale
    # never-cleared processing_images entry.
    socket =
      if image.status != :processed do
        update(socket, :processing_images, &[image.id | &1])
      else
        socket
      end

    {:ok, append_gallery_object(socket, path, key, new_gallery_image, config_target)}
  end

  # Gallery entry fields: append the delivered video to the gallery assoc.
  def update(
        %{event: "entry_field_upload_complete", asset_type: :gallery_video, field: key, asset: video} = params,
        socket
      ) do
    path = Map.get(params, :path, [])
    component_id = Map.get(params, :component_id) || "#{socket.assigns.singular}_#{key}"
    config_target = Map.get(params, :config_target)
    gallery = gallery_at(socket.assigns.form.source, path, key)

    new_gallery_video = %{
      video_id: video.id,
      creator_id: socket.assigns.current_user.id,
      gallery_id: gallery && gallery.id,
      video: video
    }

    selected_videos =
      ((gallery && gallery.gallery_objects) || [])
      |> Enum.filter(& &1.video_id)
      |> Enum.map(& &1.video_id)
      |> Kernel.++([video.id])

    send_update(VideoPicker, id: "video-picker", selected_videos: selected_videos)

    send_update(BrandoAdmin.Components.Form.Input.Gallery,
      id: component_id,
      new_video: %{video_id: video.id, video: video},
      selected_videos: selected_videos
    )

    {:ok, append_gallery_object(socket, path, key, new_gallery_video, config_target)}
  end

  # Unified handler for updating entry relations.
  # Handles live preview, entry/changeset updates, and validation in one place.
  #
  # Optional params:
  #   update_entry: false       - also update socket.assigns.entry
  #   force_validation: false   - also push b:validate + svelte remounts (implies update_entry)
  #   force_live_preview_update: false - force immediate live preview update
  def update(
        %{event: "update_entry_relation", path: path, updated_relation: updated_relation} = params,
        socket
      ) do
    update_entry? = Map.get(params, :update_entry, false)
    force_validation? = Map.get(params, :force_validation, false)
    live_preview_active? = socket.assigns.live_preview_active?

    force_live_preview_update =
      live_preview_active? && Map.get(params, :force_live_preview_update, false)

    fields_demanding_full_live_preview_rerender =
      socket.assigns.fields_demanding_full_live_preview_rerender

    # 1. Always update updated_entry_assocs (for live preview)
    socket = update_entry_assocs(socket, path, updated_relation)
    socket = if params[:draft_dirty], do: Drafts.dirty(socket), else: socket

    # 2. Optionally update entry
    socket =
      if update_entry? or force_validation? do
        update_entry_with_relation(socket, path, updated_relation)
      else
        socket
      end

    # 4. Optionally trigger validation + svelte remounts
    socket =
      if force_validation? do
        socket |> push_event("b:validate", %{}) |> force_svelte_remounts()
      else
        socket
      end

    # 5. Always handle live preview
    lp_path = live_preview_path(path)

    full_rerender? =
      live_preview_active? &&
        Enum.any?(fields_demanding_full_live_preview_rerender, &(&1 == lp_path))

    socket
    |> maybe_invalidate_live_preview_assign(lp_path)
    |> maybe_full_rerender_live_preview(full_rerender?)
    |> maybe_force_live_preview_update(full_rerender?, force_live_preview_update)
    |> then(&{:ok, &1})
  end

  # Deprecation wrapper — delegates to the unified event handler
  def update(%{action: :update_entry_relation} = params, socket) do
    IO.warn("send_update with action: :update_entry_relation is deprecated, use event: \"update_entry_relation\"")

    params
    |> Map.delete(:action)
    |> Map.put(:event, "update_entry_relation")
    |> update(socket)
  end

  # A revision loaded as a working copy (the revisions drawer): the form
  # stays on the entry as it is saved now and takes the revision as unsaved
  # changes, its fields here and its blocks in each block field, so Save
  # writes them. The block fields leave the entry's edit session while it is
  # shown (`EditSession.detach/2`).
  def update(%{action: :load_working_copy, revision_entry: revision_entry}, socket) do
    %{schema: schema, entry: entry, current_user: current_user, form_blueprint: blueprint} = socket.assigns
    block_assocs = Enum.map(blueprint.blocks, &:"entry_#{&1.name}")
    params = revision_entry |> Brando.Revisions.restore_params(entry) |> Map.drop(block_assocs)

    changeset =
      entry
      |> schema.changeset(params, current_user)
      |> Map.put(:action, :validate)

    for %{name: field} <- blueprint.blocks do
      send_update(BlockField,
        id: "#{socket.assigns.id}-blocks-#{field}",
        event: "load_working_copy",
        entry_blocks: Map.get(revision_entry, :"entry_#{field}", [])
      )
    end

    socket
    |> assign(:blocks_detached?, true)
    |> put_local_form(to_form(changeset, []))
    |> assign_entry_for_blocks()
    |> clear_blocks_root_changesets()
    |> force_svelte_remounts(:all)
    |> Drafts.dirty()
    |> then(&{:ok, &1})
  end

  def update(%{action: :update_entry_hard_reset, updated_entry: updated_entry}, socket) do
    send_update_after(__MODULE__, [id: socket.assigns.id, event: "set_block_map"], 1000)
    send(self(), {:progress_popup, "Setting new block map..."})

    # The block fields are mounted again from `updated_entry`, in the entry's
    # edit session.
    socket
    |> assign(:blocks_detached?, false)
    |> assign(:entry, updated_entry)
    |> assign_refreshed_form()
    |> assign(:block_map, [])
    |> assign_entry_for_blocks()
    |> clear_blocks_root_changesets()
    |> reload_all_blocks()
    |> force_svelte_remounts(:all)
    |> then(&{:ok, &1})
  end

  def update(%{action: :update_entry, updated_entry: updated_entry}, socket) do
    %{schema: schema, current_user: current_user} = socket.assigns
    new_changeset = schema.changeset(updated_entry, %{}, current_user)

    send_update_after(__MODULE__, [id: socket.assigns.id, event: "set_block_map"], 500)

    {:ok,
     socket
     |> assign(:entry, updated_entry)
     |> put_form(to_form(new_changeset, []))
     |> clear_owned_assets()
     |> assign(:block_map, [])
     |> force_svelte_remounts(:all)}
  end

  def update(
        %{updated_entry: updated_entry},
        %{assigns: %{schema: schema, current_user: current_user}} = socket
      ) do
    raise "DEPRECATE form.ex:updated_entry —— use action: :update_entry instead"
    new_changeset = schema.changeset(updated_entry, %{}, current_user)

    {:ok,
     socket
     |> put_form(to_form(new_changeset, []))
     |> force_svelte_remounts()}
  end

  # A block field read its rows again because someone else wrote them (the
  # edit session moved onto them, see `Brando.EditSession`). The entry this
  # form saves from follows, so the save matches the rows by id instead of
  # replacing rows that no longer exist.
  #
  # A save that has collected its blocks but not written them yet collected
  # them from the old rows: written against the new ones, it would delete
  # whatever the other write added (`recollect_blocks/2`).
  def update(%{event: "entry_blocks_reloaded", block_field: field, entry_blocks: entry_blocks}, socket) do
    socket = recollect_blocks(socket, field)

    assoc = :"entry_#{field}"
    form = socket.assigns.form
    changeset = %{form.source | data: Map.put(form.source.data, assoc, entry_blocks)}

    block_map =
      Enum.map(socket.assigns.block_map, fn
        {^field, module, _blocks, opts} -> {field, module, entry_blocks, opts}
        other -> other
      end)

    {:ok,
     socket
     |> assign(:entry, socket.assigns.entry && Map.put(socket.assigns.entry, assoc, entry_blocks))
     |> assign(:block_map, block_map)
     |> put_form(to_form(changeset, []))}
  end

  def update(%{event: "set_block_map"}, socket) do
    {:ok,
     socket
     |> assign_block_map()
     |> assign_entry_for_blocks()}
  end

  # got all root changesets for the block field
  def update(
        %{event: "provide_root_blocks", tag: {:preview_update, token}, block_field: field, root_changesets: roots},
        socket
      ) do
    {:ok, Preview.receive_blocks(socket, token, field, roots, &render_preview_update/3)}
  end

  def update(
        %{event: "provide_root_blocks", tag: {:ai_context, token}, block_field: field, root_changesets: roots},
        socket
      ) do
    {:ok, receive_ai_blocks(socket, token, field, roots)}
  end

  def update(%{event: "ai_blocks_unanswered", token: token}, socket) do
    {:ok, give_up_ai_request(socket, token)}
  end

  def update(
        %{
          event: "provide_root_blocks",
          root_changesets: root_changesets,
          block_field: block_field,
          tag: tag
        },
        socket
      ) do
    block_changesets = socket.assigns.block_changesets

    list_of_changesets =
      root_changesets
      |> Enum.reduce([], fn
        {_key, nil}, acc -> acc
        {_key, cs}, acc -> [Brando.Utils.set_action(cs) | acc]
      end)
      |> Enum.reverse()

    updated_block_changesets = Map.put(block_changesets, block_field, list_of_changesets)

    {:ok,
     socket
     |> assign(:block_changesets, updated_block_changesets)
     |> event_tag_received(tag)}
  end

  # got transformer data from a Transformer component
  def update(
        %{
          event: "provide_transformer_data",
          transformer_field: field,
          transformer_data: data,
          tag: tag
        },
        socket
      ) do
    updated = Map.put(socket.assigns.transformer_changesets, field, data)

    {:ok,
     socket
     |> assign(:transformer_changesets, updated)
     |> event_tag_received(tag)}
  end

  def update(%{action: :event_tag_received, tag: tag}, socket) do
    {:ok, event_tag_received(socket, tag)}
  end

  # A subform's add, insert, remove or reorder, applied to this form's own
  # changeset — always the latest — rather than to the copy the subform last
  # rendered with. Two quick adds both land. See `SubformHelpers.apply_op/2`.
  #
  # Whatever a change in the form does besides, this does too, without asking
  # the browser for its fields (which could be a row behind): the other
  # editors learn the field is changed, the blocks that read it get its rows,
  # and the live preview and the website editor follow it.
  def update(%{action: :update_entries, field: field, op: op}, socket) do
    changeset = socket.assigns.form.source

    case changeset |> SubformHelpers.current_entries(field) |> SubformHelpers.apply_op(op) do
      :stale ->
        {:ok, socket}

      entries ->
        updated = SubformHelpers.put_entries(changeset, field, entries)

        socket =
          socket
          |> put_local_form(to_form(updated, []))
          |> Drafts.dirty()
          |> broadcast_dirty_fields()
          |> send_updated_entry_field_to_blocks(
            [Access.key(field)],
            updated |> apply_changes() |> Map.get(field),
            to_string(field)
          )
          |> tap(&FrontendEditor.field_changed/1)
          |> maybe_invalidate_live_preview_assign([field])
          |> maybe_fetch_root_blocks(:live_preview_update, 0)

        {:ok, socket}
    end
  end

  def update(
        %{action: :update_changeset, changeset: updated_changeset, force_validation: true},
        socket
      ) do
    {:ok,
     socket
     |> put_local_form(to_form(updated_changeset, []))
     |> Drafts.dirty()
     |> push_event("b:validate", %{})
     |> force_svelte_remounts()}
  end

  # Appends a row to an `embeds_many` field, as if the editor had pressed its
  # add button: unsaved, every other unsaved change kept, and saved with the
  # form. For views that offer a row from outside the form, like the SEO
  # view's "Redirect" on a 404. `focus` names the new row's field to scroll to
  # and focus.
  def update(%{event: "append_embed", field: field, attrs: attrs} = params, socket) do
    changeset = socket.assigns.form.source
    %Ecto.Embedded{cardinality: :many, related: module} = changeset.data.__struct__.__schema__(:embed, field)

    row =
      module
      |> struct()
      |> Changeset.change(attrs)
      |> Map.put(:action, :insert)

    rows = Changeset.get_embed(changeset, field) ++ [row]
    updated = Changeset.put_embed(changeset, field, rows)
    form = to_form(updated, [])

    socket =
      case params[:focus] do
        nil ->
          socket

        focus ->
          name = "#{form.name}[#{field}][#{length(rows) - 1}][#{focus}]"
          push_event(socket, "b:scroll_to", %{selector: ~s([name="#{name}"]), focus: true})
      end

    {:ok, socket |> put_local_form(form) |> Drafts.dirty()}
  end

  def update(%{action: :update_changeset, changeset: updated_changeset}, socket) do
    updated_form = to_form(updated_changeset, [])

    {:ok, socket |> put_local_form(updated_form) |> Drafts.dirty()}
  end

  # Gallery picker writes. The gallery components hand back a replacement
  # gallery — `%{config_target:, gallery_objects:}` — and the PATH it lives at,
  # rather than a rebuilt entry changeset.
  #
  # They cannot build one: the changeset they hold belongs to whatever schema
  # OWNS the gallery, which for a nested gallery is not the entry. Sending that
  # through `:update_changeset` addressed `"<nested singular>_form"`, a
  # component that does not exist, so nested gallery picker selections silently
  # went nowhere; had the id matched, it would have replaced the entry changeset
  # with a subrecord's. This mirrors how uploads already deliver
  # (`append_gallery_object/5`), which is why that path never had the bug.
  def update(%{action: :put_gallery, path: path, key: key, gallery: new_gallery}, socket) do
    {:ok,
     socket
     |> put_gallery_at(path, key, new_gallery)
     |> push_event("b:validate", %{})
     |> force_svelte_remounts()}
  end

  def update(
        %{updated_gallery_image: %{path: path} = updated_gallery_image, key: key},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    images =
      changeset
      |> get_field(key)
      |> Enum.map(fn
        %{path: ^path} -> updated_gallery_image
        img -> img
      end)

    updated_changeset = put_change(changeset, key, images)

    {:ok,
     socket
     |> put_form(to_form(updated_changeset, []))
     |> assign(:processing, false)}
  end

  def update(
        %{action: :refresh_entry},
        %{
          assigns: %{
            schema: schema,
            entry_id: entry_id,
            singular: singular,
            context: context,
            form_blueprint: form_blueprint,
            current_user: current_user
          }
        } = socket
      ) do
    query_params =
      entry_id
      |> maybe_query(form_blueprint)
      |> add_preloads(schema, form_blueprint)
      |> Map.put(:with_deleted, true)

    updated_entry = apply(context, :"get_#{singular}!", [query_params])

    updated_changeset = schema.changeset(updated_entry, %{}, current_user)

    {:ok,
     socket
     |> assign(:entry, updated_entry)
     |> put_form(to_form(updated_changeset))
     |> clear_owned_assets()
     |> force_svelte_remounts(:all)}
  end

  # only used for allowing global sets to add "select" options.
  def update(%{action: :add_select_var_option, var_key: var_key}, socket) do
    changeset = socket.assigns.form.source
    globals = get_field(changeset, :globals) || []

    updated_globals =
      Enum.reduce(globals, [], fn
        %{key: ^var_key} = var, acc ->
          acc ++
            [
              put_in(
                var,
                [Access.key(:options)],
                (var.options || []) ++
                  [%Brando.Content.Var.Option{label: "label", value: "option"}]
              )
            ]

        var, acc ->
          acc ++ [var]
      end)

    updated_changeset = put_change(changeset, :globals, updated_globals)
    updated_form = to_form(updated_changeset, [])

    {:ok, put_local_form(socket, updated_form)}
  end

  def update(%{action: :notes_count, count: count}, socket) do
    {:ok, assign(socket, :notes_open_count, count)}
  end

  # A heavy entry loaded with a custom query: its fields went out with the
  # previous render, so they are on screen while the block tree renders.
  def update(%{action: :render_blocks}, socket) do
    {:ok, socket |> assign(:blocks_ready?, true) |> Preview.resume()}
  end

  # `run_load/3` on a sandboxed E2E server: the load runs here, in the
  # LiveView, after the render that went out before it.
  def update(%{action: :run_load, key: key, load: load}, socket) do
    {:noreply, socket} = handle_async(key, {:ok, load.()}, socket)
    {:ok, socket}
  end

  def update(%{action: :apply_translation}, socket) do
    cond do
      not Translation.apply?(socket.assigns) ->
        {:ok, socket}

      not socket.assigns.blocks_ready? or socket.assigns.entry_loading? ->
        send_update_after(__MODULE__, [id: socket.assigns.id, action: :apply_translation], 100)
        {:ok, socket}

      true ->
        case Translation.restore_changeset(socket) do
          {:ok, changeset, socket} ->
            {:ok, apply_restored_changeset(socket, changeset, :translation)}

          :error ->
            send(self(), {:toast, gettext("The changes from the source could not be loaded into the form.")})
            {:ok, socket}
        end
    end
  end

  def update(assigns, socket) do
    form_name = assigns[:name] || :default

    socket =
      socket
      |> assign(assigns)
      |> assign_new(:entry_id, fn -> nil end)
      |> assign_new(:singular, fn -> assigns.schema.__naming__().singular end)
      |> assign_sync_fields()
      |> assign_new(:context, fn -> assigns.schema.__modules__().context end)
      |> assign_new(:form_blueprint, fn ->
        case assigns.schema.__form__(form_name) do
          nil ->
            raise Brando.Exception.BlueprintError,
              message: "Missing `#{form_name}` form declaration for `#{inspect(assigns.schema)}`"

          form ->
            form
        end
      end)
      # The entry layout heads the form with the entry's own title (see
      # `EntryHeader`); a `<:header>` slot is no longer shown, but older
      # LiveViews may still pass one.
      |> assign_new(:header, fn -> nil end)
      |> assign_new(:layout, fn -> :entry end)
      |> assign_settings_save_target()
      |> assign_header()
      |> assign_new(:instructions, fn -> [] end)
      |> assign_new(:video_context, fn -> :asset end)
      |> assign_new(:frontend_edit, fn -> nil end)
      |> assign_new(:frontend_status, fn -> %{} end)
      |> FrontendEditor.init()

    cond do
      # The entry or its blocks are still loading and the parent re-rendered
      # (presence etc.): the new props are assigned above, and the rest of the
      # pipeline runs when the load lands.
      socket.assigns.entry_loading? or not socket.assigns.blocks_ready? ->
        {:ok, socket}

      socket.assigns.initial_update && socket.assigns.entry_id ->
        {:ok, open_entry(socket)}

      true ->
        {:ok, socket |> assign_entry() |> finish_form_update()}
    end
  end

  # A settings screen (`layout={:settings}`) is a singleton: its Save stays on
  # the screen instead of closing back to a listing.
  defp assign_settings_save_target(%{assigns: %{initial_update: true, layout: :settings}} = socket),
    do: assign(socket, :save_redirect_target, :self)

  defp assign_settings_save_target(socket), do: socket

  defp default_save_target(%{assigns: %{layout: :settings}}), do: :self
  defp default_save_target(socket), do: FrontendEditor.save_target(socket)

  # The tail of the update pipeline — expects :entry to be assigned. Runs
  # for create forms and subsequent parent updates, and when an existing
  # entry has loaded (`open_entry/1`). A heavy entry runs the first half
  # before its blocks are loaded and the second once they are.
  defp finish_form_update(socket) do
    socket
    |> finish_form_fields()
    |> finish_form_blocks()
  end

  defp finish_form_fields(socket) do
    socket
    # The entry as it was read, before recovery or deliveries change it: the
    # recovery baseline (`Drafts.init/1`)
    |> assign_new(:opened_entry, fn -> socket.assigns.entry end)
    |> assign_addon_statuses()
    |> assign_default_params()
    |> extract_tab_names()
    |> assign_form()
    |> maybe_assign_uploads()
    |> assign(:initial_update, false)
  end

  # Everything that reads the entry's blocks.
  defp finish_form_blocks(socket) do
    socket
    |> maybe_assign_block_map()
    |> maybe_assign_entry_for_blocks()
    |> FrontendEditor.unless_frontend(&Drafts.init/1)
    |> then(&Drafts.keep_baseline(&1, &1.assigns[:opened_entry]))
    |> Translation.assign_state()
    |> FrontendEditor.unless_frontend(&schedule_translation_apply/1)
  end

  # A synchronized translation opens with its pending version in the form.
  # Applied once the block fields exist, as a recovery copy is.
  defp schedule_translation_apply(socket) do
    if connected?(socket) and Translation.apply?(socket.assigns),
      do: send_update_after(__MODULE__, [id: socket.assigns.id, action: :apply_translation], 100)

    socket
  end

  # After a save the form reloads the entry; its translation state and any
  # newer pending version are loaded again.
  defp refresh_translation(socket, stale?) do
    socket
    |> assign(:translation, nil)
    |> Translation.assign_state()
    |> then(fn
      %{assigns: %{translation: %{} = state}} = socket -> assign(socket, :translation, %{state | stale?: stale?})
      socket -> socket
    end)
    |> schedule_translation_apply()
  end

  # Opening an existing entry. The entry is read before the form's first
  # render, so its heading, tabs and fields arrive real rather than as a
  # skeleton, and LiveView keeps the page the user came from on screen until
  # then (a listing marks the row they clicked: `openingRow.js`). Its blocks
  # decide the rest:
  #
  #   * at most `@light_block_limit` (every level counted) load and render in
  #     the same step, so a light entry goes straight to the complete form;
  #   * more, and the form renders without them: read-only, block outlines
  #     where they go, "Loading N blocks" in the toolbar. The blocks follow
  #     (`run_load/3`); Save and recovery copies wait for them.
  #
  # A blueprint with its own form query loads in one piece, so a heavy one
  # shows the full skeleton (`EntrySkeleton.form/1`) until it has.
  #
  # The limit, measured from the Pages listing on the flat bench entries
  # (`e2e/priv/repo/e2e_seeds_large.exs`, with 10, 20 and 30 built the same
  # way), from the click:
  #
  #   blocks                      5     10     20     30     40
  #   in one step                112    154    221    288    367 ms
  #     at 4x CPU                390    472    757  1 030  1 338 ms
  #   fields first: the fields    59     67     69     70     58 ms
  #     at 4x CPU                211    210    215    208    236 ms
  #   fields first: the blocks   114    140    178    239    280 ms
  #     at 4x CPU                415    521    673    828  1 078 ms
  #
  # Up to 20 blocks the complete form arrives in about 0.2 s (0.75 s on a
  # slow machine), and the fields-first frame would be on screen for only
  # ~0.1 s before it: a flash of outlines rather than a step. Past that the
  # wait on the listing grows by ~30 ms a block (4x CPU) while showing the
  # fields first stays at ~0.2 s, and gets to the whole form sooner.
  @light_block_limit 20

  # Events that wait for a heavy entry's blocks (`handle_event/3`)
  @wait_for_blocks ~w(save save_form push_submit push_submit_redirect push_submit_new push_submit_minor
                      open_live_preview open_live_preview_standalone select_preview_target toggle_preview_targets
                      share_link store_revision)

  @doc "The most blocks an entry opens with in one step, see `open_entry/1`."
  def light_block_limit, do: @light_block_limit

  defp open_entry(socket) do
    %{schema: schema, form_blueprint: form_blueprint} = socket.assigns

    cond do
      not schema.has_trait(Brando.Trait.Blocks) -> open_in_one_step(socket)
      is_nil(form_blueprint.query) -> open_fields_first(socket)
      true -> open_with_custom_query(socket)
    end
  end

  defp open_in_one_step(socket) do
    case fetch_entry(entry_source(socket), []) do
      {:ok, entry} -> entry_opened(socket, entry)
      :not_found -> not_found_on_open(socket)
    end
  end

  defp open_fields_first(socket) do
    case fetch_entry(entry_source(socket), skip_blocks: true) do
      {:ok, entry} -> open_with_blocks_counted(socket, entry)
      :not_found -> not_found_on_open(socket)
    end
  end

  defp open_with_blocks_counted(%{assigns: %{schema: schema}} = socket, entry) do
    counts = Blocks.count_entry_blocks_by_field(schema, entry.id)
    load_blocks = fn -> Brando.Repo.preload(entry, Blocks.preloads_for(schema)) end

    if light_entry?(counts) do
      entry_opened(socket, load_blocks.())
    else
      socket
      |> assign(:entry, entry)
      |> assign(:blocks_ready?, false)
      |> assign(:block_counts, counts)
      |> finish_form_fields()
      |> run_load(:blocks_load, load_blocks)
    end
  end

  defp open_with_custom_query(socket) do
    %{schema: schema, entry_id: entry_id} = socket.assigns
    counts = Blocks.count_entry_blocks_by_field(schema, entry_id)

    if light_entry?(counts) do
      open_in_one_step(socket)
    else
      source = entry_source(socket)

      socket
      |> assign(:entry_loading?, true)
      |> assign(:blocks_ready?, false)
      |> assign(:block_counts, counts)
      |> run_load(:entry_load, fn -> fetch_entry(source, []) end)
    end
  end

  # `update/2` can't navigate, so the answer goes round through
  # `handle_async/3`, which can (`entry_not_found/1`).
  defp not_found_on_open(socket) do
    socket
    |> assign(:entry_loading?, true)
    |> start_async(:entry_load, fn -> :not_found end)
  end

  defp light_entry?(counts), do: counts |> Map.values() |> Enum.sum() <= @light_block_limit

  defp entry_opened(socket, entry) do
    socket
    |> assign(:entry, entry)
    |> finish_form_update()
    |> announce_join()
  end

  # What reading the entry takes, without the socket: an async load gets it.
  defp entry_source(%{assigns: assigns}) do
    Map.take(assigns, [:schema, :form_blueprint, :entry_id, :singular, :context])
  end

  # A missing entry is an expected answer, not a failure, so it comes back as
  # `:not_found`. `skip_blocks: true` leaves out the block preloads, which a
  # custom form query can't (it passes through untouched).
  defp fetch_entry(%{schema: schema, form_blueprint: form_blueprint} = source, opts) do
    query_params =
      source.entry_id
      |> maybe_query(form_blueprint)
      |> add_preloads(schema, form_blueprint, opts)
      |> Map.put(:with_deleted, true)

    case apply(source.context, :"get_#{source.singular}", [query_params]) do
      {:ok, entry} -> {:ok, entry}
      {:error, _err} -> :not_found
    end
  end

  # Runs a slow load off the LiveView, whose result arrives in
  # `handle_async/3` after the render that went out before it. A sandboxed
  # E2E server runs it in-process instead, in the next update cycle: there
  # an async task's fresh connection escapes the per-test sandbox
  # transaction and cannot see test-created entries (the same problem as
  # `:sql_sandbox_serial_preloads`).
  defp run_load(socket, key, load) do
    if Application.get_env(Brando.config(:otp_app), :sql_sandbox) do
      send_update(__MODULE__, id: socket.assigns.id, action: :run_load, key: key, load: load)
      socket
    else
      # The tenant prefix lives in the process dictionary, which a fresh
      # async task does not inherit; without it the query runs on `public`.
      start_async(socket, key, Brando.Tenant.capture_context(gated(key, load)))
    end
  end

  # Brando's own tests hold a load back (`:form_load_gate`) to act on the
  # form while it waits, which a real load is too quick for. Compiled in only
  # where `config :brando, :form_load_gate?, true` (config/test.exs).
  if Application.compile_env(:brando, :form_load_gate?, false) do
    defp gated(key, load) do
      case Application.get_env(:brando, :form_load_gate) do
        nil ->
          load

        gate ->
          fn ->
            gate.(key)
            load.()
          end
      end
    end
  else
    defp gated(_key, load), do: load
  end

  def handle_async(:entry_load, {:ok, :not_found}, socket) do
    {:noreply, entry_not_found(socket)}
  end

  # A heavy entry with a custom query: its fields render now, read-only
  # beside the block outlines, and the block tree in the next cycle.
  def handle_async(:entry_load, {:ok, {:ok, entry}}, socket) do
    send_update(__MODULE__, id: socket.assigns.id, action: :render_blocks)

    {:noreply,
     socket
     |> assign(:entry_loading?, false)
     |> entry_opened(entry)}
  end

  # A heavy entry's blocks, for the fields already on screen. The form joins
  # the other editors now, as a light entry does once it has everything.
  def handle_async(:blocks_load, {:ok, loaded}, socket) do
    {:noreply,
     socket
     |> put_loaded_blocks(loaded)
     |> finish_form_blocks()
     |> assign(:blocks_ready?, true)
     |> Preview.resume()
     |> announce_join()}
  end

  def handle_async({:tiptap_ai, id, request}, result, socket) do
    {:noreply, RichTextAI.finish(socket, id, request, result)}
  end

  # The reply names the image it describes: the block may have another by now.
  def handle_async({:suggest_ref_alt_text, {module, id}, image_id}, result, socket) do
    reply =
      case result do
        {:ok, {language, {:ok, %{values: values}}}} when is_map_key(values, language) ->
          {:ok, language, values[language]}

        _ ->
          :error
      end

    send_update(module, id: id, event: "alt_text_suggested", result: reply, image_id: image_id)
    {:noreply, socket}
  end

  # The image form's own "Suggest alt text": a suggestion under the field
  # (`AltTextSuggestion`), written by "accept_alt_suggestion".
  def handle_async({:suggest_entry_alt_text, image_id, panel, original}, result, socket) do
    socket = assign(socket, :alt_text_suggesting, false)

    case {result, socket.assigns[:entry]} do
      {{:ok, {:ok, %{values: values}}}, %{id: ^image_id}} ->
        send_update(AltTextSuggestion, id: panel, values: values, image_id: image_id, original: original)
        {:noreply, socket}

      {{:ok, {:ok, _}}, _} ->
        {:noreply, socket}

      _ ->
        send(self(), {:toast, gettext("The alt text could not be suggested. Try again, or write it yourself.")})
        {:noreply, socket}
    end
  end

  # "Suggest alt text" in the image drawer: a suggestion under the field;
  # accepted, it goes into the drawer's form, saved with it.
  def handle_async({:suggest_alt_text, image_id, panel, original}, result, socket) do
    socket = assign(socket, :alt_text_suggesting, false)

    case {result, socket.assigns[:edit_image]} do
      {{:ok, {:ok, %{values: values}}}, %{image: %{id: ^image_id}}} ->
        send_update(AltTextSuggestion, id: panel, values: values, image_id: image_id, original: original)
        {:noreply, socket}

      # The drawer moved on to another image; its suggestion is not wanted
      {{:ok, {:ok, _}}, _} ->
        {:noreply, socket}

      _ ->
        send(self(), {:toast, gettext("The alt text could not be suggested. Try again, or write it yourself.")})
        {:noreply, socket}
    end
  end

  def handle_async(key, {:exit, reason}, _socket) when key in [:entry_load, :blocks_load] do
    # surface load failures exactly like a synchronous load does
    case reason do
      {exception, stacktrace} when is_exception(exception) -> reraise(exception, stacktrace)
      other -> exit(other)
    end
  end

  # A missing entry (a stale link, or one deleted in another tab) is not a crash.
  # Raising for it took the LiveView down after it had connected, and the
  # client's rejoin mounted it again straight into the same load — forever. Say
  # so and go back to the listing instead.
  defp entry_not_found(socket) do
    %{schema: schema, current_user: current_user} = socket.assigns

    BrandoAdmin.Toast.send_to(
      current_user,
      gettext("%{name} #%{id} was not found. It may have been deleted.",
        name: Brando.Blueprint.get_singular(schema),
        id: socket.assigns.entry_id
      ),
      %{level: :error, type: :notification}
    )

    push_navigate(socket, to: schema.__admin_route__(:list, [schema.__modules__().admin_list_view]))
  end

  # Commit exactly like handle_event("save_file") does: write the FK into a
  # fresh changeset (so the main save's cast against the entry still diffs),
  # put the asset struct on the entry assoc only (NOT the _id column), and
  # push a targeted b:validate that sets the hidden input's DOM value —
  # Input.File/Image/Video render it from the assoc, so a put_change alone
  # never reaches the submit params.
  # A picker SELECT has to commit the FK exactly like an upload does. It used to
  # only assign `edit_image`/`image_changeset`, leaving the id to reach the
  # changeset through the drawer's form submit — which is dispatched by the close
  # BUTTON (`close_image/2`). Dismissing the drawer any other way (Esc, backdrop,
  # navigating away) therefore lost the selection silently.
  #
  # Block-level picks are excluded: they carry a `block_target` and commit
  # through `Block.commit_ref_data/2` instead, and `field` is nil for them.
  defp commit_selected_asset(socket, %{field: field} = edit_asset, asset) when not is_nil(field) do
    if Map.get(edit_asset, :block_target) do
      socket
    else
      commit_entry_field_asset(socket, field, Map.get(edit_asset, :path) || [], asset)
    end
  end

  defp commit_selected_asset(socket, _edit_asset, _asset), do: socket

  # Delivery for the three single-asset entry fields. They differed only in
  # which pair of assigns they wrote (`edit_image`/`image_changeset` and so on),
  # and keeping three copies is what let the `editing_*?` handling drift apart
  # between them (see D7). Galleries are genuinely different — they append to an
  # assoc — and stay on their own clauses.
  defp deliver_entry_field_asset(socket, asset_type, field, path, asset) do
    edit_key = :"edit_#{asset_type}"
    changeset_key = :"#{asset_type}_changeset"

    edit_asset =
      Map.merge(socket.assigns[edit_key], %{
        :id => asset.id,
        :field => field,
        :path => path,
        asset_type => asset
      })

    socket
    |> commit_entry_field_asset(field, path, asset)
    |> assign(edit_key, edit_asset)
    |> assign(changeset_key, change(asset))
    # NOT `editing_*? = false`: an upload started inside a drawer leaves it
    # open, and this is what the drawer's recovery snapshot is built from.
    |> assign_drawer_recovery_state()
  end

  defp commit_entry_field_asset(socket, field, path, asset) do
    relation_key = String.to_existing_atom("#{field}_id")
    full_path = path ++ [relation_key]

    updated_changeset =
      socket.assigns.form.source
      |> apply_changes()
      |> change()
      |> EctoNestedChangeset.update_at(full_path, fn _ -> asset.id end)
      |> put_asset_in_data(path, field, asset)

    entry_or_default = socket.assigns.entry || struct(socket.assigns.schema)
    updated_entry = Map.put(entry_or_default, field, asset)

    socket
    |> assign(:entry, updated_entry)
    |> put_local_form(to_form(updated_changeset, []))
    |> own_asset(path, relation_key, :id)
    |> Drafts.dirty()
    # Ship while the FK is still a change — the drawer-save path re-bakes the
    # changeset (apply_changes/change), after which there is nothing to ship.
    |> ship_all_field_changes()
    |> push_event("b:validate", %{
      target: "#{socket.assigns.singular}[#{relation_key}]",
      value: asset.id
    })
  end

  # The live preview renders the changeset with `updated_entry_assocs` merged
  # over it, so a struct an earlier relation update put there is refreshed
  # too, and then the preview renders again, as after a validate.
  defp refresh_processed_in_preview(socket, field, refresh) do
    assocs = socket.assigns.updated_entry_assocs

    socket
    |> assign(
      :updated_entry_assocs,
      if(Map.has_key?(assocs, field), do: Map.update!(assocs, field, refresh), else: assocs)
    )
    |> maybe_invalidate_live_preview_assign([field])
    |> maybe_fetch_root_blocks(:live_preview_update, 0)
  end

  defp refresh_gallery_image(%Changeset{} = gallery, image) do
    changes =
      case gallery.changes do
        %{gallery_objects: objects} when is_list(objects) ->
          %{gallery.changes | gallery_objects: Enum.map(objects, &refresh_object_image(&1, image))}

        changes ->
          changes
      end

    %{gallery | data: refresh_gallery_image(gallery.data, image), changes: changes}
  end

  defp refresh_gallery_image(%{gallery_objects: objects} = gallery, image) when is_list(objects),
    do: %{gallery | gallery_objects: Enum.map(objects, &refresh_object_image(&1, image))}

  defp refresh_gallery_image(gallery, _image), do: gallery

  defp refresh_object_image(%Changeset{} = object, %{id: id} = image) do
    if get_field(object, :image_id) == id do
      changes =
        case object.changes do
          %{image: %Changeset{} = change} -> %{object.changes | image: %{change | data: image}}
          %{image: %{}} -> %{object.changes | image: image}
          changes -> changes
        end

      %{object | data: refresh_object_image(object.data, image), changes: changes}
    else
      object
    end
  end

  defp refresh_object_image(%{image_id: id} = object, %{id: id} = image), do: Map.put(object, :image, image)
  defp refresh_object_image(object, _image), do: object

  # Change tracking re-renders an input only when `@form[field]` changes, and
  # the asset inputs are keyed on the association, not the id. Without the
  # asset in `data` the field kept showing the previous asset until some later
  # validate happened to re-render it.
  defp put_asset_in_data(changeset, [], field, asset), do: %{changeset | data: Map.put(changeset.data, field, asset)}
  defp put_asset_in_data(changeset, _nested_path, _field, _asset), do: changeset

  # Append a delivered asset to the gallery assoc: existing objects are
  # slimmed to plain maps (put_assoc with mixed nil-ID structs would raise
  # duplicate-PK — see docs/ecto-changeset-patterns.md, "New records"),
  # the new object rides along with its loaded struct, and the whole list is
  # re-sequenced. The gallery is created on first upload.
  defp append_gallery_object(socket, path, key, new_object, config_target) do
    changeset = socket.assigns.form.source
    gallery = gallery_at(changeset, path, key)

    slimmed_objects =
      if gallery do
        Enum.map(
          gallery.gallery_objects || [],
          &Brando.Galleries.slim_gallery_object/1
        )
      else
        []
      end

    new_gallery = %{
      config_target:
        (gallery && gallery.config_target) || config_target ||
          Brando.Assets.ConfigTarget.serialize({"gallery", socket.assigns.schema, key}),
      gallery_objects: sequence(slimmed_objects ++ [new_object])
    }

    put_gallery_at(socket, path, key, new_gallery)
  end

  # The single write point for a gallery living anywhere in the entry
  # changeset. `path == []` is the entry's own field; anything deeper is a
  # gallery on a nested (subform) record, which only `update_at/3` can reach.
  defp put_gallery_at(socket, path, key, new_gallery) do
    updated_changeset = put_gallery_into(socket.assigns.form.source, path, key, new_gallery)

    socket
    |> put_local_form(to_form(updated_changeset, []))
    |> own_asset(path, key, :gallery)
    |> Drafts.dirty()
  end

  defp put_gallery_into(changeset, [], key, nil), do: put_assoc(changeset, key, nil)

  defp put_gallery_into(changeset, path, key, new_gallery) do
    current_gallery = gallery_at(changeset, path, key) || %Brando.Galleries.Gallery{}

    gallery_changeset =
      current_gallery
      |> forget_unsaved_objects()
      |> change(%{config_target: new_gallery.config_target})
      |> put_assoc(:gallery_objects, new_gallery.gallery_objects)

    if path == [] do
      put_assoc(changeset, key, gallery_changeset)
    else
      EctoNestedChangeset.update_at(changeset, path ++ [key], fn _ -> gallery_changeset end)
    end
  end

  # `gallery_at/3` reads the *applied* gallery, so objects the editor added but
  # has not saved sit in `data` with `id: nil`. `put_assoc` then keys that data
  # by primary key to match the incoming params against it
  # (`Ecto.Changeset.Relation.process_current/3`), and every nil-id object keys
  # on `[nil]` — so all but the last silently shadow each other, Ecto logs
  # "found duplicate primary keys for association/embed :gallery_objects", and
  # each nil-id param is matched against whichever object happened to survive.
  #
  # The result comes out right today only because `slim_gallery_object/1` pins
  # every writable field, so the mismatched base contributes nothing — an
  # accident, not a guarantee. An unsaved object has no identity to match on, so
  # drop it from the base and let it be the plain insert it already is. Objects
  # that carry a real id still match, and still update rather than duplicate.
  defp forget_unsaved_objects(%{gallery_objects: objects} = gallery) when is_list(objects) do
    %{gallery | gallery_objects: Enum.filter(objects, &(Map.get(&1, :id) != nil))}
  end

  defp forget_unsaved_objects(gallery), do: gallery

  defp gallery_at(changeset, [], key), do: get_field(changeset, key)
  defp gallery_at(changeset, path, key), do: EctoNestedChangeset.get_at(changeset, path ++ [key])

  # -- Server-owned asset fields --
  #
  # Asset ids and galleries only ever change through server events (upload
  # delivery, picker selection, removal, gallery edits, remote sync, draft
  # restore). The hidden inputs that carry them in the DOM lag behind those
  # events by a render, so a `validate` or `save` the browser serialized before
  # that render still holds the previous value — and casting it onto `entry`
  # (which never receives the unsaved asset) silently drops the asset.
  #
  # Once this process has written such a field it owns it: params never supply
  # it again, and every cast carries the value over from the current
  # changeset. The set starts empty in a fresh process, so the recovery
  # `validate` after a reconnect still restores unsaved assets from the DOM,
  # and it is cleared whenever the form is rebuilt from a stored entry.
  #
  # Only top-level fields are tracked. Nested (subform) records are addressed
  # by list index, and their order and membership are still decided by params,
  # so a carried-over value could land on the wrong row.
  #
  #     %{meta_image_id: :id, photos: :gallery}
  defp own_asset(socket, [], key, kind) do
    assign(socket, :server_owned_assets, Map.put(owned_assets(socket), key, kind))
  end

  defp own_asset(socket, _nested_path, _key, _kind), do: socket

  defp own_changed_assets(socket, changed_fields) do
    socket.assigns.schema
    |> asset_field_kinds()
    |> Map.take(changed_fields)
    |> Enum.reduce(socket, fn {key, kind}, socket -> own_asset(socket, [], key, kind) end)
  end

  defp clear_owned_assets(socket), do: assign(socket, :server_owned_assets, %{})

  defp owned_assets(socket), do: socket.assigns[:server_owned_assets] || %{}

  defp asset_field_kinds(schema) do
    gallery_fields =
      if function_exported?(schema, :__gallery_fields__, 0),
        do: Enum.map(schema.__gallery_fields__(), &{&1.name, :gallery}),
        else: []

    schema
    |> build_asset_fk_map()
    |> Map.new(fn {key, _} -> {key, :id} end)
    |> Map.merge(Map.new(gallery_fields))
  end

  # The one place entry params become a changeset (validate, commit_tiptap and
  # both save paths).
  defp cast_entry_params(socket, entry, params), do: socket |> cast_entry_edit(entry, params, nil) |> elem(0)

  # Also returns the fields whose value was kept over the browser's old form,
  # sent before another editor's change reached it (`drop_echoes/4`).
  # `target` is the entry field the event names.
  defp cast_entry_edit(socket, entry, params, target) do
    %{schema: schema, current_user: current_user} = socket.assigns
    owned = owned_assets(socket)
    current = socket.assigns.form.source

    entry
    |> schema.changeset(owned_params(params, owned, current), current_user)
    |> reapply_owned_assets(owned, current)
    |> drop_echoes(current, replaced_values(socket), target)
  end

  # Ids are substituted rather than dropped so the schema's own validations
  # (a required asset) still see them. Galleries are dropped and put back
  # after the cast.
  defp owned_params(params, owned, current) when is_map(params) do
    Enum.reduce(owned, params, fn
      {key, :id}, params -> Map.put(params, Atom.to_string(key), id_param(get_field(current, key)))
      {key, :gallery}, params -> Map.delete(params, Atom.to_string(key))
    end)
  end

  defp owned_params(params, _owned, _current), do: params

  defp id_param(nil), do: ""
  defp id_param(id), do: to_string(id)

  defp reapply_owned_assets(changeset, owned, current) do
    Enum.reduce(owned, changeset, fn
      {key, :id}, changeset -> put_change(changeset, key, get_field(current, key))
      {key, :gallery}, changeset -> put_gallery_into(changeset, [], key, owned_gallery(get_field(current, key)))
    end)
  end

  defp owned_gallery(nil), do: nil

  defp owned_gallery(gallery) do
    objects = if is_list(gallery.gallery_objects), do: gallery.gallery_objects, else: []

    %{
      config_target: gallery.config_target,
      gallery_objects: objects |> Enum.map(&Brando.Galleries.slim_gallery_object/1) |> sequence()
    }
  end

  defp assign_entry(%{assigns: %{initial_update: false}} = socket) do
    socket
  end

  defp assign_entry(%{assigns: %{entry_id: nil}} = socket) do
    schema = socket.assigns.schema
    current_user = socket.assigns.current_user
    assign(socket, :entry, prepare_empty_entry(schema, current_user))
  end

  # Editing an existing entry never reaches this far — the update-form path
  # loads the entry itself (`open_entry/1`) before the pipeline runs, so only
  # the skip- and create-clauses above remain.

  # The fields went out before the blocks were loaded. The entry and the form
  # keep what they hold (an asset delivered meanwhile, values other editors
  # sent, a recovered form) and take only the loaded block associations: the
  # form into its data, where saving puts the block changesets.
  defp put_loaded_blocks(%{assigns: %{entry: entry, form: %{source: changeset} = form, schema: schema}} = socket, loaded) do
    take_blocks = fn into ->
      Enum.reduce(schema.__blocks_fields__(), into, fn %{name: name}, acc ->
        Map.put(acc, :"entry_#{name}", Map.fetch!(loaded, :"entry_#{name}"))
      end)
    end

    data = take_blocks.(changeset.data)

    socket
    |> assign(:entry, take_blocks.(entry))
    |> assign(:opened_entry, take_blocks.(socket.assigns.opened_entry))
    |> put_form(%{form | source: %{changeset | data: data}, data: data})
  end

  defp assign_refreshed_entry(
         %{
           assigns: %{
             schema: schema,
             entry_id: entry_id,
             singular: singular,
             context: context,
             form_blueprint: form_blueprint
           }
         } = socket
       ) do
    query_params =
      entry_id
      |> maybe_query(form_blueprint)
      |> add_preloads(schema, form_blueprint)
      |> Map.put(:with_deleted, true)

    entry = apply(context, :"get_#{singular}!", [query_params])

    socket
    |> assign(:entry, entry)
    |> Drafts.keep_baseline(entry)
  end

  defp maybe_query(id, form_blueprint) do
    BlueprintForms.resolve_query(form_blueprint.query, id)
  end

  defp maybe_assign_uploads(socket) do
    if connected?(socket) && socket.assigns[:initial_update] do
      allow_uploads(socket)
    else
      socket
    end
  end

  # -- Helpers for unified update_entry_relation handler --

  defp update_entry_assocs(socket, path, updated_relation) do
    access_path = Brando.Utils.build_access_path(path)

    assign(
      socket,
      :updated_entry_assocs,
      put_in(socket.assigns.updated_entry_assocs, access_path, updated_relation)
    )
  end

  # Transformer changeset updates are now handled by the Transformer component

  defp update_entry_with_relation(socket, path, updated_relation) do
    entry = socket.assigns.entry || struct(socket.assigns.schema)
    access_path = Brando.Utils.build_access_path(path)
    assign(socket, :entry, put_in(entry, access_path, updated_relation))
  end

  defp live_preview_path(path), do: path

  defp maybe_force_live_preview_update(socket, true, _) do
    socket
  end

  defp maybe_force_live_preview_update(socket, false, true) do
    fetch_root_blocks(socket, :live_preview_update, 0)
  end

  defp maybe_force_live_preview_update(socket, _, _) do
    socket
  end

  defp maybe_full_rerender_live_preview(
         %{assigns: %{has_blocks?: false, live_preview_active?: true}} = socket,
         true
       ) do
    # For non-block schemas, update the live preview without changing cache_key
    # This broadcasts to the Phoenix channel which triggers morphdom in the iframe
    changeset = socket.assigns.form.source
    updated_entry_assocs = socket.assigns.updated_entry_assocs
    schema = socket.assigns.schema
    cache_key = socket.assigns.live_preview_cache_key

    LivePreview.update(schema, changeset, cache_key, updated_entry_assocs)

    socket
  end

  defp maybe_full_rerender_live_preview(%{assigns: %{has_blocks?: true}} = socket, true) do
    fetch_root_blocks(socket, :live_preview_full_rerender, 1200)
  end

  defp maybe_full_rerender_live_preview(socket, false) do
    socket
  end

  defp maybe_assign_block_map(socket) do
    blocks = socket.assigns.form_blueprint.blocks

    socket
    |> assign_new(:block_map, fn -> build_block_map(socket) end)
    |> assign_new(:block_changesets, fn -> Map.new(blocks, &{&1.name, nil}) end)
    |> assign_new(:starting_templates, fn -> starting_templates(socket) end)
  end

  # The templates each block field offers to start from, by field name (see
  # `Brando.Content.StartingTemplates`). Looked up once, here, and only for a
  # field that starts out empty: a field with blocks never shows them. The
  # block fields themselves mount later and stay free of queries.
  defp starting_templates(%{assigns: %{has_blocks?: false}}), do: %{}

  defp starting_templates(%{assigns: %{schema: schema, form_blueprint: form_blueprint, entry: entry}}) do
    for %{name: name, opts: opts} <- form_blueprint.blocks,
        Map.get(entry, :"entry_#{name}") in [nil, []],
        into: %{} do
      {name, Brando.Content.StartingTemplates.list(schema, opts[:template_namespace])}
    end
  end

  defp assign_block_map(socket) do
    blocks = socket.assigns.form_blueprint.blocks

    socket
    |> assign(:block_map, build_block_map(socket))
    |> assign(:block_changesets, Map.new(blocks, &{&1.name, nil}))
  end

  # Every change to the form goes through here, so the block fields a
  # `hidden:`/`show_if:` option hides (e.g. `hidden: {:type, :external_link}`)
  # follow the form. They are kept as their own assign rather than read from
  # `@form` in the template: `assign/3` only marks it changed when the list
  # does, so a keystroke doesn't re-render every block field. Hidden block
  # fields stay mounted, since saving waits for each one's changesets.
  defp put_form(socket, form) do
    hidden_block_fields =
      case socket.assigns do
        %{form_blueprint: %{blocks: blocks}} ->
          for %{name: name, opts: opts} <- blocks, Visibility.hidden?(opts, form), do: name

        _ ->
          []
      end

    socket
    |> assign(:form, form)
    |> assign(:hidden_block_fields, hidden_block_fields)
    |> assign_header_status(form)
  end

  # The heading's status control reads these two instead of `@form`, so a
  # keystroke in another field doesn't re-render it: `assign/3` marks them
  # changed only when the status or the choices do.
  defp assign_header_status(%{assigns: %{status_field: field}} = socket, form) when not is_nil(field) do
    %{source: changeset} = form

    socket
    |> assign(:status_input_name, "#{form.name}[#{field}]")
    |> assign(:entry_status, Changeset.get_field(changeset, field))
    |> assign(
      :status_options,
      EntryHeader.status_options(Map.get(changeset.data, field), socket.assigns.can_publish?)
    )
  end

  defp assign_header_status(socket, _form), do: socket

  defp build_block_map(%{assigns: %{has_blocks?: false}}), do: []

  defp build_block_map(%{
         assigns: %{schema: schema, form_blueprint: form_blueprint, entry: entry}
       }) do
    Enum.map(
      form_blueprint.blocks,
      &{
        &1.name,
        Module.concat(schema, &1.name |> to_string() |> Macro.camelize()),
        Map.get(entry, :"entry_#{&1.name}"),
        &1.opts
      }
    )
  end

  defp add_preloads(query_params, schema, form_blueprint, opts \\ [])

  defp add_preloads(query_params, schema, %{query: nil}, opts) do
    default_preloads = Map.get(query_params, :preload, [])
    schema_preloads = Brando.Blueprint.preloads_for(schema, opts)
    preloads = Enum.uniq(schema_preloads ++ default_preloads)

    Map.put(
      query_params,
      :preload,
      preloads
    )
  end

  # if we have a custom form_query, just pass it through.
  defp add_preloads(query_params, _schema, _form, _opts) do
    query_params
  end

  # Runs from `finish_form_update/1`, which the generic `update/2` clause reaches
  # on EVERY parent re-render — Presence diffs included. Everything below except
  # `has_alternates?` is fixed for the life of the component: it comes off the
  # schema module or the form blueprint, neither of which changes after mount.
  # Recomputing it meant five `has_trait` lookups, a `Code.ensure_compiled!` and
  # a transformer map rebuild per diff.
  #
  # Two stay plain assigns, both deliberately:
  #   * `has_alternates?` reads `entry.id`, which is nil until a create form saves;
  #   * `has_meta?` is pre-assigned `false` by `mount/1` so the loading render has
  #     it (the async-load branch returns before this pipeline ever runs), and
  #     `assign_new` would therefore pin it to `false` forever.
  # Both are a single generated `has_trait/1` call, so neither is what this costs.
  defp assign_addon_statuses(%{assigns: %{schema: schema, entry: entry}} = socket) do
    socket
    |> assign_new(:has_blocks?, fn -> schema.has_trait(Brando.Trait.Blocks) end)
    |> assign(:has_meta?, schema.has_trait(Brando.Trait.Meta))
    |> assign_new(:has_revisioning?, fn -> schema.has_trait(Brando.Trait.Revisioned) end)
    |> assign_new(:has_scheduled_publishing?, fn ->
      schema.has_trait(Brando.Trait.ScheduledPublishing)
    end)
    |> assign_new(:has_live_preview?, fn -> check_live_preview(schema) end)
    |> assign_new(:live_preview_targets, fn -> LivePreview.get_targets(schema) end)
    |> assign_new(:live_preview_default_target, fn ->
      if LivePreview.has_live_preview_target(schema), do: LivePreview.get_target_config(schema).name
    end)
    |> assign_transformer_statuses()
    |> assign(
      :has_alternates?,
      (schema.has_trait(Brando.Trait.Translatable) and schema.has_alternates?()) && entry.id
    )
  end

  # The heading's fixed parts, once: the breadcrumb, the tabs without the
  # status input when the heading shows it instead, and whether this user may
  # publish. The title and status follow the entry and the form; see
  # `put_form/2` and the template.
  defp assign_header(%{assigns: %{body_tabs: _}} = socket), do: socket

  defp assign_header(%{assigns: %{schema: schema, form_blueprint: blueprint, layout: layout}} = socket) do
    {tabs, status_field} =
      if layout == :entry,
        do: EntryHeader.lift_status(blueprint.tabs),
        else: {blueprint.tabs, nil}

    socket
    |> assign(:entry_crumbs, EntryHeader.crumbs(schema))
    |> assign(:body_tabs, tabs)
    |> assign(:status_field, status_field)
    |> assign(:can_publish?, BrandoAdmin.Authorization.allowed?(:publish, schema))
  end

  # These two are STATE, not derived facts, and `reset_transformer_changesets/1`
  # owns resetting them after a save. Re-initialising them here discarded any
  # changeset a transformer had already reported if a re-render landed while the
  # form was still collecting them — the same "an unrelated update reverts your
  # work" shape as the rest of this audit. Initialise once, then leave alone.
  defp assign_transformer_statuses(%{assigns: %{transformer_changesets: _}} = socket), do: socket

  defp assign_transformer_statuses(socket) do
    transformers = extract_transformers(socket.assigns.form_blueprint)

    assign(socket,
      has_transformers?: transformers != [],
      all_transformers_received?: transformers == [],
      transformer_changesets: Map.new(transformers, fn {name, _, _} -> {name, nil} end)
    )
  end

  defp check_live_preview(schema) do
    Code.ensure_compiled!(Brando.live_preview())
    LivePreview.has_live_preview_target(schema)
  end

  defp assign_default_params(%{assigns: %{initial_params: initial_params}} = socket)
       when not is_nil(initial_params) and map_size(initial_params) > 0 do
    assign_new(socket, :default_params, fn -> initial_params end)
  end

  defp assign_default_params(%{assigns: %{form_blueprint: %{default_params: default_params}}} = socket)
       when is_map(default_params) and map_size(default_params) > 0 do
    assign_new(socket, :default_params, fn -> default_params end)
  end

  defp assign_default_params(%{assigns: %{form_blueprint: %{default_params: %{}}}} = socket) do
    assign_new(socket, :default_params, fn -> %{} end)
  end

  defp assign_default_params(%{assigns: %{name: name, schema: schema}}) do
    raise Brando.Exception.BlueprintError,
      message: "Missing form `#{inspect(name)}` for `#{inspect(schema)}`"
  end

  defp force_svelte_remounts(socket, fields \\ []) do
    revision = Map.get(socket.assigns, :tiptap_revision, 0) + 1
    names = if fields == :all, do: :all, else: Enum.map(fields, &to_string/1)

    rich_fields =
      if function_exported?(socket.assigns.schema, :__rich_text_fields__, 0),
        do: socket.assigns.schema.__rich_text_fields__(),
        else: []

    socket =
      Enum.reduce(rich_fields, socket, fn field, current ->
        if names == :all or to_string(field) in names do
          input = current.assigns.form[field]

          push_event(current, "b:tiptap:update", %{
            id: "#{input.id}-rich-text",
            html: input.value || "",
            epoch: current.assigns[:tiptap_epoch],
            revision: revision,
            source: "replacement"
          })
        else
          current
        end
      end)

    socket
    |> assign(:tiptap_revision, revision)
    |> push_event("b:component:remount", %{skip_rich_text: true})
  end

  # Maps FK fields (e.g. :cover_id) to {assoc_field, schema_module}
  # for loading associated records when receiving remote field changes.
  #
  # A value equal to the saved one leaves no change, and the form shows a
  # field's param before its saved value: the param this editor's browser
  # sent for the field goes, or the field keeps showing what it typed.
  defp apply_field_change(cs, %{field: field, value: value, assoc?: assoc?}, asset_fk_map) do
    cs =
      if assoc? do
        Changeset.put_assoc(cs, field, value)
      else
        Changeset.put_change(cs, field, value)
      end

    cs = %{cs | params: drop_param(cs.params, field)}

    # If this is an asset FK (e.g. :cover_id), load the record
    # and put it directly on the changeset data (not via put_assoc,
    # which can fail with :on_replace => :update)
    case Map.get(asset_fk_map, field) do
      nil -> cs
      {assoc_field, asset_schema} -> put_loaded_asset(cs, assoc_field, asset_schema, value)
    end
  end

  # A cleared asset: the field shows the record in `data`, so it goes too.
  defp put_loaded_asset(cs, assoc_field, _asset_schema, nil), do: %{cs | data: Map.put(cs.data, assoc_field, nil)}

  defp put_loaded_asset(cs, assoc_field, asset_schema, value) do
    case Brando.Repo.get(asset_schema, value) do
      nil ->
        cs

      record ->
        updated_data = Map.put(cs.data, assoc_field, record)
        %{cs | data: updated_data}
    end
  end

  defp build_asset_fk_map(schema) do
    image_fields =
      if function_exported?(schema, :__image_fields__, 0),
        do: Enum.map(schema.__image_fields__(), &{:"#{&1.name}_id", {&1.name, Images.Image}}),
        else: []

    video_fields =
      if function_exported?(schema, :__video_fields__, 0),
        do: Enum.map(schema.__video_fields__(), &{:"#{&1.name}_id", {&1.name, Brando.Videos.Video}}),
        else: []

    file_fields =
      if function_exported?(schema, :__file_fields__, 0),
        do: Enum.map(schema.__file_fields__(), &{:"#{&1.name}_id", {&1.name, Brando.Files.File}}),
        else: []

    Map.new(image_fields ++ video_fields ++ file_fields)
  end

  ## Entry field sync
  #
  # Entry fields (title, URI and the other blueprint fields, not blocks,
  # which go through `Brando.EditSession`) travel between the editors of an
  # entry on its `field_sync` topic. Each edit is an op on the field the
  # editor changed: an editor ships the fields it changed itself since its
  # last shipment, with their current value (a value set back to the saved
  # one included), and never a value it only holds because another editor
  # sent it or because its browser has not caught up yet.
  #
  #   * `synced_values`: field => the value the other editors hold, because
  #     we shipped it or received it from them.
  #   * `unshipped_fields`: the fields this editor changed since its last
  #     shipment. The field a `validate` names, any other input whose value
  #     the event changed, and fields the form writes itself (an asset
  #     chosen, a subform row added, `put_local_form/2`).
  #   * `replaced_values`: field => values the browser may still show for a
  #     field another editor's change replaced. An event that carries one of
  #     them for a field it does not name is the browser's old form, sent
  #     before the change reached it, and the replacing value is kept.
  #   * `held_remote`: another editor's change to the field this editor is
  #     in. It applies when the editor leaves the field without having
  #     changed it; otherwise what they typed wins and is shipped.

  # Ships the fields this editor changed since its last shipment. Used on
  # field blur and focus, save, and after an asset or a multi-select change.
  defp ship_all_field_changes(socket) do
    entry = socket.assigns[:entry]

    if entry && entry.id && socket.assigns[:singular] do
      socket = apply_held_remote(socket)
      {changes, socket} = socket |> pending_changes() |> stamp(socket)

      if changes != [], do: broadcast_field_changes(socket, entry.id, changes, nil)

      socket
      |> mark_synced(changes)
      |> assign(:unshipped_fields, MapSet.new())
      |> broadcast_dirty_fields()
    else
      socket
    end
  end

  # A joining editor loaded the saved entry. It gets every unsaved value the
  # editors hold, as we know them (`synced_values`, which our own changes
  # have just joined), addressed to it alone: the editors who already have
  # them would otherwise take back values they have since changed. A change
  # held for the field we are in goes as the others have it, not as our
  # form still shows it.
  defp ship_fields_to(socket, user_id) do
    entry = socket.assigns[:entry]

    if entry && entry.id do
      {_fields, belongs_to} = sync_fields(socket)

      changes =
        socket
        |> synced_values()
        |> Enum.sort()
        |> Enum.map(fn {field, value} ->
          %{field: field, value: value, assoc?: field in belongs_to, clock: clock(socket, field)}
        end)

      clocks = field_clocks(socket)

      if changes != [] or clocks != %{},
        do: broadcast_field_changes(socket, entry.id, changes, user_id, clocks)
    end

    socket
  end

  defp broadcast_field_changes(socket, entry_id, changes, to, clocks \\ nil) do
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      Brando.Tenant.Topic.entry("field_sync", socket.assigns.schema, entry_id),
      {:fields_shipped,
       %{
         changes: changes,
         clocks: clocks,
         user_id: socket.assigns.current_user.id,
         tab: BrandoAdmin.Presence.tab(),
         to: to
       }}
    )
  end

  # The entry loaded in this tab (opened, or after a reconnect): the other
  # editors send it the unsaved values they hold, addressed to this tab, and
  # say which field they are in. Every form does this, with or without block
  # fields.
  defp announce_join(%{assigns: %{entry: %{id: id} = entry}} = socket) when not is_nil(id) do
    if connected?(socket) do
      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        Brando.Tenant.Topic.entry("field_sync", entry.__struct__, id),
        {:editor_joined, %{user_id: socket.assigns.current_user.id, tab: BrandoAdmin.Presence.tab(), part: :fields}}
      )
    end

    socket
  end

  defp announce_join(socket), do: socket

  # The fields this editor changed whose value the other editors don't
  # hold. A field typed back to what they hold has nothing to ship.
  defp pending_changes(socket) do
    changeset = socket.assigns.form.source
    synced = synced_values(socket)
    {_fields, belongs_to} = sync_fields(socket)

    for field <- socket |> unshipped_fields() |> Enum.sort(),
        %{value: value} = change <- List.wrap(field_change(changeset, field, belongs_to)),
        value != Map.get(synced, field, Map.get(changeset.data, field)),
        do: change
  end

  # A field as it ships: the change, or the saved value when the field was
  # set back to it. A belongs_to association ships only as a change (its
  # foreign key carries the revert).
  defp field_change(changeset, field, belongs_to) do
    assoc? = field in belongs_to

    case Map.fetch(changeset.changes, field) do
      {:ok, value} -> %{field: field, value: value, assoc?: assoc?}
      :error when assoc? -> nil
      :error -> %{field: field, value: Map.get(changeset.data, field), assoc?: false}
    end
  end

  # The fields that sync, and which of them are belongs_to associations.
  # has_many/many_to_many associations hold nested changesets the receiver
  # can't put_assoc, so they don't ship; multi-selects sync those
  # themselves.
  # Computed once per form (`assign_sync_fields/1`).
  defp sync_fields(%Phoenix.LiveView.Socket{assigns: %{sync_fields: sync_fields}}), do: sync_fields
  defp sync_fields(%Phoenix.LiveView.Socket{assigns: %{schema: schema}}), do: compute_sync_fields(schema)
  defp sync_fields(%Phoenix.LiveView.Socket{assigns: %{form: form}}), do: compute_sync_fields(form.source.data.__struct__)

  defp assign_sync_fields(%{assigns: %{schema: schema}} = socket),
    do: assign_new(socket, :sync_fields, fn -> compute_sync_fields(schema) end)

  defp compute_sync_fields(schema) do
    belongs_to =
      Enum.filter(
        schema.__schema__(:associations),
        &match?(%Ecto.Association.BelongsTo{}, schema.__schema__(:association, &1))
      )

    fields = schema.__schema__(:fields) ++ schema.__schema__(:virtual_fields) ++ belongs_to
    {fields -- unsynced_field_keys(schema), belongs_to}
  end

  # Timestamps and block fields never ship as entry fields: blocks sync
  # through their own ops.
  defp unsynced_field_keys(schema) do
    block_fields =
      if function_exported?(schema, :__blocks_fields__, 0) do
        Enum.flat_map(schema.__blocks_fields__(), fn %{name: name} ->
          [name, :"rendered_#{name}", :"entry_#{name}"]
        end)
      else
        []
      end

    [:updated_at, :inserted_at | block_fields]
  end

  # Fields this editor changed.
  defp mark_local(socket, []), do: socket

  defp mark_local(socket, fields) do
    socket
    |> assign(:unshipped_fields, MapSet.union(unshipped_fields(socket), MapSet.new(fields)))
    |> assign(:replaced_values, Map.drop(replaced_values(socket), fields))
  end

  # A change the form makes itself (an asset chosen, a subform row added, a
  # recovery copy restored): the fields it changed are this editor's to ship,
  # and the other editors see them marked until they do.
  defp put_local_form(socket, form) do
    previous = socket.assigns.form.source

    socket = socket |> put_form(form) |> mark_local(changed_fields(socket, previous, form.source))

    case socket.assigns[:entry] do
      %{id: id} when not is_nil(id) -> broadcast_dirty_fields(socket)
      _ -> socket
    end
  end

  # A field's value as the form has it. An association is compared as it is
  # held: one the entry didn't preload can't be read through the changeset.
  defp field_value(%Changeset{data: %schema{}} = changeset, field) do
    if schema.__schema__(:association, field),
      do: Map.get(changeset.changes, field, Map.get(changeset.data, field)),
      else: get_field(changeset, field)
  end

  # A value the form wrote itself, with no event from the browser to follow
  # (AI text, an uploaded video, an image copy): ship it now.
  defp put_written_form(socket, form) do
    socket
    |> put_local_form(form)
    |> Drafts.dirty()
    |> ship_all_field_changes()
  end

  defp changed_fields(socket, previous, changeset) do
    {fields, _belongs_to} = sync_fields(socket)
    Enum.filter(fields, &(field_value(previous, &1) != field_value(changeset, &1)))
  end

  # A `validate` from this editor's browser: the field it names, and any
  # other input whose value it changed, are this editor's changes. Fields
  # kept over the browser's old form (`echoed`, `drop_echoes/4`) are not. A
  # replaced field stays replaced while the browser sends what it showed
  # before; it has caught up once it sends anything else.
  defp take_local_edit(socket, previous, changeset, echoed, target, entry_params) do
    {fields, _belongs_to} = sync_fields(socket)
    sent = if is_map(entry_params), do: entry_params, else: %{}
    sent? = &Map.has_key?(sent, Atom.to_string(&1))

    edited =
      for field <- fields,
          field == target or (sent?.(field) and field_value(previous, field) != field_value(changeset, field)),
          do: field

    replaced = Map.filter(replaced_values(socket), fn {field, _} -> field in echoed or not sent?.(field) end)

    socket
    |> assign(:replaced_values, replaced)
    |> mark_local(edited)
  end

  # What a `validate` changed is this editor's edit; a recovered form is not
  # one, except in the fields typed into while the tab was offline.
  defp settle_edit(false = _recovery?, socket, changeset, edit) do
    %{previous: previous, echoed: echoed, target: target, entry_params: entry_params} = edit
    {changeset, take_local_edit(socket, previous, changeset, echoed, target, entry_params), []}
  end

  defp settle_edit(true = _recovery?, socket, changeset, %{previous: previous, params: params}) do
    offline = offline_fields(socket, params)
    {keep_received(socket, previous, changeset, offline), socket, offline}
  end

  # A recovered form keeps what the other editors sent this tab since it
  # loaded, except in the fields typed into while it was offline.
  defp keep_received(socket, previous, changeset, offline) do
    socket
    |> synced_values()
    |> Map.keys()
    |> Kernel.--(offline)
    |> Enum.reduce(changeset, fn field, changeset ->
      if field_value(changeset, field) == field_value(previous, field),
        do: changeset,
        else: keep_field(changeset, previous, field)
    end)
  end

  # The entry fields typed into while the tab was offline, which the Form
  # hook lists in the recovered form (`__offline_edits`, input names).
  defp offline_fields(socket, params) do
    singular = socket.assigns.singular

    params
    |> Map.get("__offline_edits", "")
    |> to_string()
    |> String.split(" ", trim: true)
    |> Enum.flat_map(fn name ->
      case Regex.run(~r/^#{Regex.escape(singular)}\[([^\]]+)\]/, name) do
        [_, key] -> List.wrap(target_field(socket, singular, [singular, key]))
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  # After a recovery, what the tab holds reaches the others: fields typed
  # into offline as fresh edits, which win, and other recovered values that
  # differ from the saved entry with the oldest clock, `{0, tab}`, so they
  # fill fields nobody else holds and lose to every real edit. Otherwise a
  # value restored in a tab that was alone would be in nobody else's form,
  # and their save would revert it.
  #
  # A recovered value whose field has a newer clock known (the others sent
  # it with their join reply, but no value: they saved since) is older than
  # the saved entry, and the field goes back to the saved value.
  defp share_recovered(socket, offline, entry_params) do
    socket = socket |> mark_local(offline) |> ship_all_field_changes()
    entry = socket.assigns[:entry]

    if entry && entry.id && is_map(entry_params) do
      changeset = socket.assigns.form.source
      synced = synced_values(socket)
      {fields, belongs_to} = sync_fields(socket)
      tab = BrandoAdmin.Presence.tab()

      recovered =
        for field <- fields,
            Map.has_key?(entry_params, Atom.to_string(field)),
            not Map.has_key?(synced, field),
            %{value: value} = change <- List.wrap(field_change(changeset, field, belongs_to)),
            value != Map.get(changeset.data, field),
            do: Map.put(change, :clock, {0, tab})

      {outdated, changes} = Enum.split_with(recovered, &(clock(socket, &1.field) > &1.clock))
      socket = restore_saved(socket, Enum.map(outdated, & &1.field))

      if changes != [], do: broadcast_field_changes(socket, entry.id, changes, nil)

      clocks =
        Enum.reduce(changes, field_clocks(socket), &Map.update(&2, &1.field, &1.clock, fn c -> max(c, &1.clock) end))

      socket
      |> mark_synced(changes)
      |> assign(:field_clocks, clocks)
    else
      socket
    end
  end

  # The entry field `_target` names (`["page", "title"]` or a path into a
  # subform, `["page", "items", "0", "name"]`).
  defp target_field(socket, singular, [singular, key | _]) do
    {fields, _belongs_to} = sync_fields(socket)
    Enum.find(fields, &(Atom.to_string(&1) == key))
  end

  defp target_field(_socket, _singular, _target), do: nil

  # A replaced field that arrives with a value the browser showed before the
  # change replaced it, in an event that does not name it, is the browser's
  # old form: the replacing value stays. Returns the fields kept.
  defp drop_echoes(changeset, previous, replaced, target) do
    Enum.reduce(replaced, {changeset, []}, fn {field, stale}, {changeset, echoed} ->
      value = field_value(changeset, field)

      if field != target and value in stale and value != field_value(previous, field),
        do: {keep_field(changeset, previous, field), [field | echoed]},
        else: {changeset, echoed}
    end)
  end

  defp keep_field(changeset, previous, field) do
    changes =
      case Map.fetch(previous.changes, field) do
        {:ok, value} -> Map.put(changeset.changes, field, value)
        :error -> Map.delete(changeset.changes, field)
      end

    errors = Keyword.delete(changeset.errors, field)

    %{changeset | changes: changes, errors: errors, valid?: errors == [], params: drop_param(changeset.params, field)}
  end

  # The form shows a field's param before its saved value, so a field put
  # back to its saved value has to lose the param the browser sent for it.
  defp drop_param(%{} = params, field), do: Map.delete(params, Atom.to_string(field))
  defp drop_param(params, _field), do: params

  # Another editor's changes. The field this editor is in is held until it
  # leaves it (`apply_held_remote/1`); the rest apply now.
  defp receive_field_changes(socket, changes) do
    {changes, socket} = take_newer(changes, socket)
    {held, changes} = Enum.split_with(changes, &focused_field?(socket, &1.field))

    held_remote = Enum.reduce(held, held_remote(socket), &Map.put(&2, &1.field, &1))

    socket
    |> apply_remote(changes)
    |> mark_synced(held)
    |> assign(:held_remote, held_remote)
  end

  defp apply_remote(socket, []), do: socket

  defp apply_remote(socket, changes) do
    previous = socket.assigns.form.source
    asset_fk_map = build_asset_fk_map(previous.data.__struct__)
    changeset = Enum.reduce(changes, previous, &apply_field_change(&2, &1, asset_fk_map))
    fields = Enum.map(changes, & &1.field)

    replaced =
      Enum.reduce(fields, replaced_values(socket), fn field, replaced ->
        stale = field_value(previous, field)

        if stale == field_value(changeset, field),
          do: replaced,
          else: Map.update(replaced, field, [stale], &Enum.take(Enum.uniq([stale | &1]), 5))
      end)

    socket
    |> put_form(to_form(changeset, []))
    |> assign(:replaced_values, replaced)
    |> assign(:unshipped_fields, MapSet.difference(unshipped_fields(socket), MapSet.new(fields)))
    |> assign(:held_remote, Map.drop(held_remote(socket), fields))
    |> mark_synced(changes)
    |> own_changed_assets(fields)
    |> Drafts.dirty()
    |> force_svelte_remounts(fields)
  end

  # Changes held while this editor was in their field apply once it has left
  # it without changing it.
  defp apply_held_remote(socket) do
    {left, still_in} = socket |> held_remote() |> Map.values() |> Enum.split_with(&(not focused_field?(socket, &1.field)))
    unshipped = unshipped_fields(socket)

    socket
    |> assign(:held_remote, Map.new(still_in, &{&1.field, &1}))
    |> apply_remote(Enum.reject(left, &MapSet.member?(unshipped, &1.field)))
  end

  # Each field's value carries a clock, `{n, tab}`, a hybrid logical clock:
  # `n` is the wall-clock time in milliseconds, or one more than the newest
  # `n` known for the field if that is later, and the tab id breaks a tie.
  # An editor takes a value only if its clock is newer than the one it
  # holds, so two editors who send the same field at once both end with the
  # same one, and a value relayed late to a joiner can't replace a newer
  # one. Because `n` follows the wall clock, an edit made after another one
  # wins without either tab having heard of the other: a tab that opened
  # after a save, knowing no clocks, still beats the edits before it.
  defp clock(socket, field), do: Map.get(field_clocks(socket), field, {0, ""})

  defp stamp(changes, socket) do
    tab = BrandoAdmin.Presence.tab()

    {changes, clocks} =
      Enum.map_reduce(changes, field_clocks(socket), fn %{field: field} = change, clocks ->
        {n, _tab} = Map.get(clocks, field, {0, ""})
        clock = {max(System.os_time(:millisecond), n + 1), tab}
        {Map.put(change, :clock, clock), Map.put(clocks, field, clock)}
      end)

    {changes, assign(socket, :field_clocks, clocks)}
  end

  defp take_newer(changes, socket) do
    {changes, clocks} =
      Enum.flat_map_reduce(changes, field_clocks(socket), fn %{field: field} = change, clocks ->
        incoming = Map.get(change, :clock, {0, ""})

        if incoming > Map.get(clocks, field, {0, ""}),
          do: {[change], Map.put(clocks, field, incoming)},
          else: {[], clocks}
      end)

    {changes, assign(socket, :field_clocks, clocks)}
  end

  defp field_clocks(socket), do: socket.assigns[:field_clocks] || %{}

  # Fields back to the saved value, as the entry loaded, like a change from
  # another editor: the browser's old value for them is an echo from then on.
  defp restore_saved(socket, []), do: socket

  defp restore_saved(socket, fields) do
    data = socket.assigns.form.source.data
    {_fields, belongs_to} = sync_fields(socket)

    restored =
      for field <- fields, field not in belongs_to, do: %{field: field, value: Map.get(data, field), assoc?: false}

    apply_remote(socket, restored)
  end

  # The clocks a joining tab is sent with the values: each field's newest.
  # A field this tab shipped from its recovered form (`{0, tab}`) that has a
  # newer clock but came without a value was saved since by the editor who
  # sent the clock: it goes back to the saved value (`share_recovered/3`).
  defp merge_clocks(socket, clocks) when is_map(clocks) and map_size(clocks) > 0 do
    ours = field_clocks(socket)
    recovered = {0, BrandoAdmin.Presence.tab()}
    outdated = for {field, theirs} <- clocks, Map.get(ours, field) == recovered, theirs > recovered, do: field
    merged = Map.merge(ours, clocks, fn _field, ours, theirs -> max(ours, theirs) end)

    socket
    |> assign(:field_clocks, merged)
    |> restore_saved(outdated)
  end

  defp merge_clocks(socket, _clocks), do: socket

  # The value of each field the other editors already hold, because we
  # shipped it or received it from them.
  defp mark_synced(socket, changes) do
    synced = Enum.reduce(changes, synced_values(socket), &Map.put(&2, &1.field, &1.value))
    assign(socket, :synced_values, synced)
  end

  defp synced_values(socket), do: socket.assigns[:synced_values] || %{}
  defp unshipped_fields(socket), do: socket.assigns[:unshipped_fields] || MapSet.new()
  defp replaced_values(socket), do: socket.assigns[:replaced_values] || %{}
  defp held_remote(socket), do: socket.assigns[:held_remote] || %{}

  defp focused_field?(socket, field) do
    case socket.assigns[:focused_field] do
      name when is_binary(name) -> String.starts_with?(name, "#{socket.assigns.singular}[#{field}]")
      _ -> false
    end
  end

  # This editor moved to `field` (an input name): the other editors lock it,
  # and leaving the field it was in ships what we changed there.
  defp focus_field(socket, field) do
    entry = socket.assigns.entry
    old_field = socket.assigns[:focused_field]

    if entry && entry.id do
      broadcast_active_field(socket, field)

      # Clear block focus/lock when a regular field gets focus
      send(self(), :clear_block_focus)
    end

    socket = assign(socket, :focused_field, field)

    if old_field && old_field != field,
      do: ship_all_field_changes(socket),
      else: socket
  end

  defp entry_field?(socket, field), do: String.starts_with?(field, "#{socket.assigns.singular}[")

  # Leaving the field we are in (any field, for a drawer's close) releases it.
  defp leave_field(socket, field \\ nil) do
    case socket.assigns[:focused_field] do
      focused when is_binary(focused) and (is_nil(field) or field == focused) ->
        socket = assign(socket, :focused_field, nil)
        entry = socket.assigns[:entry]
        if entry && entry.id, do: broadcast_active_field(socket, nil)
        socket

      _ ->
        socket
    end
  end

  # The field this editor is in (an input name, `page[title]`), or `nil`
  # when it left it: the other editors lock and release the field, and the
  # editor's presence carries it for those who join later.
  defp broadcast_active_field(socket, field) do
    %{schema: schema, entry: entry, current_user: user} = socket.assigns
    BrandoAdmin.Presence.broadcast_active_field(schema, entry.id, field, user.id)
  end

  # Tells the other editors which of our changed fields they do not have yet,
  # as input names (`page[title]`). Their forms mark those fields. That
  # includes has_many lists, which don't ship (`sync_fields/1`) and so stay
  # ours until saved.
  defp broadcast_dirty_fields(%{assigns: %{singular: singular, schema: schema}} = socket) do
    {_fields, belongs_to} = sync_fields(socket)
    unshipped = schema.__schema__(:associations) -- (belongs_to ++ unsynced_field_keys(schema))

    lists = for {field, _} <- socket.assigns.form.source.changes, field in unshipped, do: field

    socket
    |> pending_changes()
    |> Enum.map(& &1.field)
    |> Kernel.++(lists)
    |> Enum.map(&"#{singular}[#{&1}]")
    |> Enum.sort()
    |> then(&put_dirty_fields(socket, &1))
  end

  defp broadcast_dirty_fields(socket), do: socket

  defp put_dirty_fields(%{assigns: %{dirty_fields: dirty_fields}} = socket, dirty_fields), do: socket

  defp put_dirty_fields(socket, dirty_fields) do
    entry = socket.assigns.entry

    if entry && entry.id do
      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        Brando.Tenant.Topic.entry("dirty_fields", socket.assigns.schema, entry.id),
        {:dirty_fields, dirty_fields, socket.assigns.current_user.id}
      )
    end

    assign(socket, :dirty_fields, dirty_fields)
  end

  # The form now matches the database, so nothing is pending for anyone.
  defp clear_dirty_fields(socket) do
    socket = assign(socket, :synced_values, %{})

    case socket.assigns[:dirty_fields] do
      [_ | _] -> put_dirty_fields(socket, [])
      _ -> socket
    end
  end

  defp extract_tab_names(%{assigns: %{form_blueprint: %{tabs: tabs}}} = socket) do
    socket
    |> assign_new(:active_tab, fn ->
      first_tab = List.first(tabs)
      Map.get(first_tab, :name)
    end)
    |> assign_new(:tabs, fn -> Enum.map(tabs, & &1.name) end)
  end

  # An alert's `show_if`, given the form; alerts without one always show.
  defp alert_shown?(%{show_if: show_if}, form) when is_function(show_if, 1) do
    show_if.(form) == true
  rescue
    _ -> false
  end

  defp alert_shown?(_alert, _form), do: true

  def prepare_empty_entry(schema, current_user) do
    schema
    |> struct()
    |> maybe_put_language(current_user)
    |> nil_relations(schema)
  end

  def nil_relations(entry, schema) do
    preloads = Brando.Blueprint.preloads_for(schema)
    Brando.Repo.preload(entry, preloads)
  end

  def maybe_put_language(%{language: _} = entry, current_user) do
    lang_atom = String.to_existing_atom(current_user.config.content_language)
    Map.put(entry, :language, lang_atom)
  end

  def maybe_put_language(entry, _) do
    entry
  end

  def event_tag_received(socket, :save) do
    blocks_ready? = !Enum.any?(Map.values(socket.assigns.block_changesets), &is_nil/1)
    transformers_ready? = !Enum.any?(Map.values(socket.assigns.transformer_changesets), &is_nil/1)

    if blocks_ready? && transformers_ready? do
      # The write that answers this `b:submit` carries its token; a save
      # that wrote already leaves a later one stale (`"save_form"`).
      token = System.unique_integer([:positive])

      socket
      |> assign(:all_blocks_received?, true)
      |> assign(:all_transformers_received?, true)
      |> assign(:save_collecting_since, nil)
      |> assign(:save_token, token)
      |> push_event("b:submit", %{token: token})
    else
      socket
      |> assign_received(:all_blocks_received?, blocks_ready?)
      |> assign_received(:all_transformers_received?, transformers_ready?)
    end
  end

  def event_tag_received(socket, :store_revision) do
    blocks_ready? = !Enum.any?(Map.values(socket.assigns.block_changesets), &is_nil/1)
    transformers_ready? = !Enum.any?(Map.values(socket.assigns.transformer_changesets), &is_nil/1)

    if blocks_ready? && transformers_ready? do
      changeset =
        socket.assigns.block_changesets
        |> assoc_all_block_fields(socket.assigns.form.source)
        |> assoc_all_transformer_fields(socket.assigns.transformer_changesets)

      socket
      |> store_revision(changeset)
      |> clear_blocks_root_changesets()
      |> reset_transformer_changesets()
    else
      socket
    end
  end

  def event_tag_received(socket, :share) do
    changeset = socket.assigns.form.source
    block_changesets = socket.assigns.block_changesets
    updated_entry_assocs = socket.assigns.updated_entry_assocs

    if Enum.any?(Map.values(block_changesets), &is_nil/1) do
      socket
    else
      schema = socket.assigns.schema
      changeset = assoc_all_block_fields(block_changesets, changeset)
      user = socket.assigns.current_user
      socket = assign(socket, :sharing_preview?, false)

      case LivePreview.share(
             schema,
             changeset,
             user,
             updated_entry_assocs,
             socket.assigns.live_preview_schema_target
           ) do
        {:ok, preview_url, expiration_days} ->
          message =
            gettext(
              ~s(A shareable time limited URL has been created. The URL will expire %{expiration_days} days from now.<br><br><a href="%{preview_url}" target="_blank">OPEN LINK</a>),
              %{expiration_days: expiration_days, preview_url: preview_url}
            )

          socket
          |> clear_blocks_root_changesets()
          |> push_event("b:alert", %{
            title: gettext("Get shareable link"),
            message: message,
            type: "info"
          })

        {:error, :forbidden} ->
          push_event(socket, "b:alert", %{
            title: gettext("Cannot share preview"),
            message: gettext("You do not have permission to export this entry."),
            type: "error"
          })

        {:error, reason} ->
          Logger.error("Sharing a preview failed: #{inspect(reason)}")

          push_event(socket, "b:alert", %{
            title: gettext("Cannot share preview"),
            message:
              gettext(
                "The frontend assets for this preview could not be captured, so no link was created. Check the server log and try again."
              ),
            type: "error"
          })
      end
    end
  end

  # live preview for schema without blocks
  def event_tag_received(%{assigns: %{has_blocks?: false}} = socket, :live_preview) do
    changeset = socket.assigns.form.source
    updated_entry_assocs = socket.assigns.updated_entry_assocs
    schema = socket.assigns.schema

    if changeset.errors == [] do
      case LivePreview.initialize(
             schema,
             changeset,
             updated_entry_assocs,
             socket.assigns.live_preview_schema_target
           ) do
        {:ok, cache_key} ->
          socket
          |> assign(:live_preview_active?, true)
          |> assign(:live_preview_cache_key, cache_key)
          |> assign_entry_fields_demanding_live_preview_rerender(schema)
          |> assign_entry_fields_demanding_live_preview_reassign(schema)
          |> push_event("b:live_preview", %{cache_key: cache_key})

        {:error, err} ->
          require Logger

          Logger.error("""
          => Live Preview error: #{inspect(err)}
          """)

          push_event(socket, "b:alert", %{
            title: "Live Preview error",
            message: err,
            type: "error"
          })
      end
    else
      form_blueprint = socket.assigns.form_blueprint

      socket
      |> push_errors(changeset, form_blueprint, schema, :live_preview)
    end
  end

  def event_tag_received(socket, :live_preview) do
    block_changesets = socket.assigns.block_changesets
    changeset = socket.assigns.form.source
    updated_entry_assocs = socket.assigns.updated_entry_assocs

    if Enum.any?(Map.values(block_changesets), &is_nil/1) do
      socket
    else
      # initialize live preview
      schema = socket.assigns.schema
      form_blueprint = socket.assigns.form_blueprint
      changeset = assoc_all_block_fields(block_changesets, changeset)

      if changeset.errors == [] do
        initialize_block_live_preview(socket, schema, changeset, updated_entry_assocs)
      else
        socket
        |> clear_blocks_root_changesets()
        |> push_errors(changeset, form_blueprint, schema, :live_preview)
      end
    end
  end

  # live preview standalone for schema without blocks
  def event_tag_received(%{assigns: %{has_blocks?: false}} = socket, :live_preview_standalone) do
    changeset = socket.assigns.form.source
    updated_entry_assocs = socket.assigns.updated_entry_assocs
    schema = socket.assigns.schema

    if changeset.errors == [] do
      cache_key = socket.assigns.live_preview_cache_key

      LivePreview.update_cache(cache_key, schema, changeset, updated_entry_assocs)
      send(self(), {:toast, gettext("Opening standalone live preview...")})

      url = "/__livepreview?key=#{cache_key}&mode=standalone"

      socket
      |> push_event("b:open_window", %{url: url})
    else
      form_blueprint = socket.assigns.form_blueprint

      socket
      |> push_errors(changeset, form_blueprint, schema, :live_preview)
    end
  end

  def event_tag_received(socket, :live_preview_standalone) do
    block_changesets = socket.assigns.block_changesets
    updated_entry_assocs = socket.assigns.updated_entry_assocs

    if Enum.any?(Map.values(block_changesets), &is_nil/1) do
      socket
    else
      # initialize live preview
      schema = socket.assigns.schema
      form_blueprint = socket.assigns.form_blueprint
      changeset = assoc_all_block_fields(block_changesets, socket.assigns.form.source)

      if changeset.errors == [] do
        cache_key = socket.assigns.live_preview_cache_key
        schema = socket.assigns.schema

        LivePreview.update_cache(cache_key, schema, changeset, updated_entry_assocs)
        send(self(), {:toast, gettext("Opening standalone live preview...")})

        url = "/__livepreview?key=#{cache_key}&mode=standalone"

        socket
        |> clear_blocks_root_changesets()
        |> push_event("b:open_window", %{url: url})
      else
        socket
        |> clear_blocks_root_changesets()
        |> push_errors(changeset, form_blueprint, schema, :live_preview)
      end
    end
  end

  def event_tag_received(%{assigns: %{pending_live_preview_target: nil}} = socket, :live_preview_target),
    do: clear_blocks_root_changesets(socket)

  def event_tag_received(socket, :live_preview_target) do
    block_changesets = socket.assigns.block_changesets

    if Enum.any?(Map.values(block_changesets), &is_nil/1) do
      socket
    else
      changeset = assoc_all_block_fields(block_changesets, socket.assigns.form.source)
      schema = socket.assigns.schema
      target = socket.assigns.pending_live_preview_target
      socket = socket |> clear_blocks_root_changesets() |> assign(:pending_live_preview_target, nil)

      if changeset.errors == [] do
        switch_live_preview_target(socket, schema, changeset, target)
      else
        push_errors(socket, changeset, socket.assigns.form_blueprint, schema, :live_preview)
      end
    end
  end

  def event_tag_received(socket, tag) do
    socket
    |> clear_blocks_root_changesets()
    |> push_event("b:alert", %{
      title: gettext("Received unknown event tag"),
      message: "Tag received: #{inspect(tag)}",
      type: "info"
    })
  end

  defp assign_received(socket, key, true), do: assign(socket, key, true)
  defp assign_received(socket, _key, false), do: socket

  defp initialize_block_live_preview(socket, schema, changeset, updated_entry_assocs) do
    # fetch all blocks' rendered_html
    case LivePreview.initialize(
           schema,
           changeset,
           updated_entry_assocs,
           socket.assigns.live_preview_schema_target
         ) do
      {:ok, cache_key} ->
        socket
        |> assign(:live_preview_active?, true)
        |> assign(:live_preview_cache_key, cache_key)
        |> clear_blocks_root_changesets()
        |> assign_entry_fields_demanding_live_preview_rerender(schema)
        |> assign_entry_fields_demanding_live_preview_reassign(schema)
        |> push_event("b:live_preview", %{cache_key: cache_key})

      {:error, err} ->
        Logger.error("""
        => Live Preview error: #{inspect(err)}
        """)

        push_event(socket, "b:alert", %{
          title: "Live Preview error",
          message: err,
          type: "error"
        })
    end
  end

  defp switch_live_preview_target(socket, schema, changeset, target) do
    case LivePreview.switch_target(
           schema,
           changeset,
           socket.assigns.live_preview_cache_key,
           target,
           socket.assigns.updated_entry_assocs
         ) do
      {:ok, _key} ->
        socket
        |> assign(:live_preview_schema_target, target)
        |> assign_entry_fields_demanding_live_preview_rerender(schema)
        |> assign_entry_fields_demanding_live_preview_reassign(schema)

      {:error, _reason} ->
        push_event(socket, "b:alert", %{
          title: gettext("Could not switch preview"),
          message:
            gettext("The previous preview is still open. Check the target configuration and your access, then try again."),
          type: "error"
        })
    end
  end

  def assign_entry_fields_demanding_live_preview_rerender(socket, schema) do
    lp_opts = LivePreview.get_target_config(schema, socket.assigns.live_preview_schema_target)
    assign(socket, :fields_demanding_full_live_preview_rerender, lp_opts.rerender_on_change)
  end

  def assign_entry_fields_demanding_live_preview_reassign(socket, schema) do
    lp_opts = LivePreview.get_target_config(schema, socket.assigns.live_preview_schema_target)
    assign(socket, :fields_demanding_live_preview_reassign, lp_opts.reassign_on_change)
  end

  # The whole form as a skeleton while a heavy entry with a custom form query
  # loads in one piece (`open_with_custom_query/1`). Deliberately a separate
  # DOM id without the Brando.Form hook — the hook's mounted() expects the
  # real form markup, and hooks only mount when their element enters the DOM,
  # so the real form must arrive as a fresh element.
  def render(%{entry_loading?: true, frontend_edit: %{}} = assigns) do
    ~H"""
    <div class="frontend-edit-form-wrapper">
      <div id={"#{@id}-loading"} class="frontend-edit-loading">
        <EntrySkeleton.load_state label={gettext("Opening")} />
        <EntrySkeleton.blocks count={2} label?={false} />
      </div>
    </div>
    """
  end

  def render(%{entry_loading?: true} = assigns) do
    assigns = assign(assigns, :skeleton, EntrySkeleton.describe(assigns.schema, assigns[:name] || :default))

    ~H"""
    <div>
      <EntrySkeleton.form id={"#{@id}-loading"} skeleton={@skeleton} header?={@layout == :entry} />
    </div>
    """
  end

  def render(%{frontend_edit: %{}} = assigns), do: FrontendEditor.render(assigns)

  def render(assigns) do
    ~H"""
    <div>
      <Content.modal
        :if={@pending_permalink_redirect}
        id={"#{@id}-permalink-redirect"}
        title={gettext("URL changed")}
        show
        medium
        close={JS.push("skip_permalink_redirect", target: @myself)}
      >
        <p>{gettext("Your changes have been saved. Create a permanent redirect from the previous URL?")}</p>
        <div class="field-wrapper">
          <label for={"#{@id}-permalink-from"}>{gettext("From")}</label>
          <input
            id={"#{@id}-permalink-from"}
            class="text"
            type="text"
            readonly
            value={@pending_permalink_redirect.redirect.from}
          />
        </div>
        <div class="field-wrapper">
          <label for={"#{@id}-permalink-to"}>{gettext("To")}</label>
          <input
            id={"#{@id}-permalink-to"}
            class="text"
            type="text"
            readonly
            value={@pending_permalink_redirect.redirect.to}
          />
        </div>
        <p>{gettext("Permanent redirect (301)")}</p>
        <p :if={@permalink_redirect_error} role="alert">{@permalink_redirect_error}</p>
        <:footer>
          <button type="button" class="secondary" phx-click={JS.push("skip_permalink_redirect", target: @myself)}>
            {gettext("Continue without redirect")}
          </button>
          <button
            type="button"
            class="primary"
            phx-click={JS.push("create_permalink_redirect", target: @myself)}
            phx-disable-with={gettext("Creating redirect...")}
          >
            {gettext("Create redirect")}
          </button>
        </:footer>
      </Content.modal>
      <div
        id={"#{@id}-el"}
        class={[
          "brando-form",
          assigns[:alt_text_suggesting] && "is-suggesting-alt",
          !@blocks_ready? && "is-loading-blocks"
        ]}
        aria-busy={!@blocks_ready? && "true"}
        phx-hook="Brando.Form"
        data-deliver-topic={@deliver_topic}
        data-entry-id={@entry_id}
        data-draft-enabled={@draft_enabled? && "true"}
        data-draft-form-id={@id}
        data-draft-leave-message={gettext("Your latest edits have not reached recovery storage. Leave this editor anyway?")}
        data-notes={notes?(@layout, @entry_id) && "#{@id}-notes"}
      >
        <%!-- Recovery captures are pushed from this empty element, see `draftRecovery.js` --%>
        <span id={"#{@id}-draft-capture"} data-draft-capture phx-target={@myself} hidden></span>
        <%!-- Saves are pushed from this one, see `saveForm.js` --%>
        <span id={"#{@id}-save-source"} data-save-source phx-target={@myself} hidden></span>
        <.follow_frame id={@id} />
        <div class={["form-content", @live_preview_active? && "with-live-preview"]}>
          <EntryHeader.header
            :if={@layout == :entry}
            crumbs={@entry_crumbs}
            language={EntryHeader.language(@entry)}
            title={EntryHeader.title(@schema, @entry)}
          >
            <EntryHeader.status_control
              :if={@status_field}
              id={"#{@id}-status"}
              form_id={"#{@id}_form"}
              name={@status_input_name}
              value={@entry_status}
              options={@status_options}
              disabled={!@blocks_ready?}
            />
          </EntryHeader.header>

          <%!-- The entry layout's breadcrumb names the language already. --%>
          <.creating_language
            :if={@layout != :entry}
            entry_id={@entry_id}
            schema={@schema}
            form_blueprint={@form_blueprint}
            current_user={@current_user}
          />

          <div :if={@instructions} class="form-instructions">
            {render_slot(@instructions)}
          </div>

          <.live_component
            module={DraftRecoveryComponent}
            id={DraftRecoveryComponent.id(@id)}
            dom_id={"#{@id}-draft-recovery"}
            part={:panels}
            seed={@draft_seed}
            target={@myself}
            entry_id={@entry_id}
          />

          <%!-- Leaves the viewport when the toolbar below it sticks; the Form
                hook then gives the bar its page-coloured band (`is-stuck`). --%>
          <div :if={@layout == :entry} class="form-tabs-sentinel" aria-hidden="true"></div>
          <div
            :if={@layout == :entry or length(@tabs) > 1 or @has_meta? or @has_revisioning?}
            id={"#{@id}-toolbar"}
            class={[
              "form-tabs",
              @layout == :settings && "form-tabs--plain",
              @layout == :entry && "form-tabs--split"
            ]}
          >
            <nav
              class={["form-tab-customs pill-tabs", @layout == :entry && "pill-tabs--small"]}
              aria-label={gettext("Sections")}
              inert={!@blocks_ready?}
            >
              <button
                :for={tab <- @tabs}
                :key={tab}
                type="button"
                class={[@active_tab == tab && "active"]}
                aria-pressed={to_string(@active_tab == tab)}
                phx-click={JS.push("select_tab", target: @myself)}
                phx-value-name={tab}
              >
                <span class="form-tab-label">{g(@schema, tab)}</span>
              </button>
              <button
                :if={@has_meta?}
                class="form-tool-meta"
                phx-click={toggle_drawer("##{@id}-meta-drawer")}
                type="button"
                aria-haspopup="dialog"
              >
                <span class="tab-text">Meta</span>
              </button>
              <button
                :if={@has_revisioning?}
                class="form-tool-revisions"
                phx-click={toggle_revisions(@entry_id, @id, @myself)}
                type="button"
                aria-haspopup="dialog"
              >
                <span class="tab-text">{gettext("History")}</span>
              </button>
              <button
                :if={@has_scheduled_publishing?}
                class="form-tool-schedule"
                phx-click={toggle_drawer("##{@id}-scheduled-publishing-drawer")}
                type="button"
                aria-haspopup="dialog"
              >
                <span class="tab-text">{gettext("Scheduled publishing")}</span>
              </button>
            </nav>

            <.form_presences :if={@layout != :entry} presences={@presences} current_user={@current_user} />

            <div :if={@layout == :entry} class="form-tab-builtins">
              <.form_presences presences={@presences} current_user={@current_user} />
              <%!-- Where the save state goes, while a heavy entry's blocks
                    load. The status mounts once they have, with the
                    recovery state they come with. --%>
              <EntrySkeleton.load_state
                :if={!@blocks_ready?}
                label={EntrySkeleton.loading_blocks_label(@block_counts |> Map.values() |> Enum.sum())}
              />
              <.live_component
                :if={@blocks_ready?}
                module={DraftRecoveryComponent}
                id={DraftRecoveryComponent.status_id(@id)}
                dom_id={"#{@id}-save-state"}
                part={:status}
                seed={@draft_seed}
                saved_at={Map.get(@entry, :updated_at)}
                target={@myself}
                entry_id={@entry_id}
              />
              <button
                :if={notes?(@layout, @entry_id)}
                id={"#{@id}-notes-toggle"}
                class="form-tool-notes form-tool-icon"
                disabled={!@blocks_ready?}
                phx-click={JS.dispatch("brando:notes:toggle")}
                type="button"
                aria-controls={"#{@id}-notes"}
                aria-expanded="false"
                aria-label={notes_label(@notes_open_count)}
                data-tooltip={notes_label(@notes_open_count)}
              >
                <.icon name="message-square" class="s" />
                <span :if={@notes_open_count > 0} class="form-tool-count" aria-hidden="true">{@notes_open_count}</span>
              </button>
              <button
                :if={@has_live_preview? && length(@live_preview_targets) == 1}
                phx-click={JS.push("open_live_preview", target: @myself)}
                data-toggle-preview={JS.push("open_live_preview", target: @myself)}
                class={["live-preview-toggle form-tool-preview", @live_preview_active? && "active"]}
                type="button"
                disabled={!@blocks_ready? && !@live_preview_active?}
                aria-label={gettext("Live preview")}
                aria-pressed={to_string(@live_preview_active?)}
              >
                <.icon name="eye" class="s" />
                <span class="tab-text">{gettext("Preview")}</span>
              </button>
              <div
                :if={length(@live_preview_targets) > 1}
                class="preview-chooser form-tool-preview"
                phx-click-away={if @live_preview_menu_open?, do: "close_preview_targets"}
                phx-target={@myself}
              >
                <button
                  id={"#{@id}-preview-trigger"}
                  type="button"
                  class={["live-preview-toggle preview-chooser-trigger", @live_preview_active? && "active"]}
                  disabled={!@blocks_ready? && !@live_preview_active?}
                  data-toggle-preview={JS.push("open_live_preview", target: @myself)}
                  phx-click="toggle_preview_targets"
                  phx-target={@myself}
                  aria-label={gettext("Live preview")}
                  aria-expanded={to_string(@live_preview_menu_open?)}
                  aria-controls={"#{@id}-preview-choices"}
                  title={gettext("Choose preview")}
                >
                  <.icon name="eye" class="s" />
                  <span :if={!@live_preview_active?} class="tab-text">{gettext("Preview")}</span>
                  <span
                    :for={preview <- @live_preview_targets}
                    :if={
                      @live_preview_active? && preview.name == (@live_preview_schema_target || @live_preview_default_target)
                    }
                    class="preview-current-view"
                  >{preview.label}</span>
                  <.icon name="chevron-down" class="preview-chooser-chevron dropdown-chevron" />
                </button>
                <div
                  :if={@live_preview_menu_open?}
                  id={"#{@id}-preview-choices"}
                  class="preview-choices"
                  phx-hook="Brando.PreviewChoices"
                  data-dropdown-close={JS.push("close_preview_targets", target: @myself)}
                  role="group"
                  aria-labelledby={"#{@id}-preview-heading"}
                  phx-target={@myself}
                  phx-window-keydown={
                    JS.push("close_preview_targets", target: @myself) |> JS.focus(to: "##{@id}-preview-trigger")
                  }
                  phx-key="Escape"
                >
                  <div id={"#{@id}-preview-heading"} class="preview-choices-heading">{gettext("Preview as")}</div>
                  <%!-- Another target renders the blocks: not before they load --%>
                  <button
                    :for={preview <- @live_preview_targets}
                    type="button"
                    class="preview-choice"
                    disabled={!@blocks_ready?}
                    phx-click={
                      JS.push("select_preview_target", target: @myself, value: %{name: preview.name})
                      |> JS.focus(to: "##{@id}-preview-trigger")
                    }
                    aria-pressed={
                      to_string(
                        @live_preview_active? && preview.name == (@live_preview_schema_target || @live_preview_default_target)
                      )
                    }
                  >
                    <span class="preview-choice-copy">
                      <span class="preview-choice-label">{preview.label}</span>
                      <span :if={preview.description} class="preview-choice-description">{preview.description}</span>
                    </span>
                    <.icon name="check" class="preview-choice-check" />
                  </button>
                  <button
                    :if={@live_preview_active?}
                    type="button"
                    class="preview-choice-close"
                    phx-click={JS.push("open_live_preview", target: @myself) |> JS.focus(to: "##{@id}-preview-trigger")}
                  >
                    <.icon name="x" class="s" />
                    {gettext("Close preview")}
                  </button>
                </div>
              </div>
              <.toolbar_more
                id={@id}
                target={@myself}
                languages?={@has_alternates?}
                share?={@has_live_preview? && BrandoAdmin.Authorization.allowed?(:export, @schema)}
                sharing?={@sharing_preview?}
                disabled={!@blocks_ready?}
              />
              <div class="split-dropdown form-tool-save">
                <%!-- Saves and closes, like the bottom button and ⇧⌘S; the menu
                      beside it has "save and continue editing". --%>
                <button
                  phx-click={JS.push("push_submit_redirect", target: @myself)}
                  type="button"
                  class="form-tool-save-button"
                  title={gettext("Save and close")}
                  disabled={!@blocks_ready?}
                >
                  <.icon name="check" class="s" />
                  <span>{gettext("Save and close")}</span>
                </button>
                <SplitDropdown.render id="save-dropdown" label={gettext("Save options")} disabled={!@blocks_ready?}>
                  <Button.dropdown
                    value={false}
                    event={JS.push("push_submit_redirect", target: @myself)}
                  >
                    {gettext("Save and close")}<Primitives.shortcut key="S" shift />
                  </Button.dropdown>
                  <Button.dropdown value={false} event={JS.push("push_submit", target: @myself)}>
                    {gettext("Save and continue editing")}<Primitives.shortcut key="S" />
                  </Button.dropdown>
                  <Button.dropdown
                    :if={can_create_new?(@schema)}
                    value={false}
                    event={JS.push("push_submit_new", target: @myself)}
                  >
                    {gettext("Save and create new")}
                  </Button.dropdown>
                  <Button.dropdown
                    :if={Translation.source?(@translation)}
                    value={false}
                    event={JS.push("push_submit_minor", target: @myself)}
                  >
                    {gettext("Save minor text corrections")}
                  </Button.dropdown>
                </SplitDropdown.render>
              </div>
            </div>
            <EntrySkeleton.progress :if={!@blocks_ready?} label={gettext("Loading blocks")} />
          </div>

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

          <ImageDrawer.editor
            edit_image={@edit_image}
            myself={@myself}
          />

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

          <.form
            id={"#{@id}_form"}
            class="main-form"
            for={@form}
            phx-target={@myself}
            phx-submit="save"
            data-save-event="save_form"
            phx-change="validate"
            phx-auto-recover="recover_form"
            inert={!@blocks_ready?}
          >
            <input type="hidden" name={"#{@form.name}[#{:__force_change}]"} phx-debounce="0" />
            <Translation.panel :if={@translation} state={@translation} form_name={@form.name} target={@myself} />
            <div style="display:none">
              <.live_file_input upload={@uploads[:image_editor_upload]} />
            </div>
            <MetaDrawer.render
              :if={@has_meta?}
              id={"#{@id}-meta-drawer"}
              form={@form}
              blueprint={@form_blueprint}
              form_cid={@myself}
              form_id={@id}
              current_user={@current_user}
              close={toggle_drawer("##{@id}-meta-drawer")}
            />

            <.live_component
              :if={@has_revisioning?}
              module={RevisionsDrawer}
              id={"#{@id}-revisions-drawer"}
              current_user={@current_user}
              entry_id={@entry_id}
              form={@form}
              form_cid={@myself}
              form_id={@id}
              status={@status_revisions}
              close={
                JS.push("toggle_revisions_drawer_status", target: @myself)
                |> toggle_drawer("##{@id}-revisions-drawer")
              }
            />

            <ScheduledPublishingDrawer.render
              :if={@has_scheduled_publishing?}
              id={"#{@id}-scheduled-publishing-drawer"}
              form={@form}
              close={toggle_drawer("##{@id}-scheduled-publishing-drawer")}
            />

            <.live_component
              :if={@has_alternates?}
              module={AlternatesDrawer}
              id={"#{@id}-alternates-drawer"}
              entry={@entry}
              on_close={toggle_drawer("##{@id}-alternates-drawer")}
              on_remove_link={JS.push("remove_link", target: @myself)}
            />

            <.form_tabs
              tabs={@body_tabs}
              active_tab={@active_tab}
              current_user={@current_user}
              form={@form}
              form_cid={@myself}
              form_id={@id}
              schema={@schema}
            />
          </.form>

          <%!-- A heavy entry's block fields as outlines until its blocks
                have loaded; `@block_map` is built from them. --%>
          <EntrySkeleton.blocks
            :for={%{name: block_field, opts: field_opts} <- @form_blueprint.blocks}
            :if={
              @has_blocks? && !@blocks_ready? && !field_opts[:footnote_fields] &&
                block_field not in @hidden_block_fields
            }
            count={Map.get(@block_counts, block_field, 0)}
          />
          <.live_component
            :for={{block_field, block_module, entry_blocks, field_opts} <- (@blocks_ready? && @block_map) || []}
            :if={@has_blocks?}
            :key={block_field}
            module={BlockField}
            block_module={block_module}
            block_field={block_field}
            form_name={@form.name}
            opts={field_opts}
            hidden={block_field in @hidden_block_fields}
            id={"#{@id}-blocks-#{block_field}"}
            entry={@entry_for_blocks}
            entry_blocks={entry_blocks}
            templates={Map.get(@starting_templates, block_field, [])}
            current_user={@current_user}
            form_id={@id}
            live_preview_active?={@live_preview_active?}
            live_preview_cache_key={@live_preview_cache_key}
            source_locked={Translation.locked?(@translation)}
            source_url={Translation.source_url(@translation)}
            session_detached?={@blocks_detached?}
          />

          <Primitives.submit_button
            :if={@layout == :entry && @blocks_ready?}
            processing={@processing}
            form_id={@id}
            label={gettext("Save and close")}
            shortcut={%{key: "S", shift: true}}
            icon="check"
            class="primary submit-button"
          />

          <%!-- A settings screen has one Save, in a bar that stays in view. --%>
          <div :if={@layout == :settings} class="settings-save-bar">
            <.live_component
              module={DraftRecoveryComponent}
              id={DraftRecoveryComponent.status_id(@id)}
              dom_id={"#{@id}-save-state"}
              part={:status}
              seed={@draft_seed}
              saved_at={Map.get(@entry, :updated_at)}
              target={@myself}
              entry_id={@entry_id}
            />
            <Primitives.submit_button
              processing={@processing}
              disabled={!@blocks_ready?}
              form_id={@id}
              label={gettext("Save")}
              shortcut={%{key: "S"}}
              icon="check"
              class="primary submit-button"
            />
          </div>

          <div :if={@footer} class="form-footer">
            {render_slot(@footer)}
          </div>
        </div>

        <.live_component
          :if={notes?(@layout, @entry_id)}
          module={NotesDrawer}
          id={"#{@id}-notes"}
          schema={@schema}
          entry_id={@entry_id}
          entry_title={EntryHeader.title(@schema, @entry)}
          current_user={@current_user}
          form_id={@id}
        />

        <.live_preview
          live_preview_active?={@live_preview_active?}
          live_preview_cache_key={@live_preview_cache_key}
          live_preview_target={@live_preview_target}
          target={@myself}
        />
      </div>
    </div>
    """
  end

  # Notes belong to a saved entry, in the entry editor (not settings screens).
  defp notes?(layout, entry_id), do: layout == :entry and not is_nil(entry_id)

  defp notes_label(0), do: gettext("Notes")
  defp notes_label(count), do: ngettext("Notes, %{count} open", "Notes, %{count} open", count)

  attr :id, :string, required: true
  attr :target, :any, required: true
  attr :languages?, :any, required: true
  attr :share?, :any, required: true
  attr :sharing?, :boolean, required: true
  attr :disabled, :boolean, default: false

  # The entry toolbar's "⋯" menu: the tools an editor reaches for now and
  # then. Each item does what its toolbar button did; a form with none of
  # them has no menu. `Brando.FloatingDropdown` opens it in the top layer,
  # keeps the trigger's `aria-expanded`, closes it on Escape or a choice and
  # gives the focus back to the trigger.
  defp toolbar_more(assigns) do
    ~H"""
    <div
      :if={@languages? || @share?}
      id={"#{@id}-more"}
      class="form-tool-more"
      phx-hook="Brando.FloatingDropdown"
      data-placement="bottom-end"
    >
      <button
        id={"#{@id}-more-trigger"}
        type="button"
        class="form-tool-more-trigger form-tool-icon"
        popovertarget={"#{@id}-more-menu"}
        aria-expanded="false"
        aria-label={gettext("More")}
        data-tooltip={gettext("More")}
        aria-busy={to_string(@sharing?)}
        disabled={@disabled}
      >
        <%!-- Sharing takes a moment while the blocks are gathered; the menu
              has closed by then, so its trigger spins until the link is ready. --%>
        <span class="form-tool-share-spinner" aria-hidden="true"></span>
        <.icon name="ellipsis" class="s" />
      </button>
      <div id={"#{@id}-more-menu"} class="form-tool-more-menu" popover="auto">
        <button
          :if={@languages?}
          type="button"
          class="form-tool-language"
          phx-click={toggle_drawer("##{@id}-alternates-drawer")}
          aria-haspopup="dialog"
        >
          <.icon name="languages" />
          <span>{gettext("Languages")}</span>
        </button>
        <button
          :if={@share?}
          type="button"
          class="form-tool-share"
          phx-click={JS.push("share_link", target: @target)}
          aria-busy={to_string(@sharing?)}
          disabled={@sharing?}
        >
          <.icon name="external-link" />
          <span>{gettext("Share preview")}</span>
        </button>
      </div>
    </div>
    """
  end

  attr :presences, :list
  attr :current_user, :map, required: true

  # The editors present, each ringed in the colour their field presence has
  # (`data-presence-color-index`, by position, as fieldPresence.js counts it).
  # Another editor's avatar is a button: it follows
  # where they work (the `Brando.Form` hook scrolls to the block and field
  # they move to, until this editor scrolls or clicks), shown by
  # `follow_frame/1`. The count of editors is in each avatar's tooltip.
  def form_presences(assigns) do
    assigns = assign(assigns, :count, map_size(assigns.presences))

    ~H"""
    <div class="page-presences" data-presence-count={@count}>
      <%= for {{_, user}, index} <- Enum.with_index(@presences) do %>
        <div
          :if={user.id == @current_user.id}
          class={["user-presence visible", user[:frontend?] && "is-frontend"]}
          data-presence-user-id={user.id}
          data-presence-color-index={rem(index, 6)}
          title={presence_title(user, @count)}
        >
          <.presence_avatar user={user} />
        </div>
        <button
          :if={user.id != @current_user.id}
          type="button"
          class={["user-presence visible", user[:frontend?] && "is-frontend"]}
          data-presence-user-id={user.id}
          data-presence-color-index={rem(index, 6)}
          data-presence-name={user.name}
          data-follow-user={user.id}
          aria-pressed="false"
          aria-label={gettext("Follow %{name}", name: user.name)}
          data-tooltip={presence_title(user, @count)}
        >
          <.presence_avatar user={user} />
        </button>
      <% end %>
    </div>
    """
  end

  attr :id, :string, required: true

  # Follow mode (`assets/src/Presence/follow.js`): while this editor follows
  # another one, a frame in that editor's presence colour runs round the
  # editing area, and a chip under the toolbar names them, with × to stop.
  # Neither takes a click but the chip. Shown and coloured with sticky
  # attributes (`is-following`, `data-presence-color-index`); the name is the
  # client's, in an ignored span.
  defp follow_frame(assigns) do
    ~H"""
    <div class="follow-frame" data-testid="follow-frame" aria-hidden="true"></div>
    <div class="follow-chip" data-testid="follow-chip">
      <.icon name="eye" />
      <span
        id={"#{@id}-follow-label"}
        class="follow-chip-label"
        phx-update="ignore"
        aria-live="polite"
        data-label={gettext("Following %{name}", name: "%{name}")}
      ></span>
      <button type="button" class="follow-chip-stop" data-testid="follow-stop" aria-label={gettext("Stop following")}>
        <.icon name="x" />
      </button>
    </div>
    """
  end

  attr :user, :map, required: true

  defp presence_avatar(assigns) do
    ~H"""
    <div class="avatar" data-popover={presence_label(@user)} role="img" aria-label={presence_label(@user)}>
      <%= if @user.avatar do %>
        <Content.image image={@user.avatar} size={:thumb} />
      <% else %>
        <.icon name="user" class="avatar-placeholder" />
      <% end %>
      <span :if={@user[:frontend?]} class="user-presence-website" aria-hidden="true">
        <.icon name="globe" />
      </span>
    </div>
    """
  end

  # Someone editing from the website (frontend edit mode) says so.
  defp presence_label(%{frontend?: true, name: name}), do: gettext("%{name} · editing on the website", name: name)
  defp presence_label(user), do: user.name

  # An avatar's tooltip: who it is, and how many are here when there are several.
  defp presence_title(user, count) when count > 1,
    do: presence_label(user) <> " · " <> ngettext("%{count} editing", "%{count} editing", count)

  defp presence_title(user, _count), do: presence_label(user)

  def form_tabs(assigns) do
    ~H"""
    <div
      :for={tab <- @tabs}
      :key={tab.name}
      class={["form-tab", @active_tab == tab.name && "active"]}
      data-tab-name={tab.name}
    >
      <div class="row">
        <.tab_fields
          tab={tab}
          current_user={@current_user}
          schema={@schema}
          form={@form}
          form_cid={@form_cid}
          form_id={@form_id}
        />
      </div>
    </div>
    """
  end

  def tab_fields(assigns) do
    assigns =
      assigns
      |> assign(:indexed_fields, Enum.with_index(assigns.tab.fields))
      |> assign(:alerts, Map.get(assigns.tab, :alerts) || [])
      |> assign(:relations, Brando.Blueprint.Relations.__relations__(assigns.schema))

    ~H"""
    <.alert :for={alert <- @alerts} :if={alert_shown?(alert, @form)} type={alert.type}>
      <:icon>
        <.icon name="triangle-alert" />
      </:icon>
      <%= if is_binary(alert.content) do %>
        {g(@form.source.data.__struct__, alert.content)}
      <% else %>
        {component(
          BlueprintForms.alert_component(alert.content),
          [
            form: @form,
            schema: @schema,
            current_user: @current_user,
            form_cid: @form_cid,
            form_id: @form_id
          ],
          {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
        )}
      <% end %>
    </.alert>
    <%= for {fieldset, idx} <- @indexed_fields do %>
      <%= if fieldset.__struct__ == Brando.Blueprint.Forms.Alert do %>
        <.alert :if={alert_shown?(fieldset, @form)} type={fieldset.type}>
          <:icon>
            <.icon name="triangle-alert" />
          </:icon>
          <%= if is_binary(fieldset.content) do %>
            {g(@form.source.data.__struct__, fieldset.content)}
          <% else %>
            {component(
              BlueprintForms.alert_component(fieldset.content),
              [
                form: @form,
                schema: @schema,
                current_user: @current_user,
                form_cid: @form_cid,
                form_id: @form_id
              ],
              {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
            )}
          <% end %>
        </.alert>
      <% else %>
        <Fieldset.render
          id={"#{@form.id}-fieldset-#{@tab.name}-#{idx}"}
          relations={@relations}
          form={@form}
          fieldset={fieldset}
          current_user={@current_user}
          form_cid={@form_cid}
          form_id={@form_id}
        />
      <% end %>
    <% end %>
    """
  end

  defp extract_transformers(%Brando.Blueprint.Forms.Form{transformers: transformers}), do: transformers

  def allow_uploads(socket) do
    # All field/block/var uploads go through the sticky UploadManager
    # (docs/UPLOADER.md) — only the image editor's "save as new copy" upload
    # remains form-owned.
    default_socket =
      socket
      |> allow_upload(:image_editor_upload,
        accept: ~w(.jpg .jpeg .png .webp),
        max_file_size: 50_000_000,
        max_entries: 1,
        auto_upload: true,
        progress: &__MODULE__.handle_image_editor_upload_progress/3
      )

    # Image fields upload through the sticky UploadManager (docs/UPLOADER.md
    # Phase 4).
    socket_with_image_uploads = default_socket

    # Gallery fields upload through the sticky UploadManager (docs/UPLOADER.md
    # Phase 4).
    socket_with_gallery_uploads = socket_with_image_uploads

    # File fields upload through the sticky UploadManager (docs/UPLOADER.md
    # Phase 4) — including direct-to-CDN transport when configured.
    socket_with_file_uploads =
      socket_with_gallery_uploads

    # Video fields upload through the sticky UploadManager (docs/UPLOADER.md
    # Phase 5); Mux/Bunny/Cloudflare strategies keep their provider hooks.
    socket_with_video_uploads = socket_with_file_uploads

    # Transformer uploads are now managed by the Transformer component itself
    socket_with_video_uploads
  end

  def handle_event("draft_capture", params, socket), do: {:noreply, Drafts.capture(socket, params)}

  def handle_event("draft_open", _, socket) do
    draft = socket.assigns.draft

    case List.first(draft.candidates) do
      nil -> {:noreply, socket}
      copy -> {:noreply, Drafts.review(socket, copy.id)}
    end
  end

  def handle_event("draft_review", %{"id" => id}, socket), do: {:noreply, Drafts.review(socket, id)}
  def handle_event("draft_dismiss", _, socket), do: {:noreply, Drafts.dismiss(socket)}
  def handle_event("draft_discard", %{"id" => id}, socket), do: {:noreply, Drafts.discard(socket, id)}

  def handle_event("draft_clean", _, socket) do
    socket = Drafts.dismiss(socket)
    schema = socket.assigns.schema

    url =
      if socket.assigns.entry.id,
        do: schema.__admin_route__(:update, [socket.assigns.entry.id]),
        else: schema.__admin_route__(:create, [])

    {:noreply, push_navigate(socket, to: url)}
  end

  def handle_event(event, %{"id" => id}, socket) when event in ["draft_restore", "draft_restore_compatible"] do
    opts = if event == "draft_restore_compatible", do: [accept_conflict: true, compatible_only: true], else: []

    case Drafts.prepare_restore(socket, id, opts) do
      {:error, socket} ->
        {:noreply, socket}

      {:ok, socket, changeset} ->
        draft = %{socket.assigns.draft | open?: socket.assigns.draft.issues != [], status: :ready}

        {:noreply,
         socket
         |> Drafts.put_draft(draft)
         |> apply_restored_changeset(changeset)}
    end
  end

  # The save button and ⌘S push the form's fields rather than submit it, so
  # the focused input keeps the focus and what is typed while the save runs
  # (assets/src/hooks/Form/saveForm.js).
  #
  # The second half of a save carries the token its `b:submit` came with: a
  # token the form no longer holds is a save that already wrote (two quick
  # saves, a button press and ⌘S), and is ignored.
  # ⌘S says to stay with the save, rather than in a push of its own.
  # A heavy entry's blocks are still loading: its tools are disabled, and a
  # shortcut or a click that gets through anyway does nothing. A save would
  # write without the blocks; the rest read the block fields.
  # Closing a preview (recovered after a reconnect) needs no blocks.
  def handle_event(event, _params, %{assigns: %{blocks_ready?: false}} = socket)
      when event in @wait_for_blocks and
             not (event in ~w(open_live_preview toggle_preview_targets) and socket.assigns.live_preview_active?),
      do: {:noreply, socket}

  def handle_event("save_form", %{"stay" => true} = params, socket),
    do: handle_event("save_form", Map.delete(params, "stay"), assign(socket, :save_redirect_target, :self))

  def handle_event("save_form", %{"form" => form, "token" => token}, socket) when is_binary(form) do
    if token == socket.assigns[:save_token],
      do: handle_event("save", Plug.Conn.Query.decode(form), socket),
      else: {:noreply, socket}
  end

  def handle_event("save_form", %{"form" => form}, socket) when is_binary(form),
    do: handle_event("save", Plug.Conn.Query.decode(form), socket)

  def handle_event("commit_tiptap", %{"form" => form, "target" => target}, socket)
      when is_binary(form) and is_list(target),
      do: handle_event("validate", Map.put(Plug.Conn.Query.decode(form), "_target", target), socket)

  def handle_event("validate", params, socket), do: validate(params, socket, false)

  # LiveView's form recovery after a reconnect (`phx-auto-recover` on the main
  # form): the browser's form as it was, which is not an edit. It rebuilds
  # the entry like `validate`, but marks nothing to ship: these may be values
  # the other editors have since replaced, and they send this tab theirs when
  # it loads (`announce_join/1`). A value already received from them stays.
  def handle_event("recover_form", params, socket), do: validate(params, socket, true)

  def handle_event("open_block_upload_folder_browser", params, socket) do
    # upload_name is an opaque correlation key from the UploadTrigger hook —
    # it round-trips as-is through the folder browser and comes back in the
    # `b:block_upload_folder_confirmed` push so the right trigger can match it.
    upload_name = params["upload_name"]
    config_target = params["config_target"] || "default"

    recent_folders =
      case params["recent_folders"] do
        folders when is_list(folders) -> folders
        _ -> []
      end

    file_count = upload_file_count(params["file_count"])

    {video_config, _} = Brando.Uploads.resolve_video_config(params["video_config_target"] || "default")

    send_update(ImagePicker,
      id: "image-picker",
      event: "open_block_upload_browser",
      upload_name: upload_name,
      request_id: params["request_id"],
      file_count: file_count,
      video_count: params["video_count"] || 0,
      video_folder: video_config.upload_path,
      target_label: params["target_label"],
      config_target: config_target,
      initial_folder: params["initial_folder"],
      recent_folders: recent_folders,
      form_id: socket.assigns.id
    )

    # drawer visibility is pushed by the ImagePicker itself (avoids patch race)
    {:noreply, socket}
  end

  def handle_event(event, %{"field" => field} = params, socket)
      when event in ["create_footnote", "open_footnote"] do
    # Resolve both the owning relation and palette from the Blueprint. The
    # client only supplies the field name and marker, never its permissions.
    case Brando.Blueprint.Forms.Footnotes.field(socket.assigns.schema, field) do
      nil ->
        :ok

      config ->
        send_update(BlockField,
          id: "#{socket.assigns.id}-blocks-#{config.blocks}",
          event: event,
          field: config.field,
          params: params
        )
    end

    {:noreply, socket}
  end

  def handle_event("tiptap_link_dialog", params, socket) do
    content_language = socket.assigns.current_user.config.content_language

    TipTapLinkDialog.open(params, content_language)

    {:noreply, socket}
  end

  def handle_event("tiptap_link_result", params, socket) do
    TipTapLinkDialog.receive_result(params)
    {:noreply, socket}
  end

  # Others see the field we are in as locked (`active_field`) until we leave
  # it. Leaving a field ships what we changed; the focus moves first, so a
  # change another editor made to the field we left applies. An image,
  # video or file field is "in" while its drawer is open: the drawer's close
  # sends the blur (without a field), and the inputs inside the drawer, which
  # are not the entry's (`image[alt]`), neither take nor leave the field.
  #
  # Every blur ships: after a reconnect the input still has the focus, but
  # this process never saw it arrive.
  def handle_event("focus", %{"field" => field}, socket) do
    if entry_field?(socket, field),
      do: {:noreply, focus_field(socket, field)},
      else: {:noreply, socket}
  end

  def handle_event("focus", _, socket) do
    {:noreply, socket}
  end

  def handle_event("blur", params, socket) do
    case params["field"] do
      nil ->
        {:noreply, socket |> leave_field() |> ship_all_field_changes()}

      field ->
        if entry_field?(socket, field),
          do: {:noreply, socket |> leave_field(field) |> ship_all_field_changes()},
          else: {:noreply, socket}
    end
  end

  def handle_event("create_permalink_redirect", _, %{assigns: %{pending_permalink_redirect: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("create_permalink_redirect", _, socket) do
    %{redirect: redirect} = socket.assigns.pending_permalink_redirect

    case Brando.Sites.Redirects.create_permalink_redirect(redirect, socket.assigns.current_user) do
      {:ok, _seo} ->
        send(self(), {:toast, gettext("Redirect created")})
        {:noreply, finish_permalink_redirect(socket)}

      {:error, _reason} ->
        {:noreply,
         assign(
           socket,
           :permalink_redirect_error,
           gettext("The entry was saved, but the redirect could not be created. Please try again or continue without it.")
         )}
    end
  end

  def handle_event("skip_permalink_redirect", _, %{assigns: %{pending_permalink_redirect: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("skip_permalink_redirect", _, socket) do
    {:noreply, finish_permalink_redirect(socket)}
  end

  # Someone else saved the entry after the frontend editor loaded it. Saving
  # now would write this editor's copy of the blocks over their save.
  def handle_event("save", _params, %{assigns: %{frontend_edit: %{}, frontend_status: %{stale: %{} = stale}}} = socket) do
    {:noreply,
     socket
     |> assign(:processing, false)
     |> push_event("b:alert", %{
       title: gettext("Not saved"),
       message:
         gettext(
           "%{name} saved this page after you opened the editor. Reload the block to get their changes, then make yours again.",
           name: stale.name
         ),
       type: "error"
     })}
  end

  def handle_event("save", params, %{assigns: %{draft_save_checked?: false}} = socket) do
    socket = Drafts.before_save(socket)

    case Drafts.check_save(socket) do
      {:error, socket} ->
        # The save stops here: the session stops keeping what it read, and
        # the next save collects the blocks again.
        if socket.assigns.entry, do: EditSession.save_failed(socket.assigns.entry)

        {:noreply,
         socket
         |> assign(:processing, false)
         |> assign(:all_blocks_received?, false)
         |> assign(:save_token, nil)
         |> clear_blocks_root_changesets()}

      :ok ->
        {:noreply, result} = handle_event("save", params, assign(socket, :draft_save_checked?, true))
        {:noreply, result |> assign(:draft_save_checked?, false) |> Drafts.save_result()}
    end
  end

  def handle_event("save", _, %{assigns: %{pending_permalink_redirect: pending}} = socket) when not is_nil(pending) do
    {:noreply, socket}
  end

  def handle_event("save", _params, %{assigns: %{editing_image?: true}} = socket) do
    {:noreply,
     push_event(socket, "b:alert", %{
       title: gettext("Error"),
       message:
         gettext(
           "You must close the image drawer before saving this form. You might have changes to an image that has not been processed, which might lead to broken image links. Close the image drawer, allow processing to finish (if any), then try to save again."
         ),
       type: "error"
     })}
  end

  def handle_event("save", _params, %{assigns: %{editing_file?: true}} = socket) do
    {:noreply,
     push_event(socket, "b:alert", %{
       title: gettext("Error"),
       message:
         gettext(
           "You must close the file drawer before saving this form. You might have changes to a file that has not been processed, which might lead to broken links. Close the file drawer, allow processing to finish (if any), then try to save again."
         ),
       type: "error"
     })}
  end

  def handle_event(
        "save",
        params,
        %{
          assigns: %{
            has_blocks?: true,
            all_blocks_received?: true,
            all_transformers_received?: true
          }
        } = socket
      ) do
    socket = assign(socket, :save_token, nil)
    schema = socket.assigns.schema
    entry = socket.assigns.entry
    current_user = socket.assigns.current_user
    singular = socket.assigns.singular
    form_blueprint = socket.assigns.form_blueprint
    save_redirect_target = socket.assigns.save_redirect_target
    block_changesets = socket.assigns.block_changesets
    block_map = socket.assigns.block_map

    entry_params = Map.get(params, singular)
    entry_or_default = entry || struct(schema)

    changeset =
      socket
      |> cast_entry_params(entry_or_default, entry_params)
      |> Brando.Utils.set_action()
      |> Brando.Trait.run_trait_before_save_callbacks(schema, current_user)

    singular = schema.__naming__().singular
    context = schema.__modules__().context
    mutation_type = (get_field(changeset, :id) && :update) || :create

    send(self(), {:progress_popup, "Associating block fields..."})

    # The blocks join the entry only here, after its changeset ran, so the
    # creator trait is asked again whether this save edited anything — before
    # rendering, which would otherwise read as an edit.
    new_changeset =
      block_changesets
      |> assoc_all_block_fields(changeset)
      |> then(&assoc_all_transformer_fields(&1, socket.assigns.transformer_changesets))
      |> Brando.Trait.Creator.stamp_if_edited(schema, current_user)

    entry_for_blocks = build_entry_for_blocks(new_changeset, block_map)

    send(self(), {:progress_popup, "Rendering blocks for entry..."})

    rendered_changeset =
      render_blocks_for_entry(
        block_map,
        new_changeset,
        entry_for_blocks
      )

    send(self(), {:progress_popup, "Saving entry..."})

    socket = Translation.put_acknowledged(socket, params)
    if FrontendEditor.frontend?(socket), do: FrontendEditor.saving(socket)

    save = %{
      schema: schema,
      current_user: current_user,
      form_blueprint: form_blueprint,
      save_redirect_target: save_redirect_target,
      mutation_type: mutation_type,
      entry_or_default: entry_or_default,
      changeset: rendered_changeset
    }

    case save_entry(socket, context, mutation_type, singular, rendered_changeset) do
      {:ok, entry} -> saved_entry_with_blocks(socket, entry, save)
      {:error, {:source_controlled, paths}} -> source_controlled_save_with_blocks(socket, paths)
      {:error, %Changeset{} = changeset} -> failed_save_with_blocks(socket, changeset, save)
    end
  end

  def handle_event("save", _params, %{assigns: %{has_blocks?: true}} = socket) do
    if collecting_save?(socket), do: {:noreply, socket}, else: collect_for_save(socket)
  end

  def handle_event(
        "save",
        _params,
        %{assigns: %{has_transformers?: true, all_transformers_received?: false}} = socket
      ) do
    # no blocks, but has transformers that haven't been collected yet
    fetch_transformer_data(socket, :save)
    send(self(), {:progress_popup, "Saving..."})

    {:noreply,
     socket
     |> ship_all_field_changes()
     |> assign(:processing, true)}
  end

  def handle_event(
        "save",
        params,
        %{assigns: %{has_blocks?: false, all_transformers_received?: true}} = socket
      ) do
    socket = ship_all_field_changes(socket)
    schema = socket.assigns.schema
    entry = socket.assigns.entry
    current_user = socket.assigns.current_user
    singular = socket.assigns.singular
    form_blueprint = socket.assigns.form_blueprint
    save_redirect_target = socket.assigns.save_redirect_target

    entry_params = Map.get(params, singular)
    entry_or_default = entry || struct(schema)

    changeset =
      socket
      |> cast_entry_params(entry_or_default, entry_params)
      |> Brando.Utils.set_action()
      |> Brando.Trait.run_trait_before_save_callbacks(schema, current_user)
      |> assoc_all_transformer_fields(socket.assigns.transformer_changesets)

    singular = schema.__naming__().singular
    context = schema.__modules__().context

    mutation_type = (get_field(changeset, :id) && :update) || :create

    socket = Translation.put_acknowledged(socket, params)

    save = %{
      schema: schema,
      current_user: current_user,
      form_blueprint: form_blueprint,
      save_redirect_target: save_redirect_target,
      mutation_type: mutation_type,
      entry_or_default: entry_or_default,
      changeset: changeset
    }

    case save_entry(socket, context, mutation_type, singular, changeset) do
      {:ok, entry} ->
        saved_entry(socket, entry, save)

      {:error, %Changeset{} = changeset} ->
        require Logger
        Logger.error(inspect(changeset, pretty: true))

        # A rejected save leaves the editor on the form by definition, so this
        # path always renders the button — and it was stuck here too. Observed
        # in production: a Project failing its `one_of` listing_image/
        # listing_video constraint showed its errors under a spinner that never
        # stopped, which reads as "saving is broken" rather than "fix these
        # fields".
        {:noreply,
         socket
         |> assign(:processing, false)
         |> assign(:minor_save?, false)
         |> put_form(to_form(changeset, []))
         |> push_errors(changeset, form_blueprint, schema)}

      # A synchronized translation that changed what its source controls. The
      # block-editor clause above refuses it the same way; without this an
      # entry without blocks crashed the form instead.
      {:error, {:source_controlled, paths}} ->
        {:noreply,
         socket
         |> assign(:processing, false)
         |> source_controlled_error(paths)}
    end
  end

  def handle_event(
        "duplicate_image",
        %{"image_id" => image_id},
        %{assigns: %{singular: singular, current_user: current_user}} = socket
      ) do
    {:ok, image} = Images.duplicate_image(image_id, current_user)

    send_update(__MODULE__,
      id: "#{singular}_form",
      action: :update_edit_image,
      image: image
    )

    send(self(), {:toast, gettext("Image duplicated")})

    {:noreply, socket}
  end

  # An image's own form: the entry is the image, so the editor works on it
  # directly rather than on an image field of the entry.
  def handle_event("open_own_image_editor", _, %{assigns: %{entry: %Images.Image{} = image}} = socket) do
    {:noreply,
     socket
     |> assign(:edit_image, %{path: [], field: nil, relation_field: nil, image: image, id: image.id, own: true})
     |> assign(:editing_image?, true)
     |> assign(:image_changeset, change(image))
     # `from_block`: a new copy goes through the form's own editor upload
     # (`handle_image_editor_upload_progress/3`), as from a block. The other
     # route fills the image drawer's field upload, and this form has no field.
     |> push_event("b:image_editor:init", Map.put(image_editor_payload(image), :from_block, true))}
  end

  def handle_event("open_own_image_editor", _, socket), do: {:noreply, socket}

  def handle_event("open_image_editor", %{"image_id" => _image_id}, socket) do
    image = socket.assigns.edit_image.image

    {:noreply, push_event(socket, "b:image_editor:init", image_editor_payload(image))}
  end

  def handle_event(
        "image_editor_save",
        %{"mode" => "replace", "focal_x" => _x, "focal_y" => _y} = params,
        %{assigns: %{current_user: current_user}} = socket
      ) do
    edit_image = socket.assigns.edit_image
    block_target = Map.get(edit_image, :block_target)

    updated_image =
      if params["crop_applied"] do
        cropped_editor_image(params, edit_image)
      else
        refocused_editor_image(params, edit_image, current_user)
      end

    # Subscribe to PubSub BEFORE queuing processing so inline Oban
    # broadcasts aren't missed. Always subscribe — both block and non-block
    # paths need processing notifications to update their UI.
    Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:image:#{updated_image.id}")

    if block_target do
      send(self(), {:register_pending_block_image, updated_image.id, block_target})
    end

    # For non-crop case, queue processing after subscribing.
    unless params["crop_applied"] do
      # Silent: the editor and drawer show the image processing themselves; the
      # old top-of-page progress bar would be a second, older indicator.
      Images.Processing.queue_processing(updated_image, current_user, [], silent: true)
    end

    # For crop_applied, processing was already queued by the controller.
    # With Oban inline testing, the broadcast was sent before we subscribed.
    # Re-fetch to get the latest state (may already be processed).
    updated_image =
      if params["crop_applied"] do
        {:ok, fresh} = Images.get_image(updated_image.id)
        fresh
      else
        updated_image
      end

    send(self(), {:toast, gettext("Changes saved. Image is reprocessing.")})

    if block_target do
      # Block path: update image drawer; PubSub hooks handle the block component.
      singular = socket.assigns.singular

      send_update(__MODULE__,
        id: "#{singular}_form",
        action: :update_edit_image,
        image: updated_image
      )

      {:noreply, socket}
    else
      {:noreply, show_saved_editor_image(socket, edit_image, updated_image)}
    end
  end

  def handle_event(
        "image_editor_save",
        %{"mode" => "new_copy", "focal_x" => x, "focal_y" => y} = params,
        socket
      ) do
    # Store focal and config_target so they can be applied once the upload completes.
    # Used by both block and non-block paths.
    config_target = Map.get(params, "config_target", "default")

    {:noreply,
     socket
     |> assign(:image_editor_focal, %{x: x, y: y})
     |> assign(:image_editor_config_target, config_target)}
  end

  def handle_event(
        "reset_video_field",
        _,
        %{assigns: %{form: form, edit_video: edit_video, entry: entry, singular: singular}} = socket
      ) do
    relation_key = relation_field_key(edit_video.relation_field, edit_video.field)
    full_path = edit_video.path ++ [relation_key]

    changeset =
      form.source
      |> EctoNestedChangeset.update_at(full_path, fn _ -> nil end)
      |> put_asset_in_data(edit_video.path, edit_video.field, nil)

    {:noreply,
     socket
     |> assign(:entry, Map.put(entry, edit_video.field, nil))
     |> assign(:video_changeset, nil)
     |> assign(:editing_video?, false)
     |> assign(:edit_video, %{edit_video | video: nil})
     |> put_local_form(to_form(changeset, []))
     |> own_asset(edit_video.path, relation_key, :id)
     |> assign_drawer_recovery_state()
     |> push_event("b:validate", %{target: "#{singular}[#{relation_key}]", value: ""})}
  end

  def handle_event("browse_video_thumbnail", _, socket) do
    video = socket.assigns.edit_video.video

    send_update(ImagePicker,
      id: "image-picker",
      config_target: Brando.Assets.ConfigTarget.serialize({"image", Brando.Videos.Video, :thumbnail}),
      event_target: socket.assigns.myself,
      multi: false,
      selected_images: if(video && video.thumbnail_id, do: [video.thumbnail_id], else: []),
      form_id: socket.assigns.id
    )

    {:noreply, socket}
  end

  # The image picker's pick, when the video drawer opened it for a thumbnail
  # (`browse_video_thumbnail`) — the only time the form is its target. Saved
  # at once, like `reset_video_thumbnail`.
  def handle_event("select_image", %{"id" => image_id}, socket) do
    edit_video = socket.assigns.edit_video

    with %{video: %{id: video_id} = video} when not is_nil(video_id) <- edit_video,
         {:ok, image} <- Brando.Images.get_image(image_id),
         {:ok, updated_video} <-
           video
           |> change(%{thumbnail_id: image.id})
           |> Map.put(:action, :update)
           |> Brando.Videos.update_video(socket.assigns.current_user) do
      send_update(ImagePicker, id: "image-picker", selected_images: [image.id])
      {:noreply, assign(socket, :edit_video, %{edit_video | video: %{updated_video | thumbnail: image}})}
    else
      _ ->
        send(self(), {:toast, gettext("Could not set video thumbnail")})
        {:noreply, socket}
    end
  end

  def handle_event("reset_video_thumbnail", _, socket) do
    edit_video = socket.assigns.edit_video

    case edit_video.video do
      # Persist immediately — save_video rebuilds its changeset from the
      # struct, so an in-memory-only reset would silently never reach the DB.
      %{id: id} = video when not is_nil(id) ->
        changeset =
          video
          |> change(%{thumbnail_id: nil})
          |> Map.put(:action, :update)

        case Brando.Videos.update_video(changeset, socket.assigns.current_user) do
          {:ok, updated_video} ->
            updated_video = %{updated_video | thumbnail: nil}
            {:noreply, assign(socket, :edit_video, %{edit_video | video: updated_video})}

          {:error, %Changeset{} = failed_changeset} ->
            require Logger
            Logger.error("==> reset_video_thumbnail failed: #{inspect(failed_changeset.errors)}")
            send(self(), {:toast, gettext("Could not reset video thumbnail")})
            {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("change_preview_target", %{"target" => target}, socket) do
    {:noreply, assign(socket, :live_preview_target, target)}
  end

  def handle_event(
        "reset_file_field",
        _,
        %{assigns: %{form: form, edit_file: edit_file, entry: entry, singular: singular}} = socket
      ) do
    changeset = form.source
    relation_key = relation_field_key(edit_file.relation_field, edit_file.field)
    full_path = edit_file.path ++ [relation_key]

    updated_changeset =
      changeset
      |> EctoNestedChangeset.update_at(full_path, fn _ -> nil end)
      |> put_asset_in_data(edit_file.path, edit_file.field, nil)

    updated_edit_file = Map.put(edit_file, :file, nil)

    {:noreply,
     socket
     |> assign(:entry, Map.put(entry, edit_file.field, nil))
     |> assign(:file_changeset, nil)
     # `reset_file_field/2` closes the drawer (`toggle_drawer`), so the flag has
     # to come down with it — leaving it set stranded the main save behind
     # "close the file drawer before saving" with no drawer to close.
     |> assign(:editing_file?, false)
     |> assign(:edit_file, updated_edit_file)
     |> put_local_form(to_form(updated_changeset, []))
     |> own_asset(edit_file.path, relation_key, :id)
     |> assign_drawer_recovery_state()
     |> push_event("b:validate", %{
       target: "#{singular}[#{relation_key}]",
       value: ""
     })}
  end

  def handle_event(
        "reset_image_field",
        _,
        %{assigns: %{form: form, edit_image: edit_image, entry: entry, singular: singular}} =
          socket
      ) do
    changeset = form.source
    relation_key = relation_field_key(edit_image.relation_field, edit_image.field)
    full_path = edit_image.path ++ [relation_key]

    updated_changeset =
      changeset
      |> EctoNestedChangeset.update_at(full_path, fn _ -> nil end)
      |> put_asset_in_data(edit_image.path, edit_image.field, nil)

    updated_edit_image = Map.put(edit_image, :image, nil)

    {:noreply,
     socket
     |> assign(:entry, Map.put(entry, edit_image.field, nil))
     |> assign(:image_changeset, nil)
     # Same as reset_file_field above — this closes the image drawer, so the
     # guard flag must come down or the entry can never be saved again.
     |> assign(:editing_image?, false)
     |> assign(:edit_image, updated_edit_image)
     |> put_local_form(to_form(updated_changeset, []))
     |> own_asset(edit_image.path, relation_key, :id)
     |> assign_drawer_recovery_state()
     |> push_event("b:validate", %{
       target: "#{singular}[#{relation_key}]",
       value: ""
     })}
  end

  def handle_event("validate_file", %{"file" => file_params}, socket) do
    file = socket.assigns.edit_file.file || %Brando.Files.File{}

    file_changeset =
      file
      |> Brando.Files.File.changeset(file_params, socket.assigns.current_user)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :file_changeset, file_changeset)}
  end

  def handle_event("validate_file", _, socket) do
    {:noreply, socket}
  end

  # Write with AI in a top-level rich text field's toolbar. The reply goes
  # back to the editor as a suggestion; nothing here writes the field.
  def handle_event("tiptap_ai_generate", params, socket) do
    with {:ok, field} <- safe_to_existing_atom(params["field_key"]),
         true <- is_binary(params["field_name"]),
         %BlueprintForms.Input{type: :rich_text, opts: opts} <-
           BlueprintForms.get_field(field, socket.assigns.form_blueprint),
         config = RichTextAI.input_config(opts || []),
         true <- RichTextAI.enabled?(config),
         false <- FieldActions.locked?(opts, socket.assigns.current_user),
         {:ok, _path, ^field, _segments} <- parse_form_field_name(params["field_name"], socket.assigns.singular),
         {:ok, _prompt} <- RichTextAI.prompt(nil, params) do
      request = {:tiptap, params["tiptap_id"], params["request_id"]}

      {:noreply,
       with_ai_blocks(socket, request, config[:from] || [], fn
         socket, {:ok, blocks} ->
           RichTextAI.start(
             socket,
             params,
             write_with_ai_prompt(socket, config, params, blocks),
             RichTextAI.ai_opts(config)
           )

         socket, :unanswered ->
           push_event(socket, "b:tiptap:ai:#{params["tiptap_id"]}", %{request_id: params["request_id"], error: true})
       end)}
    else
      _ ->
        {:noreply,
         push_event(socket, "b:tiptap:ai:#{params["tiptap_id"]}", %{request_id: params["request_id"], error: true})}
    end
  end

  def handle_event("tiptap_ai_cancel", params, socket) do
    {:noreply, socket |> cancel_ai_blocks(params) |> RichTextAI.cancel(params)}
  end

  # An AI action on the field (`ai_actions:`, a deprecated `ai:`, or a meta
  # field's site prompt): the prompt is built here, from the unsaved form, and
  # the field's suggestion panel asks the model and shows the reply until the
  # editor accepts or discards it.
  def handle_event("run_field_action", %{"field" => field, "action" => action} = params, socket) do
    with {:ok, field_atom} <- safe_to_existing_atom(field),
         {:ok, action_atom} <- safe_to_existing_atom(action),
         {actions, type, opts} <- field_ai_actions(socket, field_atom),
         false <- FieldActions.locked?(opts, socket.assigns.current_user),
         %BlueprintForms.AIAction{} = ai_action <- Enum.find(actions, &(&1.name == action_atom)),
         true <- FieldAction.available?(ai_action) do
      panel = field_action_panel(socket, field_atom, params["panel"])

      {:noreply,
       with_ai_blocks(socket, {:field_action, panel}, ai_action.from, fn
         socket, {:ok, blocks} ->
           send_update(FieldActions, id: panel, run: field_action_run(socket, field_atom, ai_action, type, blocks))
           socket

         socket, :unanswered ->
           run = field_action_run(socket, field_atom, ai_action, type, nil)
           send_update(FieldActions, id: panel, run: %{run | build: fn -> {:error, :blocks_unanswered} end})
           socket
       end)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(
        "save_file",
        %{"file" => file_params},
        %{
          assigns: %{
            form: form,
            entry: entry,
            schema: schema,
            singular: singular,
            edit_file: %{file: file, path: path, field: field, relation_field: relation_field} = edit_file,
            current_user: current_user
          }
        } = socket
      ) do
    entry_or_default = entry || struct(schema)

    validated_changeset =
      file
      |> Brando.Files.File.changeset(file_params, current_user)
      |> Map.put(:action, :update)
      |> Brando.Trait.run_trait_before_save_callbacks(
        Brando.Files.File,
        current_user
      )

    {:ok, updated_file} = Brando.Files.update_file(validated_changeset, current_user)

    Brando.Blueprint.AfterSave.run(
      Brando.Files.File,
      updated_file,
      validated_changeset,
      current_user
    )

    edit_file = Map.put(edit_file, :file, updated_file)
    relation_key = relation_field_key(relation_field, field)
    full_path = path ++ [relation_key]

    updated_changeset =
      form.source
      |> apply_changes()
      |> change()
      |> EctoNestedChangeset.update_at(full_path, fn _ -> file.id end)

    updated_entry = Map.put(entry_or_default, field, updated_file)

    # this is only for fresh uploads.
    if !updated_file.cdn && Brando.CDN.enabled?(Brando.Files) do
      # TODO __ FIGURE OUT FULL_PATH
      full_field_path = []
      Brando.CDN.queue_upload(updated_file, current_user, full_field_path)
    end

    {:noreply,
     socket
     # ship BEFORE the re-bake below — apply_changes/change() bakes pending
     # changes into data, leaving nothing for ship_all_field_changes to see
     |> ship_all_field_changes()
     |> assign(:entry, updated_entry)
     |> put_form(to_form(updated_changeset, []))
     |> assign(:file_changeset, validated_changeset)
     |> assign(:editing_file?, false)
     |> assign(:edit_file, edit_file)
     |> assign_drawer_recovery_state()
     |> push_event("b:validate", %{
       target: "#{singular}[#{relation_key}]",
       value: file.id
     })}
  end

  # without file in params
  def handle_event("save_file", _, socket) do
    {:noreply, assign_drawer_recovery_state(socket)}
  end

  def handle_event("validate_image", %{"image" => image_params}, socket) do
    # Cast rather than change: the fields are language → text maps, and a
    # plain string (older recovery state) must land under the default language.
    image_changeset =
      socket.assigns.edit_image.image
      |> cast(Map.take(image_params, ["title", "credits", "alt"]), [:title, :credits, :alt])
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :image_changeset, image_changeset)}
  end

  def handle_event("validate_image", _, socket) do
    {:noreply, socket}
  end

  # The image form's own "Suggest alt text" (`suggest_alt: true` on its alt
  # field) and the image drawer's: the reply is a suggestion in the field's
  # panel (`AltTextSuggestion`), which the button names.
  def handle_event("suggest_entry_alt_text", params, %{assigns: %{entry: %Images.Image{id: id}}} = socket) do
    case alt_suggestion_panel(params) do
      nil ->
        {:noreply, socket}

      panel ->
        {:noreply,
         socket
         |> assign(:alt_text_suggesting, true)
         |> start_alt_suggestion(
           :suggest_entry_alt_text,
           id,
           panel,
           Changeset.get_field(socket.assigns.form.source, :alt)
         )}
    end
  end

  def handle_event("suggest_alt_text", params, %{assigns: %{edit_image: %{image: %{id: id}}}} = socket) do
    case alt_suggestion_panel(params) do
      nil ->
        {:noreply, socket}

      panel ->
        {:noreply,
         socket
         |> assign(:alt_text_suggesting, true)
         |> start_alt_suggestion(:suggest_alt_text, id, panel, Changeset.get_field(socket.assigns.image_changeset, :alt))}
    end
  end

  # When opened from a block, edit_image has no path/field/relation_field.
  # Create a new image record and notify the block component to update its reference.
  def handle_event(
        "save_image",
        %{"image" => image_params},
        %{
          assigns: %{
            edit_image: %{field: nil, image: original_image, block_target: block_target},
            current_user: current_user
          }
        } = socket
      ) do
    new_image_params = Map.put(image_params, "config_target", original_image.config_target)

    validated_changeset =
      %Images.Image{}
      |> Images.Image.changeset(new_image_params, current_user)
      |> Map.put(:action, :insert)
      |> Brando.Trait.run_trait_before_save_callbacks(
        Images.Image,
        current_user
      )

    {:ok, new_image} = Images.create_image(validated_changeset, current_user)

    Brando.Blueprint.AfterSave.run(
      Images.Image,
      new_image,
      validated_changeset,
      current_user
    )

    if new_image.status !== :processed do
      Images.Processing.queue_processing(new_image, current_user, [], silent: true)
    end

    if block_target do
      {module, id} = block_target
      old_image_id = Map.get(socket.assigns.edit_image, :old_image_id)

      send_update(module,
        id: id,
        event: "image_editor_new_copy",
        new_image: new_image,
        old_image_id: old_image_id
      )
    end

    send(self(), {:toast, gettext("New image created.")})

    {:noreply,
     socket
     |> assign(:editing_image?, false)
     |> assign_drawer_recovery_state()}
  end

  def handle_event(
        "save_image",
        %{"image" => image_params},
        %{
          assigns: %{
            form: form,
            entry: entry,
            schema: schema,
            singular: singular,
            edit_image:
              %{image: image, path: path, field: field, relation_field: relation_field} =
                edit_image,
            current_user: current_user
          }
        } = socket
      ) do
    entry_or_default = entry || struct(schema)

    validated_changeset =
      image
      |> Images.Image.changeset(image_params, current_user)
      |> Map.put(:action, :update)
      |> Brando.Trait.run_trait_before_save_callbacks(
        Images.Image,
        current_user
      )

    {:ok, _} = Images.update_image(validated_changeset, current_user)

    # Reload from DB — the Oban processing job may have updated
    # status/sizes since the drawer was opened.
    {:ok, updated_image} = Images.get_image(image.id)

    Brando.Blueprint.AfterSave.run(
      Images.Image,
      updated_image,
      validated_changeset,
      current_user
    )

    edit_image = Map.put(edit_image, :image, updated_image)
    relation_key = relation_field_key(relation_field, field)
    relation_full_path = path ++ [relation_key]
    field_full_path = path ++ [field]

    updated_changeset =
      form.source
      |> apply_changes()
      |> change()
      |> EctoNestedChangeset.update_at(relation_full_path, fn _ -> image.id end)

    entrys_current_image = Brando.Utils.try_path(entry_or_default, field_full_path)
    access_field_full_path = Brando.Utils.build_access_path(field_full_path)

    updated_entry =
      if loaded_image?(entrys_current_image) && entrys_current_image.id == image.id &&
           updated_image.status == :processed do
        # the image has already been marked as processed, do not
        # update the image but merge in title, credits and alt text
        merged_image =
          Map.merge(entrys_current_image, Map.take(updated_image, [:title, :credits, :alt]))

        put_in(entry_or_default, access_field_full_path, merged_image)
      else
        put_in(entry_or_default, access_field_full_path, updated_image)
      end

    # Subscribe parent live view to changes to this image
    Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:image:#{image.id}")

    if requeue_processing?(validated_changeset, updated_image) do
      Images.Processing.queue_processing(updated_image, current_user, field_full_path, silent: true)
    end

    target_field_name =
      Enum.join([singular | Enum.map(relation_full_path, &"[#{to_string(&1)}]")])

    {:noreply,
     socket
     # ship BEFORE the re-bake below — apply_changes/change() bakes pending
     # changes into data, leaving nothing for ship_all_field_changes to see
     |> ship_all_field_changes()
     |> assign(:entry, updated_entry)
     |> put_form(to_form(updated_changeset, []))
     |> assign(:image_changeset, validated_changeset)
     |> assign(:edit_image, edit_image)
     |> assign(:editing_image?, false)
     |> assign_drawer_recovery_state()
     |> push_event("b:validate", %{
       target: target_field_name,
       value: image.id
     })}
  end

  # without image in params
  def handle_event("save_image", params, socket) do
    require Logger
    Logger.warning(">>> save_image called WITHOUT image params. params=#{inspect(params)}")

    {:noreply,
     socket
     |> assign(:editing_image?, false)
     |> ship_all_field_changes()
     |> assign_drawer_recovery_state()}
  end

  def handle_event("validate_video", %{"video" => video_params}, socket) do
    video = socket.assigns.edit_video.video || %Brando.Videos.Video{}

    video_changeset =
      video
      |> Brando.Videos.Video.changeset(video_params, socket.assigns.current_user)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :video_changeset, video_changeset)}
  end

  def handle_event("validate_video", _, socket) do
    {:noreply, socket}
  end

  # The drawer's ratio presets. They write the same `aspect_ratio` its custom
  # input does, which then re-renders with the preset, so closing the drawer
  # submits it like any typed value.
  def handle_event(
        "set_video_aspect_ratio",
        %{"value" => value},
        %{assigns: %{video_changeset: %Changeset{}}} = socket
      ) do
    value = if value in [nil, ""], do: nil, else: value
    {:noreply, update(socket, :video_changeset, &Changeset.put_change(&1, :aspect_ratio, value))}
  end

  def handle_event("set_video_aspect_ratio", _, socket), do: {:noreply, socket}

  # The drawer's preview reports the size of the file it loaded, so a video
  # without stored dimensions still shows its shape. Display only; nothing is
  # saved.
  def handle_event(
        "video_preview_dimensions",
        %{"width" => w, "height" => h},
        %{assigns: %{edit_video: %{} = edit_video}} = socket
      )
      when is_integer(w) and is_integer(h) and w > 0 and h > 0 do
    {:noreply, assign(socket, :edit_video, Map.put(edit_video, :preview_dimensions, {w, h}))}
  end

  def handle_event("video_preview_dimensions", _, socket), do: {:noreply, socket}

  def handle_event("save_video", %{"video" => video_params} = params, socket) do
    if external_video_params?(video_params) and not external_video_urls_allowed?(socket) do
      send(self(), {:toast, gettext("External video URLs are disabled for this field")})
      {:noreply, socket}
    else
      handle_event("save_video_authorized", params, assign(socket, :video_save_authorized?, true))
    end
  end

  # The drawer can be saved before there is anything to save: opened on a field
  # that has no video, nothing picked and nothing uploaded, and the editor hits
  # save. `edit_video.video` is nil then, and the clause below binds it straight
  # into `Brando.Videos.Video.changeset/3` — where `ChangesetRunner.run/1` reads
  # `schema.__struct__` on nil, raises KeyError, and takes the entry form
  # process down with every unsaved change in it. Seen in production as
  # `video[type]=upload` with an empty drawer.
  #
  # Defaulting to `%Video{}` would not do: `update_video/2` further down expects
  # a persisted record, so a struct with no id only moves the failure. There is
  # genuinely nothing to persist here, so close the drawer — which is exactly
  # what the "no video in params" clause below already does.
  #
  # `validate_video/2` has guarded this since it was written (`edit_video.video
  # || %Video{}`); it was only ever the save path that did not.
  def handle_event(
        "save_video_authorized",
        %{"video" => _video_params},
        %{assigns: %{edit_video: %{video: nil}, video_save_authorized?: true}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:video_save_authorized?, false)
     |> assign(:editing_video?, false)
     |> assign_drawer_recovery_state()}
  end

  def handle_event(
        "save_video_authorized",
        %{"video" => video_params},
        %{
          assigns: %{
            form: form,
            entry: entry,
            schema: schema,
            singular: singular,
            edit_video:
              %{video: video, path: path, field: field, relation_field: relation_field} =
                edit_video,
            current_user: current_user,
            video_save_authorized?: true
          }
        } = socket
      ) do
    socket = assign(socket, :video_save_authorized?, false)
    entry_or_default = entry || struct(schema)

    validated_changeset =
      video
      |> Brando.Videos.Video.changeset(video_params, current_user)
      |> Map.put(:action, :update)
      |> Brando.Trait.run_trait_before_save_callbacks(
        Brando.Videos.Video,
        current_user
      )

    {:ok, updated_video} = Brando.Videos.update_video(validated_changeset, current_user)

    Brando.Blueprint.AfterSave.run(
      Brando.Videos.Video,
      updated_video,
      validated_changeset,
      current_user
    )

    edit_video = Map.put(edit_video, :video, updated_video)
    relation_key = relation_field_key(relation_field, field)
    relation_full_path = path ++ [relation_key]
    field_full_path = path ++ [field]

    updated_changeset =
      form.source
      |> apply_changes()
      |> change()
      |> EctoNestedChangeset.update_at(relation_full_path, fn _ -> video.id end)

    access_field_full_path = Brando.Utils.build_access_path(field_full_path)
    updated_entry = put_in(entry_or_default, access_field_full_path, updated_video)

    target_field_name =
      Enum.join([singular | Enum.map(relation_full_path, &"[#{to_string(&1)}]")])

    {:noreply,
     socket
     # ship BEFORE the re-bake below — apply_changes/change() bakes pending
     # changes into data, leaving nothing for ship_all_field_changes to see
     |> ship_all_field_changes()
     |> assign(:entry, updated_entry)
     |> put_form(to_form(updated_changeset, []))
     |> assign(:video_changeset, validated_changeset)
     |> assign(:edit_video, edit_video)
     |> assign(:editing_video?, false)
     |> assign_drawer_recovery_state()
     |> push_event("b:validate", %{
       target: target_field_name,
       value: video.id
     })}
  end

  # without video in params
  def handle_event("save_video", _, socket) do
    {:noreply,
     socket
     |> assign(:editing_video?, false)
     |> assign_drawer_recovery_state()}
  end

  def handle_event("save_video_authorized", _params, socket), do: {:noreply, socket}

  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("recover_drawer_state", %{"drawer" => drawer_params}, socket) do
    case drawer_params do
      %{"type" => "image", "resource_id" => id} when id != "" ->
        restore_image_drawer(socket, drawer_params)

      %{"type" => "video", "resource_id" => id} when id != "" ->
        restore_video_drawer(socket, drawer_params)

      %{"type" => "file", "resource_id" => id} when id != "" ->
        restore_file_drawer(socket, drawer_params)

      # A drawer was open but carried no resource id — recovery cannot rebuild
      # it, and any edits inside it are gone. Rare, but it used to be entirely
      # invisible; the clause below is the ordinary "no drawer was open" case
      # and is correctly silent.
      %{"type" => type} when type not in [nil, ""] ->
        require Logger

        Logger.warning(
          "Form (#{socket.assigns.id}) could not recover an open #{type} drawer: " <>
            "no resource_id in the recovery params. In-progress edits in that drawer are lost."
        )

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("share_link", _, socket) do
    send(self(), {:toast, gettext("Gathering blocks for sharing...")})
    socket = assign(socket, :sharing_preview?, true)
    {:noreply, fetch_root_blocks(socket, :share, 500)}
  end

  def handle_event("store_revision", _, socket) do
    send(self(), {:toast, gettext("Saving a revision...")})

    socket =
      socket
      |> clear_blocks_root_changesets()
      |> reset_transformer_changesets()

    fetch_transformer_data(socket, :store_revision)

    {:noreply, fetch_root_blocks(socket, :store_revision, 150)}
  end

  def handle_event("toggle_preview_targets", _, socket) do
    {:noreply, assign(socket, :live_preview_menu_open?, !socket.assigns.live_preview_menu_open?)}
  end

  def handle_event("close_preview_targets", _, socket) do
    {:noreply, assign(socket, :live_preview_menu_open?, false)}
  end

  def handle_event("select_preview_target", %{"name" => name}, socket) do
    case Enum.find(socket.assigns.live_preview_targets, &(to_string(&1.name) == name)) do
      nil ->
        {:noreply, socket}

      target ->
        socket = assign(socket, :live_preview_menu_open?, false)

        if socket.assigns.live_preview_active? do
          socket = socket |> Preview.cancel() |> assign(:pending_live_preview_target, target.name)
          {:noreply, fetch_root_blocks(socket, :live_preview_target, 0)}
        else
          socket = assign(socket, :live_preview_schema_target, target.name)
          handle_event("open_live_preview", %{}, socket)
        end
    end
  end

  # restore live preview after reconnect via form recovery
  def handle_event(
        "recover_live_preview_state",
        %{"live_preview" => %{"cache_key" => cache_key}},
        socket
      )
      when cache_key != "" do
    if Brando.Authorization.Preview.authorize_write(cache_key, socket.assigns.form.source) == :ok do
      schema = socket.assigns.schema

      socket =
        socket
        |> assign(:live_preview_active?, true)
        |> assign(:live_preview_cache_key, cache_key)
        |> assign(:live_preview_schema_target, LivePreview.target_name(cache_key))
        |> assign_entry_fields_demanding_live_preview_rerender(schema)
        |> assign_entry_fields_demanding_live_preview_reassign(schema)
        |> push_event("b:live_preview", %{cache_key: cache_key})
        |> push_event("js-exec", %{to: "#sidebar", attr: "data-js-hide"})

      # Do not render the preview here. Recovery is two independent
      # `phx-auto-recover` forms — this one and the main form's `validate` — and
      # LiveView orders them however it likes; measured locally they land about a
      # millisecond apart. `validate` is what rebuilds the entry from the
      # recovered params, so rendering from this handler produces an empty page
      # whenever it happens to go first.
      #
      # Instead both sides mark their half done and whichever finishes last does
      # the render. See `maybe_finish_live_preview_recovery/1`.
      socket
      |> assign(:live_preview_recovery_pending?, true)
      |> maybe_finish_live_preview_recovery()
      |> then(&{:noreply, &1})
    else
      {:noreply, socket}
    end
  end

  def handle_event("recover_live_preview_state", _params, socket) do
    {:noreply, socket}
  end

  # manually re-ship a fresh live preview while the drawer stays open
  def handle_event("refresh_live_preview", _, %{assigns: %{live_preview_active?: true}} = socket) do
    send(self(), {:toast, gettext("Refreshing Live Preview...")})
    {:noreply, maybe_full_rerender_live_preview(socket, true)}
  end

  # close live_preview
  def handle_event("open_live_preview", _, %{assigns: %{live_preview_active?: true}} = socket) do
    LivePreview.cleanup_cache(socket.assigns.live_preview_cache_key)

    socket
    |> Preview.cancel()
    |> assign(:live_preview_active?, false)
    |> assign(:live_preview_menu_open?, false)
    |> assign(:pending_live_preview_target, nil)
    |> assign(:live_preview_cache_key, nil)
    |> push_event("js-exec", %{to: "#sidebar", attr: "data-js-show"})
    |> then(&{:noreply, &1})
  end

  # try to open live_preview for schema without blocks
  def handle_event(
        "open_live_preview",
        _,
        %{assigns: %{has_blocks?: false, live_preview_active?: false}} = socket
      ) do
    send(self(), {:toast, gettext("Starting Live Preview...")})

    # Send update to self (the Form component) to trigger live preview initialization
    send_update_after(
      __MODULE__,
      [id: socket.assigns.id, action: :event_tag_received, tag: :live_preview],
      100
    )

    socket =
      socket
      |> push_event("js-exec", %{to: "#sidebar", attr: "data-js-hide"})

    {:noreply, socket}
  end

  # try to open live_preview, but blocks are not ready.
  def handle_event("open_live_preview", _, %{assigns: %{live_preview_ready?: false}} = socket) do
    send(self(), {:toast, gettext("Starting Live Preview — fetching initial render...")})
    # Same margin as save for edits still in flight; blocks are materialized
    # from the op store, so there is nothing else to wait for.
    socket = fetch_root_blocks(socket, :live_preview, 150)
    {:noreply, push_event(socket, "js-exec", %{to: "#sidebar", attr: "data-js-hide"})}
  end

  # open standalone live preview for schema without blocks
  def handle_event("open_live_preview_standalone", _, %{assigns: %{has_blocks?: false}} = socket) do
    send(self(), {:toast, gettext("Opening stand alone live preview window...")})

    send_update_after(
      __MODULE__,
      [id: socket.assigns.id, action: :event_tag_received, tag: :live_preview_standalone],
      100
    )

    {:noreply, socket}
  end

  def handle_event("open_live_preview_standalone", _, socket) do
    send(self(), {:toast, gettext("Opening stand alone live preview window...")})
    {:noreply, fetch_root_blocks(socket, :live_preview_standalone, 500)}
  end

  # One save that asks the translations for no new review of text that
  # changed: typo fixes and the like. Structure, shared values and new text
  # are still synchronized.
  def handle_event("push_submit_minor", _, socket) do
    {:noreply,
     socket
     |> assign(:minor_save?, true)
     |> assign(:save_redirect_target, :self)
     |> push_event("b:submit", %{})}
  end

  def handle_event("create_translation", %{"language" => language}, socket) do
    %{schema: schema, current_user: user, translation: state} = socket.assigns
    source_id = (state && state.source && state.source.id) || socket.assigns.entry.id

    with :ok <- Brando.Authorization.Boundary.authorize(user, :create, schema),
         {:ok, target} <- Brando.Translations.create_target(schema, source_id, language, user) do
      BrandoAdmin.LiveView.Listing.update_list_entries(schema)
      {:noreply, push_navigate(socket, to: schema.__admin_route__(:update, [target.id]))}
    else
      error -> {:noreply, translation_action_failed(socket, error)}
    end
  end

  def handle_event("make_translation_independent", _, socket) do
    %{schema: schema, current_user: user, entry: entry} = socket.assigns

    with :ok <- Brando.Authorization.Boundary.authorize(user, :update, entry),
         {:ok, _member} <- Brando.Translations.make_independent(schema, entry.id, user) do
      BrandoAdmin.LiveView.Listing.update_list_entries(schema)
      send(self(), {:toast, gettext("This translation is now independent.")})
      # The form keeps its unsaved changes; only the translation state changes.
      {:noreply, Translation.assign_state(socket)}
    else
      error -> {:noreply, translation_action_failed(socket, error)}
    end
  end

  def handle_event("make_translation_source", _, socket) do
    %{schema: schema, current_user: user, entry: entry, translation: state} = socket.assigns

    with :ok <- Brando.Authorization.Boundary.authorize(user, :update, entry),
         :ok <- authorize_source(schema, user, state),
         {:ok, _member} <- Brando.Translations.transfer_source(schema, entry.id, user) do
      BrandoAdmin.LiveView.Listing.update_list_entries(schema)
      send(self(), {:toast, gettext("This translation is now the source.")})
      {:noreply, Translation.assign_state(socket)}
    else
      error -> {:noreply, translation_action_failed(socket, error)}
    end
  end

  def handle_event("push_submit_redirect", _, socket) do
    {:noreply, push_event(socket, "b:submit", %{})}
  end

  def handle_event("push_submit", _, socket) do
    {:noreply,
     socket
     |> assign(:save_redirect_target, :self)
     |> push_event("b:submit", %{})}
  end

  def handle_event("push_submit_new", _, socket) do
    {:noreply,
     socket
     |> assign(:save_redirect_target, :new)
     |> push_event("b:submit", %{})}
  end

  def handle_event("toggle_revisions_drawer_status", _, socket) do
    if socket.assigns.entry_id do
      new_status = (socket.assigns.status_revisions == :open && :closed) || :open

      # Send update to revision drawer component to trigger loading if opening
      if new_status == :open do
        send_update(BrandoAdmin.Components.Form.RevisionsDrawer,
          id: "#{socket.assigns.id}-revisions-drawer",
          action: :fetch_revisions
        )
      end

      {:noreply, assign(socket, :status_revisions, new_status)}
    else
      error_title = gettext("Notice")

      error_msg =
        gettext("To create and administrate revisions, the entry must be saved at least one time first.")

      {:noreply, push_event(socket, "b:alert", %{title: error_title, message: error_msg, type: "error"})}
    end
  end

  def handle_event("select_tab", %{"name" => tab_name}, socket) do
    {:noreply, assign(socket, :active_tab, tab_name)}
  end

  def handle_event("save_redirect_target", _, socket) do
    {:noreply, assign(socket, :save_redirect_target, :self)}
  end

  # An entry that was never saved has no revisions: the button only asks the
  # server, which says so, and the drawer stays shut. Opening it here too left
  # it open, and closing it asked again.
  defp toggle_revisions(nil, _id, myself), do: JS.push("toggle_revisions_drawer_status", target: myself)

  defp toggle_revisions(_entry_id, id, myself) do
    "toggle_revisions_drawer_status"
    |> JS.push(target: myself)
    |> toggle_drawer("##{id}-revisions-drawer")
  end

  defp upload_file_count(count) when is_integer(count), do: count

  defp upload_file_count(count) when is_binary(count) do
    case Integer.parse(count) do
      {parsed, _} -> parsed
      _ -> 0
    end
  end

  defp upload_file_count(_count), do: 0

  defp saved_entry_with_blocks(socket, entry, save) do
    %{schema: schema, current_user: current_user, mutation_type: mutation_type} = save
    translated_singular = Brando.Blueprint.get_singular(schema)

    send(self(), {:progress_popup, "Entry saved."})
    if FrontendEditor.frontend?(socket), do: FrontendEditor.saved(socket, entry)

    Brando.Blueprint.AfterSave.run(schema, entry, save.changeset, current_user)

    {socket, stale?} = after_translation_save(socket, schema, entry)

    maybe_run_form_after_save(save.form_blueprint, entry, current_user)

    mutation_message =
      Brando.Gettext
      |> Gettext.dgettext("mutations", "#{mutation_type}", singular: translated_singular)
      |> String.capitalize()

    send(self(), {:toast, mutation_message})

    {:noreply,
     maybe_offer_permalink_redirect(Drafts.saved(socket, entry), save.entry_or_default, entry, fn socket ->
       redirect_after_save_with_blocks(socket, entry, stale?, save)
     end)}
  end

  defp redirect_after_save_with_blocks(socket, entry, stale?, save) do
    %{schema: schema, mutation_type: mutation_type} = save

    # Leaving the editor: the block fields that would hand the saved rows to
    # the edit session are going away, so the form does it. Without it the
    # others' sessions keep this save's new blocks as unsaved, and their next
    # save inserts them again.
    if save.save_redirect_target in [:listing, :new], do: EditSession.saved(entry)

    maybe_redirected_socket =
      case save.save_redirect_target do
        :self ->
          refresh_saved_entry_with_blocks(socket, entry, stale?, save)

        :listing ->
          # if redirect_on_save is set in form, use this
          redirect_fn =
            save.form_blueprint.redirect_on_save ||
              fn socket, _entry, _mutation_type ->
                generated_list_view = schema.__modules__().admin_list_view
                Brando.routes().admin_live_path(socket, generated_list_view)
              end

          push_navigate(socket, to: Callback.call(redirect_fn, [socket, entry, mutation_type]))

        :new ->
          # redirect to "create new"
          push_navigate(socket, to: schema.__admin_route__(:create, []))
      end

    assign(maybe_redirected_socket, :save_redirect_target, default_save_target(socket))
  end

  defp refresh_saved_entry_with_blocks(socket, entry, stale?, %{schema: schema, mutation_type: :create}) do
    update_url = schema.__admin_route__(:update, [entry.id])

    socket
    |> assign(:processing, false)
    |> assign(:all_blocks_received?, false)
    |> reset_transformer_changesets()
    |> assign(:entry_id, entry.id)
    |> assign_refreshed_entry()
    |> assign_refreshed_form()
    |> clear_blocks_root_changesets()
    |> assign_block_map()
    |> assign_entry_for_blocks()
    # A saved revision preview is the entry now: its blocks rejoin the
    # entry's edit session.
    |> assign(:blocks_detached?, false)
    |> reload_all_blocks(:changed)
    |> refresh_translation(stale?)
    |> push_patch(to: update_url)
  end

  defp refresh_saved_entry_with_blocks(socket, entry, stale?, %{schema: schema}) do
    maybe_refresh_revisions(socket, schema)

    # update entry!
    socket
    |> assign(:processing, false)
    |> assign(:all_blocks_received?, false)
    |> reset_transformer_changesets()
    |> assign(:entry_id, entry.id)
    |> assign_refreshed_entry()
    |> assign_refreshed_form()
    |> clear_blocks_root_changesets()
    |> assign_block_map()
    |> assign_entry_for_blocks()
    # A saved revision preview is the entry now: its blocks rejoin the
    # entry's edit session.
    |> assign(:blocks_detached?, false)
    |> reload_all_blocks(:changed)
    |> refresh_translation(stale?)
  end

  defp maybe_refresh_revisions(socket, schema) do
    if schema.has_trait(Brando.Trait.Revisioned) do
      id = "#{socket.assigns.id}-revisions-drawer"
      send_update(RevisionsDrawer, id: id, action: :refresh_revisions)
    end
  end

  defp source_controlled_save_with_blocks(socket, paths) do
    if FrontendEditor.frontend?(socket), do: FrontendEditor.save_failed(socket, :source_controlled)
    if socket.assigns.entry, do: EditSession.save_failed(socket.assigns.entry)

    {:noreply,
     socket
     |> assign(:processing, false)
     |> assign(:all_blocks_received?, false)
     |> clear_blocks_root_changesets()
     |> reset_transformer_changesets()
     |> source_controlled_error(paths)}
  end

  defp failed_save_with_blocks(socket, changeset, save) do
    Logger.error(inspect(changeset, pretty: true))
    send(self(), {:progress_popup, "Saving entry failed..."})
    if socket.assigns.entry, do: EditSession.save_failed(socket.assigns.entry)

    if FrontendEditor.frontend?(socket),
      do: FrontendEditor.save_failed(socket, {:invalid, changeset |> traverse_errors(& &1) |> Map.keys()})

    # The next save reads the blocks again rather than writing the ones this
    # save collected: another editor's save may have written some of them
    # since (a retry after two overlapping saves).
    {:noreply,
     socket
     |> assign(:processing, false)
     |> assign(:minor_save?, false)
     |> assign(:all_blocks_received?, false)
     |> clear_blocks_root_changesets()
     |> reset_transformer_changesets()
     |> put_form(to_form(changeset, []))
     |> push_errors(changeset, save.form_blueprint, save.schema)}
  end

  defp saved_entry(socket, entry, save) do
    %{schema: schema, current_user: current_user, mutation_type: mutation_type} = save
    singular = schema.__naming__().singular

    Brando.Blueprint.AfterSave.run(schema, entry, save.changeset, current_user)

    {socket, _stale?} = after_translation_save(socket, schema, entry)
    maybe_run_form_after_save(save.form_blueprint, entry, current_user)
    send(self(), {:toast, "#{String.capitalize(singular)} #{mutation_type}d"})

    {:noreply,
     maybe_offer_permalink_redirect(Drafts.saved(socket, entry), save.entry_or_default, entry, fn socket ->
       redirect_after_save(socket, entry, save)
     end)}
  end

  defp redirect_after_save(socket, entry, save) do
    %{schema: schema, mutation_type: mutation_type} = save

    maybe_redirected_socket =
      case save.save_redirect_target do
        :self ->
          refresh_saved_entry(socket, entry, save)

        :listing ->
          # if redirect_on_save is set in form, use this
          redirect_fn =
            save.form_blueprint.redirect_on_save ||
              fn _socket, _entry, _mutation_type ->
                schema.__admin_route__(:list, [schema.__modules__().admin_list_view])
              end

          push_navigate(socket, to: Callback.call(redirect_fn, [socket, entry, mutation_type]))

        :new ->
          # redirect to "create new"
          push_navigate(socket, to: schema.__admin_route__(:create, []))
      end

    # `:processing` is cleared here rather than per-branch: `:listing` and
    # `:new` navigate away, so only `:self` ever renders the button again —
    # and it was the one branch that forgot. The button is `disabled` while
    # the flag is set, so a stuck flag does not just look wrong, it locks
    # the form until the page is reloaded. Its sibling clause above sets
    # the flag in each `:self` sub-branch; one place is harder to forget.
    maybe_redirected_socket
    |> assign(:save_redirect_target, if(socket.assigns[:layout] == :settings, do: :self, else: :listing))
    |> assign(:processing, false)
  end

  defp refresh_saved_entry(socket, entry, %{schema: schema, mutation_type: :create}) do
    generated_route = schema.__admin_route__(:update, [entry.id])

    push_navigate(socket, to: generated_route)
  end

  defp refresh_saved_entry(socket, entry, %{schema: schema}) do
    maybe_refresh_revisions(socket, schema)

    # update entry!
    socket
    |> assign(:entry_id, entry.id)
    |> assign_refreshed_entry()
    |> assign_refreshed_form()
  end

  # Crop was already applied via the HTTP replace_crop endpoint.
  # The controller's Crop.save_replace already queued processing.
  defp cropped_editor_image(params, edit_image) do
    image_id = params["image_id"] || edit_image.image.id
    {:ok, img} = Images.get_image(image_id)
    img
  end

  # No crop — just update focal point and reprocess from the original file.
  defp refocused_editor_image(params, edit_image, current_user) do
    image =
      case edit_image do
        %{image: image} when not is_nil(image) ->
          image

        _ ->
          {:ok, img} = Images.get_image(params["image_id"])
          img
      end

    x = params["focal_x"]
    y = params["focal_y"]

    changeset =
      image
      |> Images.Image.changeset(
        %{focal: %{x: x, y: y}, status: :unprocessed},
        current_user
      )
      |> Map.put(:action, :update)

    {:ok, img} = Images.update_image(changeset, current_user)
    img
  end

  # The image's own form: the entry is the image; show it as saved.
  defp show_saved_editor_image(socket, %{own: own} = edit_image, updated_image) when own not in [nil, false] do
    socket
    |> assign(:entry, updated_image)
    |> assign(:edit_image, Map.merge(edit_image, %{image: updated_image}))
    |> assign(:image_changeset, change(updated_image))
    |> assign_refreshed_form()
  end

  # Non-block path: update entry with the image so the Image input
  # detects the change when the form re-validates (same pattern as new_copy).
  defp show_saved_editor_image(socket, edit_image, updated_image) do
    schema = socket.assigns.schema
    field_atom = String.to_existing_atom("#{edit_image.field}")
    entry = socket.assigns.entry || struct(schema)
    field_path = edit_image.path ++ [field_atom]
    access_path = Brando.Utils.build_access_path(field_path)
    updated_entry = put_in(entry, access_path, updated_image)

    image_changeset = change(updated_image)
    updated_edit_image = Map.merge(edit_image, %{image: updated_image})

    socket
    |> assign(:entry, updated_entry)
    |> assign(:edit_image, updated_edit_image)
    |> assign(:image_changeset, image_changeset)
    |> push_event("b:validate", %{})
  end

  defp external_video_params?(%{"type" => type}) when type in ["external_file", "vimeo", "youtube"], do: true
  defp external_video_params?(%{type: type}) when type in [:external_file, :vimeo, :youtube], do: true
  defp external_video_params?(_params), do: false

  defp external_video_urls_allowed?(socket) do
    case socket.assigns.edit_video do
      %{schema: schema, field: field} when is_atom(schema) and is_atom(field) ->
        %{cfg: cfg} = Brando.Blueprint.Assets.__asset_opts__(schema, field)
        Map.get(cfg, :allow_external_urls, true)

      _ ->
        true
    end
  rescue
    _ -> false
  end

  defp maybe_invalidate_live_preview_assign(socket, path, path_type \\ :atom_path)

  defp maybe_invalidate_live_preview_assign(
         %{assigns: %{live_preview_active?: true, fields_demanding_live_preview_reassign: fdlpr}} =
           socket,
         path,
         path_type
       )
       when fdlpr != [] do
    path = if path_type == :string_path, do: string_path_to_atom_path(path), else: path
    cache_key = socket.assigns.live_preview_cache_key

    case Enum.find(fdlpr, fn {_key, trigger_path} -> trigger_path == path end) do
      {key, _} -> LivePreview.invalidate_var(cache_key, key)
      nil -> nil
    end

    socket
  end

  defp maybe_invalidate_live_preview_assign(socket, _string_path, _) do
    socket
  end

  defp request_select_options_update(socket) do
    form_blueprint = socket.assigns.form_blueprint
    singular = socket.assigns.singular

    form_blueprint
    |> Brando.Blueprint.Forms.list_fields(:select)
    |> Enum.reject(&(&1 == :language))
    |> build_lc_ids(singular)
    |> send_select_options_update(Select)

    form_blueprint
    |> Brando.Blueprint.Forms.list_fields(:multi_select)
    |> build_lc_ids(singular)
    |> send_select_options_update(MultiSelect)

    socket
  end

  defp send_select_options_update(field_ids, component) do
    Enum.map(field_ids, fn field_id ->
      send_update(component, id: field_id, action: :force_refresh_options)
    end)
  end

  defp build_lc_ids(fields, singular) do
    Enum.map(fields, fn field -> "#{singular}_#{field}" end)
  end

  # Rendezvous between the two halves of a live preview recovery.
  #
  # `recover_live_preview_state` knows the cache key and that the preview was
  # open; `validate` is what rebuilds the entry from the recovered form params.
  # Neither can render alone — the first to arrive would render an entry the
  # other has not restored yet — and LiveView does not order them. So each
  # marks its half done and the second one through renders.
  #
  # Previously nothing coordinated them and it worked only because a validate
  # usually happened to arrive after the preview handler. When it did not, the
  # preview stayed blank until the editor toggled it off and on.
  defp maybe_finish_live_preview_recovery(
         %{assigns: %{live_preview_recovery_pending?: true, form_recovered?: true}} = socket
       ) do
    socket
    |> assign(:live_preview_recovery_pending?, false)
    |> maybe_full_rerender_live_preview(true)
  end

  defp maybe_finish_live_preview_recovery(socket), do: socket

  defp maybe_fetch_root_blocks(%{assigns: %{live_preview_active?: true}} = socket, event, delay) do
    fetch_root_blocks(socket, event, delay)
  end

  defp maybe_fetch_root_blocks(%{assigns: %{live_preview_active?: false}} = socket, _, _) do
    socket
  end

  defp fetch_root_blocks(socket, tag, delay)
       when tag in [:live_preview_update, :live_preview_full_rerender, :live_preview_reload] do
    Preview.queue(socket, tag, delay)
  end

  defp fetch_root_blocks(socket, tag, delay) do
    id = socket.assigns.id
    block_map = socket.assigns.block_map

    if block_map == [] do
      event_tag_received(socket, tag)
    else
      for {block_field_name, _schema, _entry_blocks, _opts} <- block_map do
        block_field_id = "#{id}-blocks-#{block_field_name}"

        send_update_after(
          BlockField,
          [id: block_field_id, event: "fetch_root_blocks", tag: tag],
          delay
        )
      end

      socket
    end
  end

  # A save asks every block field for its blocks, then writes once they all
  # answered (`event_tag_received/2`). A second save while the first is
  # collecting (a button press and ⌘S) is the same save. A collection that
  # never finishes stops counting after a while, so a save can be tried
  # again.
  @save_collect_ms 10_000

  defp collecting_save?(socket) do
    case socket.assigns[:save_collecting_since] do
      nil -> false
      since -> System.monotonic_time(:millisecond) - since < @save_collect_ms
    end
  end

  defp collect_for_save(socket) do
    fetch_transformer_data(socket, :save)
    send(self(), {:progress_popup, "Saving..."})

    # A form that declares none of the schema's block fields has no BlockField
    # to answer, so `fetch_root_blocks/3` handles the tag itself and returns the
    # socket carrying the submit. Dropping that socket left the save hanging.
    {:noreply,
     socket
     |> ship_all_field_changes()
     |> assign(:processing, true)
     |> assign(:save_collecting_since, System.monotonic_time(:millisecond))
     |> fetch_root_blocks(:save, 150)}
  end

  # All collected: the blocks are dropped, and the write that follows (the
  # `b:submit` already on its way) collects them again first. Still
  # collecting: the field that moved on is asked again.
  defp recollect_blocks(%{assigns: %{all_blocks_received?: true}} = socket, _field),
    do: socket |> assign(:all_blocks_received?, false) |> clear_blocks_root_changesets()

  defp recollect_blocks(%{assigns: %{processing: true, block_changesets: collected}} = socket, field)
       when is_map_key(collected, field) and not is_nil(:erlang.map_get(field, collected)) do
    send_update(BlockField, id: "#{socket.assigns.id}-blocks-#{field}", event: "fetch_root_blocks", tag: :save)
    assign(socket, :block_changesets, Map.put(collected, field, nil))
  end

  defp recollect_blocks(socket, _field), do: socket

  # Reset the per-field accumulator between provide_root_blocks rounds.
  # (BlockFields materialize their answer from the op store, so there is no
  # per-component gather state left to clear.)
  defp clear_blocks_root_changesets(socket) do
    blocks = socket.assigns.form_blueprint.blocks
    assign(socket, :block_changesets, Map.new(blocks, &{&1.name, nil}))
  end

  defp render_preview_update(%{assigns: %{frontend_edit: %{}}} = socket, mode, block_changesets) do
    changeset = assoc_all_block_fields(block_changesets, socket.assigns.form.source)
    FrontendEditor.replace_fields(socket, changeset, mode)
    socket
  end

  defp render_preview_update(socket, mode, block_changesets) do
    changeset = assoc_all_block_fields(block_changesets, socket.assigns.form.source)

    # Reload newly introduced media so frontend players initialize. Preserve the
    # key held by the iframe and every block's channel subscription.
    function =
      case mode do
        :live_preview_update -> :update
        :live_preview_full_rerender -> :rerender
        :live_preview_reload -> :reload
      end

    apply(LivePreview, function, [
      socket.assigns.schema,
      changeset,
      socket.assigns.live_preview_cache_key,
      socket.assigns.updated_entry_assocs
    ])

    socket
  end

  # `scope: :changed` after a save lets each block field skip roots it can
  # prove already hold the saved rows; every other reload re-seeds them all.
  defp reload_all_blocks(socket, scope \\ :all) do
    block_map = socket.assigns.block_map
    id = socket.assigns.id

    for {block_field_name, _schema, _entry_blocks, _opts} <- block_map do
      block_field_id = "#{id}-blocks-#{block_field_name}"
      send_update(BlockField, id: block_field_id, event: "reload_all_blocks", scope: scope)
    end

    socket
  end

  defp maybe_offer_permalink_redirect(socket, previous, saved, continue) do
    case Brando.Trait.Permalink.redirect_for(previous, saved, Brando.config(:default_language)) do
      nil ->
        continue.(socket)

      redirect ->
        language = to_string(Map.get(saved, :language) || Brando.config(:default_language))

        error =
          case Brando.Sites.Redirects.delete_permalink_redirect(redirect.to, language, socket.assigns.current_user) do
            {:ok, _} ->
              nil

            {:error, _} ->
              gettext(
                "The entry was saved, but an existing redirect on its new URL could not be removed. Please check the SEO redirect settings."
              )
          end

        # The entry is saved: the edit session moves onto it now, not when
        # the prompt is answered, which may be never.
        EditSession.saved(saved)

        socket
        |> assign(:processing, false)
        |> assign(:pending_permalink_redirect, %{redirect: redirect, continue: continue})
        |> assign(:permalink_redirect_error, error)
    end
  end

  defp finish_permalink_redirect(socket) do
    %{continue: continue} = socket.assigns.pending_permalink_redirect

    socket
    |> assign(:pending_permalink_redirect, nil)
    |> assign(:permalink_redirect_error, nil)
    |> continue.()
  end

  defp maybe_run_form_after_save(%{after_save: nil}, _, _), do: nil

  defp maybe_run_form_after_save(%{after_save: after_save}, entry, current_user) do
    Callback.call(after_save, [entry, current_user])
  end

  # Puts a changeset built on the saved entry — a recovery copy, or a
  # translation's pending version — into the form as unsaved changes: the main
  # form, every block field and every transformer.
  #
  # `source` is `:translation` when the form loads a pending version on open:
  # an editor who joins a translation others already work in finds the
  # version, and their work, in the edit session, and the block fields keep
  # it rather than load the version over it.
  defp apply_restored_changeset(socket, changeset, source \\ :recovery_copy) do
    form = to_form(changeset)

    for field <- socket.assigns.form_blueprint.blocks do
      send_update(BlockField,
        id: "#{socket.assigns.id}-blocks-#{field.name}",
        event: "restore_draft",
        source: source,
        entry_blocks: Map.get(changeset.data, :"entry_#{field.name}") || [],
        changesets: get_assoc(changeset, :"entry_#{field.name}")
      )
    end

    for {name, _, _} <- socket.assigns.form_blueprint.transformers do
      send_update(BrandoAdmin.Components.Form.Transformer,
        id: "#{form.id}-transformer-#{name}",
        event: "restore_draft",
        field: form[name]
      )
    end

    socket
    |> put_local_form(form)
    |> own_changed_assets(Map.keys(changeset.changes))
    |> assign_entry_for_blocks()
    |> force_svelte_remounts(:all)
    |> Drafts.dirty()
  end

  # A synchronized translation is checked against the version its editor
  # worked from before it is written (`Brando.Translations.check_target_save/4`).
  defp save_entry(socket, context, mutation_type, singular, changeset) do
    entry_id = get_field(changeset, :id)
    user = socket.assigns.current_user

    check =
      if entry_id,
        do:
          Brando.Translations.check_target_save(
            socket.assigns.schema,
            entry_id,
            changeset,
            Translation.version_id(socket.assigns)
          ),
        else: {:ok, changeset}

    case check do
      {:ok, changeset} -> apply(context, :"#{mutation_type}_#{singular}", [changeset, user | mutation_opts(socket)])
      error -> error
    end
  end

  # Options for the translation sync the mutation queues. A minor save (Save
  # minor text corrections) of a synchronized source raises no review work. A
  # synchronized translation is recomputed by `after_translation_save/3`, so
  # the mutation queues no recompute of its own. Other saves keep the
  # two-argument call, which hand-written contexts define.
  defp mutation_opts(socket) do
    opts =
      [
        minor: Map.get(socket.assigns, :minor_save?, false),
        editor_review: Translation.locked?(socket.assigns[:translation])
      ]
      |> Enum.filter(&elem(&1, 1))

    if opts == [], do: [], else: [opts]
  end

  defp after_translation_save(socket, schema, entry) do
    socket = assign(socket, :minor_save?, false)

    case Brando.Translations.target_saved(schema, entry.id, Translation.review(socket.assigns)) do
      {:ok, %{stale: stale?}} -> {socket, stale?}
      _ -> {socket, false}
    end
  end

  # The current source becomes a translation, so the user must be allowed to
  # change it too.
  defp authorize_source(schema, user, %{source: %{id: id}}) do
    case Brando.Repo.get(schema, id) do
      nil -> {:error, :source_not_found}
      source -> Brando.Authorization.Boundary.authorize(user, :update, source)
    end
  end

  defp authorize_source(_schema, _user, _state), do: {:error, :not_enrolled}

  defp translation_action_failed(socket, error) do
    message =
      case error do
        {:error, :language_exists} -> gettext("This language already has a version.")
        {:error, :not_duplicable} -> gettext("Translations can't be created: this content type can't be copied.")
        {:error, :unauthorized} -> gettext("You do not have permission to do this.")
        {:error, %{__exception__: true}} -> gettext("You do not have permission to do this.")
        _ -> gettext("The translation could not be changed.")
      end

    require Logger
    Logger.warning("Translation action failed: #{inspect(error)}")
    send(self(), {:toast, message})
    socket
  end

  defp source_controlled_error(socket, paths) do
    socket = assign(socket, :minor_save?, false)
    require Logger
    Logger.warning("Refused a translation save that changed source-controlled content: #{inspect(paths)}")
    send(self(), {:progress_popup, "Saving entry failed..."})

    send(
      self(),
      {:toast,
       gettext(
         "Not saved: this translation's structure, media and shared values follow the source. Change them in the source."
       )}
    )

    socket
  end

  defp assoc_all_block_fields(block_changesets, changeset) do
    Enum.reduce(block_changesets, changeset, fn {field_name, block_cs}, updated_changeset ->
      updated_block_cs =
        block_cs
        |> Blocks.reject_deleted(true)
        |> Blocks.strip_render_artifacts()
        |> Brando.Utils.set_action()

      Changeset.put_assoc(updated_changeset, :"entry_#{field_name}", updated_block_cs)
    end)
  end

  defp assoc_all_transformer_fields(changeset, transformer_changesets) do
    Enum.reduce(transformer_changesets, changeset, fn
      {_field_name, nil}, acc -> acc
      {field_name, data}, acc -> Changeset.put_assoc(acc, field_name, data)
    end)
  end

  defp store_revision(socket, changeset) do
    result =
      with :ok <- Brando.Authorization.Boundary.change(socket.assigns.current_user, :update, changeset),
           do: Changeset.apply_action(changeset, :update)

    case result do
      {:ok, entry} ->
        case Brando.Revisions.create_revision(entry, socket.assigns.current_user, false) do
          {:ok, _revision} ->
            send(self(), {:toast, gettext("Revision saved")})

            send_update(RevisionsDrawer,
              id: "#{socket.assigns.id}-revisions-drawer",
              action: :refresh_revisions
            )

            socket

          {:error, reason} ->
            revision_error(socket, reason)
        end

      {:error, :forbidden} ->
        revision_error(socket, :forbidden)

      {:error, invalid_changeset} ->
        socket
        |> put_form(to_form(invalid_changeset, []))
        |> push_errors(
          invalid_changeset,
          socket.assigns.form_blueprint,
          socket.assigns.schema
        )
    end
  end

  defp revision_error(socket, reason) do
    require Logger
    Logger.error("Could not store revision: #{inspect(reason)}")

    push_event(socket, "b:alert", %{
      title: gettext("Could not save revision"),
      message: gettext("The revision was not saved. Please try again."),
      type: "error"
    })
  end

  defp fetch_transformer_data(socket, tag) do
    transformers = extract_transformers(socket.assigns.form_blueprint)

    for {relation_key, _field, _default} <- transformers do
      transformer_id = "#{socket.assigns.form.id}-transformer-#{relation_key}"

      send_update_after(
        BrandoAdmin.Components.Form.Transformer,
        [id: transformer_id, event: "fetch_transformer_data", tag: tag],
        150
      )
    end

    socket
  end

  defp reset_transformer_changesets(socket) do
    transformers = extract_transformers(socket.assigns.form_blueprint)

    socket
    |> assign(:all_transformers_received?, transformers == [])
    |> assign(:transformer_changesets, Map.new(transformers, fn {name, _, _} -> {name, nil} end))
  end

  defp loaded_image?(nil), do: false
  defp loaded_image?(%Ecto.Association.NotLoaded{}), do: false
  defp loaded_image?(%Images.Image{}), do: true

  # `env` says what the errors stopped: a save, or opening the live preview.
  defp push_errors(socket, changeset, form, schema, env \\ :save) do
    error_title = gettext("Error")

    error_notice =
      case env do
        :save ->
          gettext("Error while saving form. Please correct marked fields and resubmit<br><br>Fields marked invalid:")

        :live_preview ->
          gettext(
            "Cannot open Live Preview with errors in form. Please correct marked fields and try again<br><br>Fields marked invalid:"
          )
      end

    traversed_errors =
      traverse_errors(changeset, fn {msg, opts} ->
        String.replace(msg, "%{count}", to_string(opts[:count]))
      end)

    error_keys = Map.keys(traversed_errors)

    tab_with_first_error =
      error_keys
      |> List.first()
      |> Brando.Blueprint.Forms.get_tab_for_field(form)

    {group_items, grouped_keys} = group_constraint_items(changeset, form, schema)

    translated_error_keys =
      (error_keys -- grouped_keys)
      |> Brando.Blueprint.Utils.translate_error_keys(form, schema)
      |> Kernel.++(group_items)

    # Include nested association errors as "parent → child → field" paths
    nested_error_paths = flatten_nested_errors(traversed_errors)

    all_error_items =
      for key <- translated_error_keys do
        "<li class=\"text-mono\">#{key}</li>"
      end ++
        for {path, messages} <- nested_error_paths do
          "<li class=\"text-mono\">#{path}: #{Enum.join(messages, ", ")}</li>"
        end

    error_msg = """
    #{error_notice}<br><br>
    <ul class="error-keys">#{all_error_items}</ul>
    """

    require Logger

    Logger.error("""


    Changeset errors:

    #{inspect(traversed_errors, pretty: true)}

    """)

    socket
    |> assign(:active_tab, tab_with_first_error)
    |> push_event("b:alert", %{title: error_title, message: error_msg, type: "error"})
    |> push_event("b:scroll_to_first_error", %{})
  end

  @doc false
  # `one_of`/`exactly_one_of` mark every field in the set, which would list each
  # of them separately — reading as "all of these are wrong" when the point is
  # that one of them will do. Collapse each set into a single entry.
  #
  # Returns `{items, consumed_keys}`; the caller subtracts the consumed keys so
  # the grouped fields are not also listed individually.
  def group_constraint_items(changeset, form, schema) do
    changeset.errors
    |> Enum.flat_map(fn {_key, {_msg, opts}} ->
      case opts[:one_of] || opts[:exactly_one_of] do
        nil -> []
        fields -> [fields]
      end
    end)
    |> Enum.uniq()
    |> Enum.reduce({[], []}, fn fields, {items, keys} ->
      labels = Brando.Blueprint.Utils.translate_error_keys(fields, form, schema)
      item = Enum.join(labels, " #{gettext("or")} ")

      {items ++ [item], keys ++ Enum.map(fields, &group_error_key(changeset, &1))}
    end)
  end

  # Mirrors Brando.Blueprint.Constraints: an asset's error lives on its _id.
  defp group_error_key(changeset, field) do
    relation_key = :"#{field}_id"
    if Map.has_key?(changeset.data, relation_key), do: relation_key, else: field
  end

  defp flatten_nested_errors(errors, prefix \\ []) do
    Enum.flat_map(errors, fn
      {field, messages} when is_list(messages) ->
        flatten_error_messages(messages, prefix, prefix ++ [field])

      {field, nested} when is_map(nested) ->
        flatten_nested_errors(nested, prefix ++ [field])

      _ ->
        []
    end)
  end

  defp flatten_error_messages(messages, prefix, path) do
    if Enum.all?(messages, &is_binary/1) do
      # Only include if this is a nested path (not top-level, those are handled separately)
      if prefix == [], do: [], else: [{Enum.join(path, " → "), messages}]
    else
      # messages contains nested maps (from associations)
      Enum.flat_map(messages, fn
        nested when is_map(nested) -> flatten_nested_errors(nested, path)
        _ -> []
      end)
    end
  end

  @doc """
  Handle upload progress for the image editor's "save as new copy" feature.

  Applies stored focal point and config_target to the new image, then queues
  processing and forwards the result to the block component (if from a block).
  """
  def handle_image_editor_upload_progress(:image_editor_upload, entry, socket) do
    if entry.done? do
      consume_image_editor_upload(entry, socket)
    else
      {:noreply, socket}
    end
  end

  defp consume_image_editor_upload(entry, socket) do
    current_user = socket.assigns.current_user
    config_target = Map.get(socket.assigns, :image_editor_config_target, "default")

    {cfg, resolved_target} = resolve_block_image_config(config_target)

    case consume_uploaded_entry(socket, entry, fn meta ->
           safe_handle_upload(
             Map.put(meta, :config_target, resolved_target),
             entry,
             cfg,
             current_user
           )
         end) do
      {:upload_error, reason} ->
        upload_error_noreply(socket, :image, reason)

      new_image ->
        refocus_image_editor_copy(socket, new_image)
    end
  end

  defp refocus_image_editor_copy(socket, new_image) do
    current_user = socket.assigns.current_user
    focal = Map.get(socket.assigns, :image_editor_focal, %{x: 50, y: 50})

    # Apply focal and mark for reprocessing
    changeset =
      new_image
      |> Images.Image.changeset(
        %{focal: %{x: focal.x, y: focal.y}, status: :unprocessed},
        current_user
      )
      |> Map.put(:action, :update)

    case Images.update_image(changeset, current_user) do
      {:ok, updated_image} ->
        image_editor_copy_created(socket, updated_image)

      {:error, reason} ->
        {:noreply,
         push_event(socket, "b:alert", %{
           title: gettext("Error creating image"),
           type: "error",
           message: inspect(reason)
         })}
    end
  end

  defp image_editor_copy_created(socket, updated_image) do
    current_user = socket.assigns.current_user
    edit_image = socket.assigns.edit_image

    Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:image:#{updated_image.id}")

    if block_target = Map.get(edit_image, :block_target) do
      send(self(), {:register_pending_block_image, updated_image.id, block_target})
    end

    Images.Processing.queue_processing(updated_image, current_user, [], silent: true)

    if block_target = Map.get(edit_image, :block_target) do
      {module, id} = block_target

      send_update(module,
        id: id,
        event: "image_editor_new_copy",
        new_image: updated_image,
        old_image_id: Map.get(edit_image, :old_image_id)
      )

      send(self(), {:toast, gettext("New image created.")})
      {:noreply, socket}
    else
      own_or_field_copy(socket, edit_image, updated_image)
    end
  end

  # A copy made from an image's own form opens its own form; a copy made for
  # an entry's image field takes the field's place.
  defp own_or_field_copy(socket, %{own: true}, new_image) do
    send(self(), {:toast, gettext("New image created.")})
    {:noreply, push_navigate(socket, to: Images.Image.__admin_route__(:update, [new_image.id]))}
  end

  defp own_or_field_copy(socket, edit_image, updated_image) do
    # Non-block path
    relation_key = String.to_existing_atom("#{edit_image.field}_id")
    image_changeset = change(updated_image)

    updated_edit_image =
      Map.merge(edit_image, %{id: updated_image.id, image: updated_image})

    {:noreply,
     socket
     |> update_changeset(edit_image.path, relation_key, updated_image.id)
     |> assign(:edit_image, updated_edit_image)
     |> assign(:image_changeset, image_changeset)}
  end

  defp resolve_block_image_config(config_target) do
    resolved_target = normalize_upload_config_target(config_target) || "default"

    case Images.get_config_for(resolved_target) do
      {:ok, cfg} ->
        {cfg, resolved_target}

      _ ->
        default_config =
          Brando.config(Images)[:default_config] ||
            Brando.Type.ImageConfig.default_config()

        cfg =
          case default_config do
            %Brando.Type.ImageConfig{} = c -> c
            config -> struct(Brando.Type.ImageConfig, config)
          end

        {cfg, "default"}
    end
  end

  defp normalize_upload_config_target(nil), do: nil

  defp normalize_upload_config_target(config_target) when is_binary(config_target),
    do: config_target

  defp normalize_upload_config_target(%{config_target: config_target}),
    do: normalize_upload_config_target(config_target)

  defp normalize_upload_config_target({type, schema, :function, function_name}) do
    "#{type}:#{inspect(schema)}:function:#{function_name}"
  end

  defp normalize_upload_config_target({type, schema, field}) do
    "#{type}:#{inspect(schema)}:#{field}"
  end

  defp normalize_upload_config_target(_), do: nil

  defp safe_handle_upload(meta, upload_entry, cfg, current_user) do
    case Brando.Uploads.Store.handle_upload(meta, upload_entry, cfg, current_user) do
      {:ok, asset} -> {:ok, asset}
      {:error, reason} -> {:ok, {:upload_error, reason}}
    end
  end

  defp upload_error_noreply(socket, kind, {:content_type, rejected_type, allowed_types}) do
    error_title = gettext("Error uploading")

    error_msg =
      gettext(
        "Server rejected %{kind} type [%{rejected_type}].<br><br>Allowed types are:<br>%{allowed_types}",
        %{
          kind: upload_kind_label(kind),
          rejected_type: rejected_type,
          allowed_types: inspect(allowed_types)
        }
      )

    {:noreply, push_event(socket, "b:alert", %{title: error_title, type: "error", message: error_msg})}
  end

  defp upload_error_noreply(socket, _kind, %Changeset{} = changeset) do
    require Logger

    Logger.error("""
    Upload failed with validation errors:
    #{inspect(changeset.errors, pretty: true)}
    """)

    {:noreply,
     push_event(socket, "b:alert", %{
       title: gettext("Error uploading"),
       type: "error",
       message: gettext("Could not store uploaded file. Check upload settings and try again.")
     })}
  end

  defp upload_error_noreply(socket, _kind, reason) do
    {:noreply,
     push_event(socket, "b:alert", %{
       title: gettext("Error uploading"),
       type: "error",
       message: inspect(reason)
     })}
  end

  defp upload_kind_label(:image), do: gettext("image")
  defp upload_kind_label(:file), do: gettext("file")
  defp upload_kind_label(:video), do: gettext("video")
  defp upload_kind_label(_), do: gettext("file")

  def assign_form(
        %{
          assigns: %{
            default_params: default_params,
            entry: %{id: nil} = default_entry,
            schema: schema,
            current_user: current_user
          }
        } = socket
      ) do
    socket
    |> assign_new(:form, fn ->
      # this is the initial assignment of changeset with an empty entry,
      # so we add default_params here
      default_entry
      |> schema.changeset(default_params, current_user)
      |> to_form()
    end)
    |> then(&put_form(&1, &1.assigns.form))
  end

  # No `Map.put(:action, :validate)` on any of these three: they all build from
  # EMPTY params, and the error gate that actually fires here goes through
  # `Phoenix.Component.used_input?/1`, which reads `form.params` alone — so no
  # field of an empty-params form can surface an error, action or no action.
  # Forcing the action only made `Phoenix.HTML.FormData` copy `changeset.errors`
  # onto a form nothing reads them from, while implying to the next reader that
  # it was load-bearing.
  #
  # Note the qualifier: only `has_error/2`'s `true` clause gates on
  # `used_input?`. Its fallback clauses (`:5562-5563`) read `field.errors` raw.
  # They are not reached for an empty-params form, which is why this is safe —
  # but "every gate routes through `used_input?`" would be false, and is not the
  # reason to keep it.
  # Pinned by `test/brando_admin/components/form/empty_params_errors_test.exs`.
  def assign_form(%{assigns: %{entry: entry, schema: schema, current_user: current_user}} = socket) do
    socket
    |> assign_new(:form, fn ->
      entry
      |> schema.changeset(%{}, current_user)
      |> to_form()
    end)
    |> then(&put_form(&1, &1.assigns.form))
  end

  def assign_refreshed_form(%{assigns: %{entry: entry, schema: schema, current_user: current_user}} = socket) do
    socket
    |> put_form(to_form(schema.changeset(entry, %{}, current_user), []))
    |> clear_owned_assets()
    |> clear_dirty_fields()
  end

  @doc """
  Assigns a stripped down entry to be used in block fields
  """
  def assign_entry_for_blocks(%{assigns: %{has_blocks?: true}} = socket) do
    changeset = socket.assigns.form.source
    block_map = socket.assigns.block_map
    entry_for_blocks = build_entry_for_blocks(changeset, block_map)
    assign(socket, :entry_for_blocks, entry_for_blocks)
  end

  @doc """
  Assigns a stripped down entry to be used in block fields
  """
  def maybe_assign_entry_for_blocks(%{assigns: %{has_blocks?: true}} = socket) do
    assign_new(socket, :entry_for_blocks, fn ->
      changeset = socket.assigns.form.source
      block_map = socket.assigns.block_map
      build_entry_for_blocks(changeset, block_map)
    end)
  end

  def maybe_assign_entry_for_blocks(socket), do: socket

  defp build_entry_for_blocks(changeset, block_map) do
    blocks_field_names =
      Enum.reduce(block_map, [], fn {block_field_name, _schema, _entry_blocks, _opts}, acc ->
        entry_field_name = :"entry_#{block_field_name}"
        rendered_field_name = :"rendered_#{block_field_name}"
        rendered_at_field_name = :"rendered_#{block_field_name}_at"

        [
          entry_field_name
          | [block_field_name | [rendered_field_name | [rendered_at_field_name | acc]]]
        ]
      end)

    changeset
    |> apply_changes()
    |> Map.drop(blocks_field_names)
  end

  def render_blocks_for_entry(block_map, changeset, entry) do
    Enum.reduce(block_map, changeset, fn {block_field_name, _schema, _entry_blocks, _opts}, updated_changeset ->
      entry_field_name = :"entry_#{block_field_name}"
      rendered_field_name = :"rendered_#{block_field_name}"
      rendered_at_field_name = :"rendered_#{block_field_name}_at"
      blocks_to_parse = get_assoc(changeset, entry_field_name)
      applied_blocks = Brando.Utils.apply_changes_recursively(blocks_to_parse)
      rendered_blocks = Villain.parse(applied_blocks, entry, [])

      updated_changeset
      |> put_change(rendered_field_name, rendered_blocks)
      |> put_change(rendered_at_field_name, DateTime.truncate(DateTime.utc_now(), :second))
    end)
  end

  defp send_updated_entry_field_to_blocks(socket, path, change, field) do
    # Delivering an entry change re-renders the receiving block's whole form
    # subtree — `@entry` is consumed inside `<.form>`, which rebuilds its
    # assigns above its own `~H`, so a changed slot re-emits everything under
    # it. At 115 blocks all reading `entry.title` that is 290 KB and 339 ms for
    # a single settled keystroke, one frame per block. Skipping the blocks
    # whose module cannot read the field that changed is what keeps typing in
    # one entry field from waking every block that reads a different one.
    Enum.each(socket.assigns.blocks_wanting_entry, fn {{mod, id}, fields} ->
      if fields == :all or field in fields do
        send_update(mod, id: id, event: "update_entry_field", path: path, change: change)
      end
    end)

    socket
  end

  # A Write with AI request's prompt, built in its task: the input's
  # `write_with_ai:` instructions (or the deprecated `ai:` they come from)
  # with the fields they read as the form has them now. `blocks` is the
  # block editor's content (`with_ai_blocks/4`), rendered in the task.
  defp write_with_ai_prompt(socket, config, params, blocks) do
    context = ai_context_fun(socket, config[:from] || [], blocks)

    fn ->
      instructions =
        case config[:prompt] do
          prompt when is_binary(prompt) -> Brando.AI.Context.build_prompt(String.trim(prompt), context.())
          _ -> nil
        end

      RichTextAI.prompt(instructions, params)
    end
  end

  # The suggestion panel an event names: the field's own, or the Meta
  # drawer's for a meta field (`FieldActions.id/2`).
  defp field_action_panel(socket, field, panel) do
    ids = FieldActions.ids(socket.assigns.form[field])
    if panel in ids, do: panel, else: hd(ids)
  end

  # Asks for the languages the field has no text in as the form has it now,
  # and keeps its values, so Accept leaves alone what is written since.
  defp start_alt_suggestion(socket, kind, image_id, panel, current) do
    describe = AltTextSuggestion.describe_task(image_id, languages: AltTextSuggestion.languages(current))
    start_async(socket, {kind, image_id, panel, current || %{}}, describe)
  end

  defp alt_suggestion_panel(%{"panel" => panel}) do
    if AltTextSuggestion.id?(panel), do: panel
  end

  defp alt_suggestion_panel(_params), do: nil

  defp field_ai_actions(socket, field) do
    FieldAction.for_field(socket.assigns.schema, socket.assigns.form_blueprint, field)
  end

  # The values of the fields an AI action reads, as a function to call later:
  # it holds the form and the blocks, not the socket, so a task can render
  # the blocks. Block fields read the editor's unsaved blocks: `blocks` is
  # what the block fields answered (`with_ai_blocks/4`), by field, or nil
  # when there was no editor to ask. `:blocks` reads every block field the
  # form shows, a block field's own name just that one. Every other field
  # reads the applied changeset headlessly.
  defp ai_context_fun(socket, context_fields, blocks) do
    form = socket.assigns.form
    block_map = if socket.assigns.has_blocks?, do: socket.assigns.block_map
    context_fields = Brando.AI.Context.normalize_fields(context_fields)

    fn ->
      entry = apply_changes(form.source)
      changeset = assoc_all_block_fields(blocks || %{}, form.source)
      read = %{changeset: changeset, block_map: block_map, live: Map.keys(blocks || %{})}
      Enum.flat_map(context_fields, &ai_context_value(&1, form, entry, read))
    end
  end

  defp ai_context_value(:blocks, _form, _entry, %{changeset: changeset, block_map: block_map}) do
    case render_ai_blocks_context(changeset, block_map, :all) do
      value when value in [nil, ""] -> []
      value -> [{:blocks, value}]
    end
  end

  # A field's text as the editor sees it: the form's params, where the
  # browser sent one. The changeset keeps a required field's saved value when
  # it is cleared, and that is not what the editor asked about. A block field
  # whose blocks were not collected (the form does not show it, or its blocks
  # had not loaded) reads what was last saved.
  defp ai_context_value(field, form, entry, %{changeset: changeset, block_map: block_map, live: live}) do
    if field in live do
      case render_ai_blocks_context(changeset, block_map, [field]) do
        value when value in [nil, ""] -> []
        value -> [{field, value}]
      end
    else
      form_field_context(field, form, entry)
    end
  end

  defp form_field_context(field, form, entry) do
    case Phoenix.HTML.Form.input_value(form, field) do
      value when is_binary(value) ->
        case Brando.AI.Context.format_value(value) do
          "" -> []
          text -> [{field, text}]
        end

      _ ->
        Brando.AI.Context.for_entry(entry, [field])
    end
  end

  # The text of the block fields in `fields` (`:all` for every one), each cut
  # to the length `Brando.AI.Context` gives a saved entry's blocks.
  defp render_ai_blocks_context(_changeset, nil, _fields), do: nil

  defp render_ai_blocks_context(changeset, block_map, fields) do
    entry_for_blocks = build_entry_for_blocks(changeset, block_map)
    read = if fields == :all, do: block_map, else: Enum.filter(block_map, &(elem(&1, 0) in fields))
    rendered_changeset = render_blocks_for_entry(read, changeset, entry_for_blocks)

    read
    |> Enum.map(fn {block_field_name, _schema, _entry_blocks, _opts} ->
      rendered_field_name = :"rendered_#{block_field_name}"

      Changeset.get_change(rendered_changeset, rendered_field_name) ||
        Changeset.get_field(rendered_changeset, rendered_field_name)
    end)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map_join("\n\n", &block_context_text/1)
    |> String.trim()
  end

  # An AI request that reads block fields asks their BlockFields for the
  # editor's blocks first (as save and preview do: the op store, not the
  # rows the form loaded), and `continue.(socket, {:ok, blocks})` makes the
  # request once every one has answered (`receive_ai_blocks/4`). Without
  # blocks to ask for, or before they have loaded, it goes at once with
  # `blocks` nil. `request` names what asks; asking again for the same thing
  # replaces the request that is still waiting, also when the new one needs
  # no blocks.
  #
  # A block field that has not answered in `@ai_blocks_collect_ms` (its
  # blocks reloaded while asked) is given up on as a save gives up on its
  # collection: nothing is sent without the blocks, and
  # `continue.(socket, :unanswered)` tells the editor, who can try again.
  @ai_blocks_collect_ms 10_000

  # Brando's own tests shorten the wait (`:ai_blocks_collect_ms`), compiled
  # in only where `config :brando, :form_load_gate?, true`.
  if Application.compile_env(:brando, :form_load_gate?, false) do
    defp ai_blocks_collect_ms, do: Application.get_env(:brando, :ai_blocks_collect_ms, @ai_blocks_collect_ms)
  else
    defp ai_blocks_collect_ms, do: @ai_blocks_collect_ms
  end

  defp with_ai_blocks(socket, request, context_fields, continue) do
    waiting =
      socket.assigns
      |> Map.get(:ai_block_requests, %{})
      |> Map.reject(fn {_token, waiting} -> same_ai_request?(waiting.request, request) end)

    socket = assign(socket, :ai_block_requests, waiting)

    case ai_block_fields(socket, context_fields) do
      [] ->
        continue.(socket, {:ok, nil})

      fields ->
        token = make_ref()

        send_update_after(
          __MODULE__,
          [id: socket.assigns.id, event: "ai_blocks_unanswered", token: token],
          ai_blocks_collect_ms()
        )

        for field <- fields do
          send_update(BlockField,
            id: "#{socket.assigns.id}-blocks-#{field}",
            event: "fetch_root_blocks",
            tag: {:ai_context, token}
          )
        end

        request = %{request: request, parts: Map.new(fields, &{&1, nil}), continue: continue}
        assign(socket, :ai_block_requests, Map.put(waiting, token, request))
    end
  end

  defp ai_block_fields(%{assigns: %{has_blocks?: true, blocks_ready?: true, block_map: block_map}}, context_fields) do
    fields = Brando.AI.Context.normalize_fields(context_fields)
    names = Enum.map(block_map, &elem(&1, 0))
    if :blocks in fields, do: names, else: Enum.filter(names, &(&1 in fields))
  end

  defp ai_block_fields(_socket, _context_fields), do: []

  # A Write with AI request is one editor's, whichever request id it has.
  defp same_ai_request?({:tiptap, id, _}, {:tiptap, id, _}), do: true
  defp same_ai_request?(request, request), do: true
  defp same_ai_request?(_waiting, _request), do: false

  defp receive_ai_blocks(socket, token, field, roots) do
    waiting = Map.get(socket.assigns, :ai_block_requests, %{})

    case waiting do
      %{^token => %{parts: parts} = request} when is_map_key(parts, field) ->
        parts = Map.put(parts, field, for({_uid, cs} <- roots, not is_nil(cs), do: cs))
        maybe_continue_ai_request(socket, waiting, token, %{request | parts: parts})

      _ ->
        socket
    end
  end

  defp maybe_continue_ai_request(socket, waiting, token, %{parts: parts, continue: continue} = request) do
    if Enum.any?(parts, fn {_field, part} -> is_nil(part) end) do
      assign(socket, :ai_block_requests, Map.put(waiting, token, request))
    else
      socket
      |> assign(:ai_block_requests, Map.delete(waiting, token))
      |> continue.({:ok, parts})
    end
  end

  defp give_up_ai_request(socket, token) do
    case Map.pop(Map.get(socket.assigns, :ai_block_requests, %{}), token) do
      {%{continue: continue}, waiting} ->
        socket
        |> assign(:ai_block_requests, waiting)
        |> continue.(:unanswered)

      {nil, _waiting} ->
        socket
    end
  end

  # A Write with AI request cancelled while its blocks were on their way.
  defp cancel_ai_blocks(socket, %{"tiptap_id" => id} = params) do
    expected = params["request_id"]

    waiting =
      socket.assigns
      |> Map.get(:ai_block_requests, %{})
      |> Map.reject(fn
        {_token, %{request: {:tiptap, ^id, request_id}}} -> is_nil(expected) or request_id == expected
        _ -> false
      end)

    assign(socket, :ai_block_requests, waiting)
  end

  defp cancel_ai_blocks(socket, _params), do: socket

  defp block_context_text(html) do
    html |> HtmlSanitizeEx.strip_tags() |> String.trim() |> String.slice(0, Brando.AI.Context.block_text_length())
  end

  defp parse_form_field_name(field_name, singular) do
    segments = Regex.scan(~r/[^\[\]]+/, field_name) |> List.flatten()

    with [root | field_segments] <- segments,
         true <- root == singular,
         false <- field_segments == [],
         {:ok, path, key} when is_atom(key) <- cast_form_path_segments(field_segments) do
      {:ok, path, key, field_segments}
    else
      _ -> {:error, :invalid_field_name}
    end
  end

  defp cast_form_path_segments(segments) do
    segments
    |> Enum.reduce_while({:ok, []}, fn segment, {:ok, reversed} ->
      case cast_form_path_segment(segment) do
        {:ok, casted} -> {:cont, {:ok, [casted | reversed]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, [key | reversed_path]} -> {:ok, Enum.reverse(reversed_path), key}
      error -> error
    end
  end

  defp cast_form_path_segment(segment) do
    case Integer.parse(segment) do
      {idx, ""} ->
        {:ok, idx}

      _ ->
        {:ok, String.to_existing_atom(segment)}
    end
  rescue
    ArgumentError -> {:error, :invalid_field_segment}
  end

  defp maybe_send_ai_update_to_blocks(
         %{assigns: %{has_blocks?: false}} = socket,
         _string_path,
         _generated_text
       ),
       do: socket

  defp maybe_send_ai_update_to_blocks(socket, string_path, generated_text) do
    if string_path == ["__force_change"] do
      socket
    else
      access_path = string_path_to_access_path(string_path)
      send_updated_entry_field_to_blocks(socket, access_path, generated_text, hd(string_path))
    end
  end

  # An accepted AI suggestion written into a field as if typed: shipped to
  # the other editors, passed to the blocks that read the field and to the
  # preview.
  defp write_ai_text(socket, path, key, string_path, field_atom, text) do
    socket
    |> update_changeset(path, key, text)
    |> maybe_send_ai_update_to_blocks(string_path, text)
    |> maybe_invalidate_live_preview_assign(string_path, :string_path)
    |> maybe_fetch_root_blocks(:live_preview_update, 0)
    |> maybe_force_ai_component_remount(socket.assigns.form_blueprint, field_atom)
  end

  # What the suggestion panel needs to ask the model. The prompt is built in
  # its task (`build`), from the fields the action reads as the form has them
  # now; nothing to read is an error, not a prompt for the model to make
  # something up from. `original` is the field's value now, so Accept can
  # tell whether it changed since.
  defp field_action_run(socket, field, ai_action, type, blocks) do
    original = get_field(socket.assigns.form.source, field)
    context = ai_context_fun(socket, ai_action.from, blocks)
    language = field_action_language(socket)

    # An action from `ai:` or a site prompt sends its prompt even with
    # nothing to read, as `ai:` did.
    needs_inputs? = FieldAction.needs_inputs?(ai_action)

    build = fn ->
      case context.() do
        [] when needs_inputs? -> {:error, :empty_inputs}
        values -> {:ok, FieldAction.prompt(ai_action, values, language: language, type: type)}
      end
    end

    %{
      action: ai_action.name,
      label: FieldActions.label(socket.assigns.schema, ai_action),
      max: ai_action.max,
      original: original,
      warning: field_action_warning(type, original),
      build: build,
      ai_opts: FieldAction.ai_opts(ai_action)
    }
  end

  defp field_action_warning(:rich_text, html) do
    if FieldAction.formatting_lost?(html),
      do: gettext("Accepting replaces the field's text, with its formatting, links and footnotes.")
  end

  defp field_action_warning(_type, _value), do: nil

  # A translatable entry is written in its language, as the form has it now.
  defp field_action_language(%{assigns: %{schema: schema, form: form}}) do
    if schema.has_trait(Brando.Trait.Translatable) do
      case get_field(form.source, :language) do
        language when language not in [nil, ""] -> to_string(language)
        _ -> nil
      end
    end
  end

  defp maybe_force_ai_component_remount(socket, form_blueprint, field_atom) do
    case BlueprintForms.get_field(field_atom, form_blueprint) do
      %{type: :rich_text} -> force_svelte_remounts(socket, [field_atom])
      _ -> socket
    end
  end

  defp safe_to_existing_atom(value) when is_atom(value), do: {:ok, value}

  defp safe_to_existing_atom(value) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> {:error, :invalid_field}
  end

  defp safe_to_existing_atom(_), do: {:error, :invalid_field}

  # used for updating schema assets

  def update_changeset(socket, [], key, arg) do
    # empty path, treat as root field
    update_changeset(socket, key, arg)
  end

  def update_changeset(socket, path, key, list) when is_list(list) do
    changeset = socket.assigns.form.source

    new_changeset =
      EctoNestedChangeset.update_at(changeset, path ++ [key], fn _ ->
        Enum.map(list, &Map.from_struct/1)
      end)

    socket |> put_written_form(to_form(new_changeset, []))
  end

  def update_changeset(socket, path, key, map) when is_list(path) and is_map(map) do
    changeset = socket.assigns.form.source

    new_changeset =
      EctoNestedChangeset.update_at(changeset, path ++ [key], fn _ -> Map.from_struct(map) end)

    socket |> put_written_form(to_form(new_changeset, []))
  end

  def update_changeset(socket, path, key, value) when is_list(path) do
    # The re-bake below moves pending changes into `data`, where they no
    # longer read as changes: ship them first.
    socket = ship_all_field_changes(socket)

    changeset =
      socket.assigns.form.source
      |> apply_changes()
      |> change()

    new_changeset = EctoNestedChangeset.update_at(changeset, path ++ [key], fn _ -> value end)

    socket |> put_written_form(to_form(new_changeset, []))
  end

  def update_changeset(socket, key, list) when is_list(list) do
    changeset = socket.assigns.form.source
    new_changeset = put_change(changeset, key, Enum.map(list, &Map.from_struct/1))

    socket |> put_written_form(to_form(new_changeset, []))
  end

  def update_changeset(socket, key, value) when is_map(value) do
    changeset = socket.assigns.form.source
    new_changeset = put_change(changeset, key, Map.from_struct(value))

    socket |> put_written_form(to_form(new_changeset, []))
  end

  def update_changeset(socket, key, value) do
    changeset = socket.assigns.form.source
    new_changeset = put_change(changeset, key, value)

    socket |> put_written_form(to_form(new_changeset, []))
  end

  defp sequence(gallery_images) do
    gallery_images
    |> Enum.with_index()
    |> Enum.map(fn {gi, idx} -> Map.put(gi, :sequence, idx) end)
  end

  defp string_path_to_atom_path(string_path) do
    Enum.map(string_path, fn segment ->
      case Integer.parse(segment) do
        {idx, ""} -> idx
        _ -> String.to_existing_atom(segment)
      end
    end)
  end

  defp string_path_to_access_path(string_path) do
    Enum.map(string_path, fn segment ->
      case Integer.parse(segment) do
        {idx, ""} -> Access.at(idx)
        _ -> segment |> String.to_existing_atom() |> Access.key()
      end
    end)
  end

  ##
  ## Function components

  def live_preview(assigns) do
    ~H"""
    <form
      id="live-preview-recovery"
      phx-change="noop"
      phx-auto-recover="recover_live_preview_state"
      phx-target={@target}
      class="hidden"
    >
      <input type="hidden" name="live_preview[cache_key]" value={@live_preview_cache_key} />
    </form>
    <%= if @live_preview_active? do %>
      <div
        class="live-preview-wrapper"
        phx-update="ignore"
        id="live-preview"
        phx-hook="Brando.LivePreview"
      >
        <div class="live-preview">
          <div class="live-preview-targets">
            <div class="live-preview-divider"></div>
            <button
              type="button"
              class="tiny live-preview-refresh"
              phx-click="refresh_live_preview"
              phx-target={@target}
              title={gettext("Refresh")}
            >
              <.icon name="refresh-cw" />
              <span>{gettext("Refresh")}</span>
            </button>
            <button
              type="button"
              class="tiny live-preview-blank"
              phx-click="open_live_preview_standalone"
              phx-target={@target}
            >
              {gettext("Open preview in new window")}
            </button>
            <div class="live-preview-targets-buttons">
              <button type="button" data-live-preview-target="desktop">
                <.icon name="monitor" />
                <span>1440px</span>
              </button>
              <button type="button" data-live-preview-target="tablet">
                <.icon name="tablet" />
                <span>768px</span>
              </button>
              <button type="button" data-live-preview-target="mobile">
                <.icon name="smartphone" />
                <span>375px</span>
              </button>
            </div>
          </div>
          <div class="live-preview-iframe-wrapper">
            <iframe
              data-live-preview-device={@live_preview_target}
              src={"/__livepreview?key=#{@live_preview_cache_key}"}
            ></iframe>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # Extract user-friendly error message from various video provider error formats
  # Supports: Mux, Cloudflare, S3, Bunny, Vimeo, etc.
  #
  # Errors Brando itself produces — `Brando.Uploads`' pre-flight validators and
  # the facade's backstop rescue — are atoms, and they come first: they are the
  # ones a site operator can act on, and the `inspect/1` fallback at the bottom
  # of this chain would otherwise put an internal atom in front of an editor.
  # `Brando.Uploads` owns the text so the picker and the transformer say the
  # same thing.
  defp extract_video_error_message(reason) when is_atom(reason) and not is_nil(reason),
    do: Brando.Uploads.video_upload_error_message(reason)

  defp extract_video_error_message({:unknown_strategy, _strategy} = reason),
    do: Brando.Uploads.video_upload_error_message(reason)

  defp extract_video_error_message(%{"error" => %{"messages" => messages}})
       when is_list(messages) do
    # Mux format: %{"error" => %{"messages" => [...]}}
    Enum.join(messages, ". ")
  end

  defp extract_video_error_message(%{"error" => %{"message" => message}})
       when is_binary(message) do
    # Generic format: %{"error" => %{"message" => "..."}}
    message
  end

  defp extract_video_error_message(%{"message" => message}) when is_binary(message) do
    # Simplified format: %{"message" => "..."}
    message
  end

  defp extract_video_error_message(error) when is_binary(error) do
    # Plain string error
    error
  end

  defp extract_video_error_message(error) do
    inspect(error)
  end

  # A delivery topic is a bearer token: anyone who can present it can subscribe
  # a form to another form's asset deliveries, and unguessability is the only
  # thing stopping them. So logs get enough to correlate the two sides of one
  # delivery and no more — printing it whole put a replayable credential into
  # every log aggregator.
  defp topic_ref("form:" <> uuid), do: "form:" <> String.slice(uuid, 0, 8) <> "…"
  defp topic_ref(other), do: inspect(other)

  # Inputs the image pipeline actually derives its output from. The drawer's
  # other fields (title / credits / alt) are metadata — the sizes on disk do
  # not depend on them.
  @processing_inputs [:focal, :path, :formats, :config_target]

  # The old gate was `status !== :processed`, which is wrong in both directions:
  #
  #   * it MISSES a focal-point change on an already-processed image — the
  #     drawer renders `FocalPoint` bound to this same form, so `:focal` arrives
  #     in these params, and without a re-queue every crop stays stale;
  #   * it FIRES on an unprocessed image even when the user only touched the alt
  #     text, and `queue_processing/4` deletes any matching job before inserting
  #     a new one, so closing the drawer twice while the first job is still
  #     running discards it and starts a second pass over the same files.
  defp requeue_processing?(%Changeset{changes: changes}, image) do
    if Enum.any?(@processing_inputs, &Map.has_key?(changes, &1)) do
      true
    else
      # Nothing processing-relevant changed. Still queue an unprocessed image —
      # the upload that created it may never have processed, and the drawer is
      # the only place the editor can recover that from — but not if a pass is
      # already in flight, which is the case the old gate kept restarting.
      image.status != :processed and not Images.Processing.processing_queued?(image)
    end
  end

  # `socket.assigns.schema` is the ENTRY schema. A nested video field — or a
  # block media ref — belongs to a different one, which the drawer carries on
  # `edit_video.schema`; the sibling upload trigger in `VideoDrawer.render/1` already
  # reads it that way. Hand-building `"video:<entry schema>:<field>"` here sent
  # provider (Mux/Bunny/Cloudflare) uploads to the entry's config instead of the
  # field's, so the resulting video was invisible to the originating picker and
  # lost its field-level configuration.
  #
  # The upload strategy + provider settings come from `get_config_for/1`;
  # `field` may be a block media ref (not a registered schema asset), so we
  # still don't look up `__asset_opts__` — that would crash for blocks.
  defp video_config_target(edit_video, entry_schema) do
    schema = Map.get(edit_video, :schema) || entry_schema

    # `nil` is an atom, so `serialize/1` accepts it as a field segment and emits
    # a trailing-colon target that resolves to nothing. Guard it here rather
    # than relying on the rescue.
    case Map.get(edit_video, :field) do
      field when field in [nil, ""] -> nil
      field -> Brando.Assets.ConfigTarget.serialize({"video", schema, field})
    end
  rescue
    # serialize/1 raises on a non-blueprint schema. A hard match here would take
    # the whole entry form down with it (see A2).
    ArgumentError -> nil
  end

  # No rescue here any more, and that is the change rather than an omission.
  #
  # This wrapper existed because provider clients raise rather than return on
  # some configuration failures, and an escaping exception takes the entry form
  # process down with every unsaved change in it (the A2 class). Both halves of
  # that are now handled a layer down, where all three call sites benefit:
  # `Brando.Uploads.validate_provider_video_intake/2` rejects a missing
  # credential before dispatch, and `Videos.Uploader.initiate_upload/3` carries
  # the broad rescue for genuinely unexpected provider exceptions. That function
  # documents itself as total.
  #
  # Keeping a second rescue here would have guarded only the one call site that
  # was never the problem — the picker and the transformer were the unguarded
  # ones — while making the facade's guarantee look untrusted.
  defp initiate_provider_upload(video_config, config_target, filename, user, file_meta) do
    Brando.Videos.Uploader.initiate_upload(filename, user,
      config: video_config,
      config_target: config_target,
      file_meta: file_meta
    )
  end

  defp start_provider_video_upload(socket, config_target, %{
         filename: filename,
         size: size,
         mime_type: mime_type,
         request_ref: request_ref
       }) do
    edit_video = socket.assigns.edit_video
    user = socket.assigns.current_user

    case Brando.Videos.get_config_for(config_target) do
      {:ok, video_config} ->
        case initiate_provider_upload(video_config, config_target, filename, user, %{
               name: filename,
               size: size,
               type: mime_type
             }) do
          {:ok, %{upload_url: _url, video: _video} = result} ->
            provider_video_upload_ready(socket, edit_video, result, filename, request_ref)

          {:error, reason} ->
            Logger.error("Failed to get video upload URL: #{inspect(reason)}")
            error_message = extract_video_error_message(reason)

            # Push error event to JavaScript hook
            {:ok,
             push_event(socket, "video_upload_url_error", %{
               error: error_message,
               filename: filename,
               request_ref: request_ref
             })}
        end

      {:error, reason} ->
        Logger.error("Failed to get video config: #{inspect(reason)}")
        error_message = extract_video_error_message(reason)

        # Push error event to JavaScript hook
        {:ok,
         push_event(socket, "video_upload_url_error", %{
           error: error_message,
           filename: filename,
           request_ref: request_ref
         })}
    end
  end

  defp provider_video_upload_ready(socket, edit_video, %{upload_url: url, video: video} = result, filename, request_ref) do
    # Subscribe to video updates
    Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:video:#{video.id}", link: true)

    # Update edit_video with the created video
    edit_video = Map.put(edit_video, :video, video)
    video_changeset = change(video)

    # Build event payload - include tus_auth for Bunny uploads
    event_payload = %{
      upload_url: url,
      video_id: video.id,
      filename: filename,
      request_ref: request_ref
    }

    event_payload =
      case Map.get(result, :tus_auth) do
        nil -> event_payload
        tus_auth -> Map.put(event_payload, :tus_auth, tus_auth)
      end

    # Push event to JavaScript hook with upload URL
    {:ok,
     socket
     |> assign(:edit_video, edit_video)
     |> assign(:video_changeset, video_changeset)
     |> push_event("video_upload_url_ready", event_payload)}
  end

  defp relation_field_key(%{field: relation_key}, _field) when not is_nil(relation_key),
    do: relation_key

  defp relation_field_key(_relation_field, field) when is_atom(field) do
    candidate = "#{field}_id"

    try do
      String.to_existing_atom(candidate)
    rescue
      ArgumentError -> field
    end
  end

  defp relation_field_key(_relation_field, field), do: field

  # The fields each drawer lets you type into. These are the values that used to
  # be lost: the drawer's own edit form is `:if={@image_changeset}`-gated, so on
  # reconnect it exists in neither the old nor the new DOM when LiveView's
  # recovery diff runs, and LiveView only recovers forms it can see. The
  # always-rendered recovery form below carries them instead.
  @image_drawer_fields [:title, :credits, :alt]
  @video_drawer_fields [:source_url, :type]
  @file_drawer_fields [:title]

  defp restore_image_drawer(socket, params) do
    resource_id = String.to_integer(params["resource_id"])

    case Images.get_image(resource_id) do
      {:ok, image} ->
        edit_image = %{
          id: resource_id,
          path: decode_recovery_path(params["path"]),
          field: String.to_existing_atom(params["field"]),
          relation_field: nil,
          schema: String.to_existing_atom(params["schema"]),
          form_id: params["form_id"],
          image: image
        }

        {:noreply,
         socket
         |> assign(:edit_image, edit_image)
         |> assign(:editing_image?, true)
         |> assign(:image_changeset, replay_drawer_changes(image, params, @image_drawer_fields))
         |> assign_drawer_recovery_state()
         |> push_event("b:show_drawer", %{drawer_id: "image-drawer"})}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp restore_video_drawer(socket, params) do
    resource_id = String.to_integer(params["resource_id"])

    case Brando.Videos.get_video(%{matches: %{id: resource_id}, preload: [:thumbnail, :file]}) do
      {:ok, video} ->
        edit_video = %{
          id: resource_id,
          path: decode_recovery_path(params["path"]),
          field: String.to_existing_atom(params["field"]),
          relation_field: nil,
          schema: String.to_existing_atom(params["schema"]),
          form_id: params["form_id"],
          video: video
        }

        {:noreply,
         socket
         |> assign(:edit_video, edit_video)
         |> assign(:editing_video?, true)
         |> assign(:video_changeset, replay_drawer_changes(video, params, @video_drawer_fields))
         |> assign_drawer_recovery_state()
         |> push_event("b:show_drawer", %{drawer_id: "video-drawer"})}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp restore_file_drawer(socket, params) do
    resource_id = String.to_integer(params["resource_id"])

    case Brando.Files.get_file(resource_id) do
      {:ok, file} ->
        edit_file = %{
          id: resource_id,
          path: decode_recovery_path(params["path"]),
          field: String.to_existing_atom(params["field"]),
          relation_field: nil,
          schema: String.to_existing_atom(params["schema"]),
          form_id: params["form_id"],
          file: file
        }

        {:noreply,
         socket
         |> assign(:edit_file, edit_file)
         |> assign(:editing_file?, true)
         |> assign(:file_changeset, replay_drawer_changes(file, params, @file_drawer_fields))
         |> assign_drawer_recovery_state()
         |> push_event("b:show_drawer", %{drawer_id: "file-drawer"})}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp drawer_fields("image"), do: @image_drawer_fields
  defp drawer_fields("video"), do: @video_drawer_fields
  defp drawer_fields("file"), do: @file_drawer_fields
  defp drawer_fields(_type), do: []

  # Replay the drawer edits that were in flight when the process died, on top of
  # the freshly loaded resource. `cast/3` rather than `change/2` on purpose: the
  # values arrive as strings from a hidden input, and `type` on a video is an
  # enum that `change/2` would happily store unconverted.
  defp replay_drawer_changes(resource, params, allowed_fields) do
    case decode_drawer_changes(params["changes"]) do
      changes when map_size(changes) == 0 -> Changeset.change(resource)
      changes -> Changeset.cast(resource, changes, allowed_fields)
    end
  end

  defp decode_drawer_changes(json) when is_binary(json) and json != "" do
    case Jason.decode(json) do
      {:ok, %{} = changes} -> changes
      _ -> %{}
    end
  end

  defp decode_drawer_changes(_json), do: %{}

  defp assign_drawer_recovery_state(socket) do
    {type, resource_id, field, path, schema, changeset} = editing_drawer(socket.assigns)

    socket
    |> assign(:editing_drawer_type, type)
    |> assign(:editing_resource_id, resource_id)
    |> assign(:editing_field, field && to_string(field))
    |> assign(:editing_path, path || [])
    |> assign(:editing_schema, schema && to_string(schema))
    |> assign(:editing_drawer_changes, encode_drawer_changes(type, changeset))
  end

  defp editing_drawer(assigns) do
    %{
      editing_image?: editing_image?,
      editing_video?: editing_video?,
      editing_file?: editing_file?,
      edit_image: edit_image,
      edit_video: edit_video,
      edit_file: edit_file
    } = assigns

    cond do
      editing_image? and edit_image[:id] ->
        {"image", edit_image.id, edit_image[:field], edit_image[:path], edit_image[:schema], assigns[:image_changeset]}

      editing_video? and edit_video[:id] ->
        {"video", edit_video.id, edit_video[:field], edit_video[:path], edit_video[:schema], assigns[:video_changeset]}

      editing_file? and edit_file[:id] ->
        {"file", edit_file.id, edit_file[:field], edit_file[:path], edit_file[:schema], assigns[:file_changeset]}

      true ->
        {nil, nil, nil, [], nil, nil}
    end
  end

  # Only what the user actually changed, and only the text fields — everything
  # else in a drawer changeset either is not JSON-encodable or is not something
  # the drawer can edit. An empty map is the common case and encodes to "{}".
  defp encode_drawer_changes(type, %Changeset{changes: changes}) do
    changes
    |> Map.take(drawer_fields(type))
    |> Jason.encode!()
  end

  defp encode_drawer_changes(_type, _changeset), do: "{}"

  defp decode_recovery_path(path_json) when is_binary(path_json) do
    case Jason.decode(path_json) do
      {:ok, list} when is_list(list) -> Enum.map(list, &String.to_existing_atom/1)
      _ -> []
    end
  end

  defp decode_recovery_path(_), do: []

  defp image_editor_payload(image) do
    crop_groups =
      case Images.get_config_for(image) do
        {:ok, config} -> build_crop_groups(config.sizes)
        _ -> []
      end

    %{
      image_id: image.id,
      image_src: Brando.Utils.img_url(image, :original, prefix: Brando.Utils.media_url()),
      image_width: image.width,
      image_height: image.height,
      focal_x: (image.focal && image.focal.x) || 50,
      focal_y: (image.focal && image.focal.y) || 50,
      crop_groups: crop_groups,
      config_target: image.config_target
    }
  end

  @doc """
  Build crop groups from image config sizes.

  Groups crop sizes by their aspect ratio and returns a list of maps
  with `ratio`, `label`, and `size_keys` for the image editor.
  """
  def build_crop_groups(nil), do: []

  def build_crop_groups(sizes) when is_map(sizes) do
    sizes
    |> Enum.filter(fn {key, cfg} ->
      is_map(cfg) and cfg["crop"] == true and to_string(key) != "thumb"
    end)
    |> Enum.map(fn {key, cfg} ->
      {w, h} = Images.Operations.Sizing.get_crop_dimensions_from_cfg(cfg)
      ratio = w / h
      %{key: to_string(key), width: w, height: h, ratio: ratio}
    end)
    |> Enum.group_by(fn s -> Float.round(s.ratio, 4) end)
    |> Enum.map(fn {ratio, group_sizes} ->
      {num, den} = rationalize(ratio)

      %{
        ratio: ratio,
        label: "#{num}:#{den}",
        size_keys: Enum.map(group_sizes, & &1.key)
      }
    end)
  end

  def build_crop_groups(_), do: []

  @doc """
  Build crop groups from an image's resolved config.

  Convenience over `build_crop_groups/1` for call sites that hold an image
  struct rather than a size config.
  """
  def build_crop_groups_for(image) do
    case Images.get_config_for(image) do
      {:ok, config} -> build_crop_groups(config.sizes)
      _ -> []
    end
  end

  defp rationalize(ratio) when is_float(ratio) do
    # Try common ratios first
    common_ratios = [
      {1.0, {1, 1}},
      {4 / 3, {4, 3}},
      {3 / 2, {3, 2}},
      {16 / 9, {16, 9}},
      {21 / 9, {21, 9}},
      {3 / 4, {3, 4}},
      {2 / 3, {2, 3}},
      {9 / 16, {9, 16}},
      {5 / 4, {5, 4}},
      {4 / 5, {4, 5}}
    ]

    Enum.find_value(common_ratios, fn {r, label} ->
      if abs(ratio - r) < 0.01, do: label
    end) ||
      approximate_ratio(ratio)
  end

  defp approximate_ratio(ratio) do
    # Find closest integer ratio within reasonable bounds
    best =
      for den <- 1..20, reduce: {round(ratio), 1} do
        {best_num, best_den} ->
          num = round(ratio * den)

          if abs(num / den - ratio) < abs(best_num / best_den - ratio),
            do: {num, den},
            else: {best_num, best_den}
      end

    best
  end

  # "Save and create new" needs somewhere to go: singletons such as the
  # identity have no create route.
  defp can_create_new?(schema) do
    BrandoAdmin.Authorization.allowed?(:create, schema) and is_binary(schema.__admin_route__(:create, []))
  rescue
    UndefinedFunctionError -> false
    FunctionClauseError -> false
    ArgumentError -> false
  end

  # A new entry of a translatable schema takes the content language chosen in
  # the sidebar. Where the form has no language field of its own, say which.
  attr :entry_id, :any, required: true
  attr :schema, :atom, required: true
  attr :form_blueprint, :any, required: true
  attr :current_user, :map, required: true

  defp creating_language(assigns) do
    assigns = assign(assigns, :language, creating_language_label(assigns))

    ~H"""
    <p :if={@language} class="form-creating-language">
      {gettext("Creating in %{language}", language: @language)}
    </p>
    """
  end

  defp creating_language_label(%{entry_id: nil, schema: schema, form_blueprint: blueprint, current_user: user}) do
    languages = Brando.config(:languages) || []

    if schema.has_trait(Brando.Trait.Translatable) and length(languages) > 1 and
         not language_input?(blueprint) do
      code = user.config.content_language
      language_text(languages, code)
    end
  end

  defp creating_language_label(_assigns), do: nil

  defp language_text(languages, code) do
    Enum.find_value(languages, code, fn language ->
      if to_string(language[:value]) == to_string(code), do: language[:text]
    end)
  end

  defp language_input?(%{tabs: tabs}), do: Enum.any?(tabs, &has_language_input?/1)
  defp language_input?(_blueprint), do: false

  defp has_language_input?(%{fields: fields}), do: Enum.any?(fields, &has_language_input?/1)
  defp has_language_input?(%{name: :language}), do: true
  defp has_language_input?(_field), do: false

  defp validate(params, socket, recovery?) do
    # This is also the recovery event for the main form, and it is what
    # rebuilds the entry from the recovered params — see
    # `maybe_finish_live_preview_recovery/1`.
    socket = socket |> assign(:form_recovered?, true) |> Translation.put_acknowledged(params)
    schema = socket.assigns.schema
    entry = socket.assigns.entry
    singular = socket.assigns.singular
    has_blocks? = socket.assigns.has_blocks?

    entry_params = Map.get(params, singular)
    entry_or_default = entry || struct(schema)
    previous = socket.assigns.form.source
    target = target_field(socket, singular, params["_target"])

    {changeset, echoed} = cast_entry_edit(socket, entry_or_default, entry_params, target)
    changeset = Map.put(changeset, :action, :validate)

    edit = %{previous: previous, echoed: echoed, target: target, params: params, entry_params: entry_params}
    {changeset, socket, offline} = settle_edit(recovery?, socket, changeset, edit)

    # The recomputed form is assigned before the `_target` branch, and that
    # placement is load-bearing. Form *recovery* pushes this same event with a
    # `_target` naming the first non-hidden input in the form — which here is
    # the `image_editor_upload` file input a few lines into the markup, not an
    # entry field (`view.ts:2450`, `channel.ex:848-853`). Assigning inside the
    # `[^singular | rest]` branch meant every recovered value was recomputed and
    # then dropped, so a reconnect silently restored nothing.
    socket = socket |> put_form(to_form(changeset, [])) |> broadcast_dirty_fields() |> Drafts.dirty()
    socket = if recovery?, do: share_recovered(socket, offline, entry_params), else: socket

    case Map.get(params, "_target") do
      [^singular | rest] ->
        if has_blocks? && rest != ["__force_change"] do
          # `rest` is the path *below* the singular, so it has to be read out of
          # `entry_params`, not out of the top-level params map — `params` is
          # `%{"page" => %{"title" => …}}`, so `get_in(params, ["title"])` is
          # always nil. Every block rendering `{{ entry.title }}` therefore blanked
          # its entry variables the moment you typed in that field, and stayed
          # blank until reload. Invisible until a fixture had a module that reads
          # the entry — see `/bench-entry-consumers`.
          #
          # The two representations differ on purpose: `path` walks the entry
          # *struct* (list indices as `Access.at/1`), `rest` walks the params
          # *map* (list indices as "0" keys).
          path = string_path_to_access_path(rest)
          change = get_in(entry_params, rest)
          send_updated_entry_field_to_blocks(socket, path, change, hd(rest))
        end

        if rest == ["language"] do
          request_select_options_update(socket)
        end

        if rest != ["__force_change"], do: FrontendEditor.field_changed(socket)

        socket
        |> maybe_invalidate_live_preview_assign(rest, :string_path)
        |> maybe_fetch_root_blocks(:live_preview_update, 0)
        |> maybe_finish_live_preview_recovery()
        |> then(&{:noreply, &1})

      # Anything else — a target outside the entry, or none at all. A missing
      # `_target` used to raise `CaseClauseError` here and take the form
      # LiveView down with every unsaved edit in it.
      _ ->
        {:noreply, maybe_finish_live_preview_recovery(socket)}
    end
  end
end
