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

  alias Brando.Blueprint.Callback
  alias Brando.Blueprint.Forms, as: BlueprintForms
  alias Brando.Villain
  alias BrandoAdmin.Components.Button
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.FilePicker
  alias BrandoAdmin.Components.Form.AlternatesDrawer
  alias BrandoAdmin.Components.Form.BlockField
  alias BrandoAdmin.Components.Form.Fieldset
  alias BrandoAdmin.Components.Form.FileDrawer
  alias BrandoAdmin.Components.Form.ImageDrawer
  alias BrandoAdmin.Components.Form.Input.Blocks.TipTapLinkDialog
  alias BrandoAdmin.Components.Form.Input.MultiSelect
  alias BrandoAdmin.Components.Form.Input.Select
  alias BrandoAdmin.Components.Form.MetaDrawer
  alias BrandoAdmin.Components.Form.Primitives
  alias BrandoAdmin.Components.Form.RevisionsDrawer
  alias BrandoAdmin.Components.Form.ScheduledPublishingDrawer
  alias BrandoAdmin.Components.Form.VideoDrawer
  alias BrandoAdmin.Components.ImagePicker
  alias BrandoAdmin.Components.SplitDropdown
  alias BrandoAdmin.Components.VideoPicker

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
     |> assign(:entry_loading?, false)
     |> assign(:blocks_ready?, true)
     |> assign(:entry_load_status, nil)
     |> assign(:dirty_fields, [])
     |> assign(:editing_image?, false)
     |> assign(:editing_file?, false)
     |> assign(:editing_video?, false)
     |> assign(:video_context, :asset)
     |> assign(:active_video_tab, "upload")
     |> assign(:processing_images, [])
     |> assign(:presences, %{})
     |> assign(:has_meta?, false)
     |> assign(:status_revisions, :closed)
     |> assign(:processing, false)
     |> assign(:save_redirect_target, :listing)
     |> assign(:live_preview_target, "desktop")
     |> assign(:live_preview_ready?, false)
     |> assign(:live_preview_active?, false)
     |> assign(:live_preview_cache_key, nil)
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
  def update(%{event: "ship_field_changes"}, socket) do
    {:ok, ship_all_field_changes(socket)}
  end

  # Re-broadcast our focused field for a late joiner — field presence
  # indicators are event-driven, so a joiner would otherwise not see the
  # field we're editing as locked (triggered from the blocks_sync_request
  # handler in LiveView.Form alongside ship_field_changes)
  def update(%{event: "reship_active_field"}, socket) do
    entry = socket.assigns[:entry]
    field = socket.assigns[:focused_field]

    if field && entry && entry.id do
      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        "brando:active_field:#{entry.id}",
        {:active_field, field, socket.assigns.current_user.id}
      )
    end

    {:ok, socket}
  end

  # Apply field changes received from another user
  def update(%{event: "apply_remote_field_changes", changes: changes}, socket) do
    changeset = socket.assigns.form.source
    schema = changeset.data.__struct__

    # Build a set of image/video/file FK fields so we can load associations
    asset_fk_map = build_asset_fk_map(schema)

    updated_changeset =
      Enum.reduce(changes, changeset, fn %{field: field, value: value, assoc?: assoc?}, cs ->
        cs =
          if assoc? do
            Ecto.Changeset.put_assoc(cs, field, value)
          else
            Ecto.Changeset.put_change(cs, field, value)
          end

        # If this is an asset FK (e.g. :cover_id), load the record
        # and put it directly on the changeset data (not via put_assoc,
        # which can fail with :on_replace => :update)
        case Map.get(asset_fk_map, field) do
          nil ->
            cs

          {assoc_field, asset_schema} ->
            case Brando.Repo.get(asset_schema, value) do
              nil ->
                cs

              record ->
                updated_data = Map.put(cs.data, assoc_field, record)
                %{cs | data: updated_data}
            end
        end
      end)

    {:ok,
     socket
     |> assign(:form, to_form(updated_changeset, []))
     |> force_svelte_remounts()}
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
    image_changeset = change(%Brando.Images.Image{})

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
        %{
          event: "update_live_preview_block",
          rendered_html: rendered_html,
          uid: uid,
          has_children?: has_children?
        },
        socket
      ) do
    cache_key = socket.assigns.live_preview_cache_key

    Brando.endpoint().broadcast("live_preview:#{cache_key}", "update_block", %{
      uid: uid,
      rendered_html: rendered_html,
      has_children: has_children?
    })

    {:ok, socket}
  end

  def update(%{event: "get_live_preview_status", block_ref: {mod, id}}, socket) do
    cache_key = socket.assigns.live_preview_cache_key
    live_preview_active = socket.assigns.live_preview_active?
    event = (live_preview_active && "enable_live_preview") || "disable_live_preview"

    send_update(mod, id: id, event: event, cache_key: cache_key)

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

  def update(%{action: :update_entry_hard_reset, updated_entry: updated_entry}, socket) do
    send_update_after(__MODULE__, [id: socket.assigns.id, event: "set_block_map"], 1000)
    send(self(), {:progress_popup, "Setting new block map..."})

    socket
    |> assign(:entry, updated_entry)
    |> assign_refreshed_form()
    |> assign(:block_map, [])
    |> assign_entry_for_blocks()
    |> clear_blocks_root_changesets()
    |> reload_all_blocks()
    |> force_svelte_remounts()
    |> then(&{:ok, &1})
  end

  def update(%{action: :update_entry, updated_entry: updated_entry}, socket) do
    %{schema: schema, current_user: current_user} = socket.assigns
    new_changeset = schema.changeset(updated_entry, %{}, current_user)

    send_update_after(__MODULE__, [id: socket.assigns.id, event: "set_block_map"], 500)

    {:ok,
     socket
     |> assign(:entry, updated_entry)
     |> assign(:form, to_form(new_changeset, []))
     |> assign(:block_map, [])
     |> force_svelte_remounts()}
  end

  def update(
        %{updated_entry: updated_entry},
        %{assigns: %{schema: schema, current_user: current_user}} = socket
      ) do
    raise "DEPRECATE form.ex:updated_entry —— use action: :update_entry instead"
    new_changeset = schema.changeset(updated_entry, %{}, current_user)

    {:ok,
     socket
     |> assign(:form, to_form(new_changeset, []))
     |> force_svelte_remounts()}
  end

  def update(%{event: "set_block_map"}, socket) do
    {:ok,
     socket
     |> assign_block_map()
     |> assign_entry_for_blocks()}
  end

  # got all root changesets for the block field
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

  def update(
        %{action: :update_changeset, changeset: updated_changeset, force_validation: true},
        socket
      ) do
    {:ok,
     socket
     |> assign(:form, to_form(updated_changeset, []))
     |> push_event("b:validate", %{})
     |> force_svelte_remounts()}
  end

  def update(%{action: :update_changeset, changeset: updated_changeset}, socket) do
    updated_form = to_form(updated_changeset, [])

    {:ok, assign(socket, :form, updated_form)}
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
     |> assign(:form, to_form(updated_changeset, []))
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
     |> assign(:form, to_form(updated_changeset))
     |> force_svelte_remounts()}
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

    {:ok, assign(socket, :form, updated_form)}
  end

  # Async entry-load progress, reported from the loading task via
  # send_update/3 — keeps the loading overlay's status current.
  def update(%{action: :entry_load_progress, status: status}, socket) do
    {:ok, assign(socket, :entry_load_status, status)}
  end

  # Second phase of the async load: the entry + form fields rendered in the
  # previous cycle, now let the block components mount. Deferred one render
  # cycle (send_update_after) so the "building block editor" status actually
  # paints before the server spends seconds rendering a large block tree.
  def update(%{action: :render_blocks}, socket) do
    {:ok, assign(socket, :blocks_ready?, true)}
  end

  def update(assigns, socket) do
    form_name = assigns[:name] || :default

    socket =
      socket
      |> assign(assigns)
      |> assign_new(:entry_id, fn -> nil end)
      |> assign_new(:singular, fn -> assigns.schema.__naming__().singular end)
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
      |> assign_new(:header, fn ->
        IO.warn("""

        No <:header> slot is defined for form component with schema `#{inspect(assigns.schema)}`.

        It is recommended to use this instead of a standalone `<Content.header>` component
        for better integration with Live Previews!

        Example:

            <.live_component module={Form}
              id="page_form"
              entry_id={@entry_id}
              current_user={@current_user}
              schema={@schema}>
              <:header>
                <%= gettext("Edit page") %>
              </:header>
            </.live_component>

        """)

        nil
      end)
      |> assign_new(:instructions, fn -> [] end)
      |> assign_new(:active_video_tab, fn -> "upload" end)
      |> assign_new(:video_context, fn -> :asset end)

    cond do
      # async load in flight — parent re-rendered (presence etc.); the new
      # props are assigned above, nothing to build until the entry lands
      socket.assigns.entry_loading? ->
        {:ok, socket}

      # editing an existing entry: load it off-process so the form shell and
      # loading overlay paint immediately instead of blocking on the query
      socket.assigns.initial_update && socket.assigns.entry_id ->
        {:ok, start_entry_load(socket)}

      true ->
        {:ok, socket |> assign_entry() |> finish_form_update()}
    end
  end

  # The tail of the update pipeline — expects :entry to be assigned. Runs
  # synchronously for create forms and subsequent parent updates, and from
  # handle_async/3 once the async-loaded entry arrives.
  defp finish_form_update(socket) do
    socket
    |> assign_addon_statuses()
    |> assign_default_params()
    |> extract_tab_names()
    |> assign_form()
    |> maybe_assign_uploads()
    |> maybe_assign_block_map()
    |> maybe_assign_entry_for_blocks()
    |> assign(:initial_update, false)
  end

  defp start_entry_load(socket) do
    %{
      schema: schema,
      form_blueprint: form_blueprint,
      entry_id: entry_id,
      singular: singular,
      context: context,
      id: form_id
    } = socket.assigns

    if Application.get_env(Brando.config(:otp_app), :sql_sandbox) do
      # Sandboxed e2e runs use ownership :auto mode, where the async task's
      # fresh connection escapes the per-test sandbox transaction and cannot
      # see test-created entries (same class of problem as
      # :sql_sandbox_serial_preloads) — load in-process instead.
      entry = load_entry_with_progress(nil, form_id, schema, form_blueprint, entry_id, singular, context)

      socket
      |> assign(:entry, entry)
      |> finish_form_update()
    else
      lv_pid = self()
      has_blocks? = schema.has_trait(Brando.Trait.Blocks)

      socket
      |> assign(:entry_loading?, true)
      |> assign(:blocks_ready?, false)
      |> assign(:entry_load_status, %{phase: :entry, blocks?: has_blocks?, block_count: nil})
      |> start_async(
        :entry_load,
        # The tenant prefix lives in the process dictionary, which a fresh async
        # task does not inherit — without this the query runs against `public`.
        Brando.Tenant.capture_context(fn ->
          load_entry_with_progress(lv_pid, form_id, schema, form_blueprint, entry_id, singular, context)
        end)
      )
    end
  end

  # Runs inside the async task. Splits the load in two so we can report real
  # progress: the entry itself (fast) first, then the heavy recursive block
  # preloads — with a cheap count in between so the overlay can say how many
  # blocks are coming. Custom form queries pass through untouched (we can't
  # split preloads we don't own), so they load in one step.
  defp load_entry_with_progress(lv_pid, form_id, schema, form_blueprint, entry_id, singular, context) do
    has_blocks? = schema.has_trait(Brando.Trait.Blocks)
    split_blocks? = has_blocks? && is_nil(form_blueprint.query)

    query_params =
      entry_id
      |> maybe_query(form_blueprint)
      |> add_preloads(schema, form_blueprint, skip_blocks: split_blocks?)
      |> Map.put(:with_deleted, true)

    entry =
      case apply(context, :"get_#{singular}", [query_params]) do
        {:ok, entry} -> entry
        {:error, _err} -> raise Brando.Exception.EntryNotFoundError
      end

    if split_blocks? do
      if lv_pid do
        block_count = Brando.Content.Blocks.count_entry_blocks(schema, entry_id)

        send_update(lv_pid, __MODULE__,
          id: form_id,
          action: :entry_load_progress,
          status: %{phase: :blocks, blocks?: true, block_count: block_count}
        )
      end

      Brando.Repo.preload(entry, Brando.Content.Blocks.preloads_for(schema))
    else
      entry
    end
  end

  def handle_async(:entry_load, {:ok, entry}, socket) do
    socket =
      socket
      |> assign(:entry, entry)
      |> assign(:entry_loading?, false)
      |> finish_form_update()

    socket =
      if socket.assigns.has_blocks? do
        # let this cycle's diff (form fields + updated status) reach the
        # client before the expensive block render pass starts
        send_update_after(__MODULE__, [id: socket.assigns.id, action: :render_blocks], 50)

        update(socket, :entry_load_status, fn
          %{} = status -> %{status | phase: :rendering}
          nil -> nil
        end)
      else
        assign(socket, :blocks_ready?, true)
      end

    {:noreply, socket}
  end

  def handle_async(:entry_load, {:exit, reason}, _socket) do
    # surface load failures exactly like the old synchronous load did
    case reason do
      {exception, stacktrace} when is_exception(exception) -> reraise(exception, stacktrace)
      other -> exit(other)
    end
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
  # BUTTON (`close_image/1`). Dismissing the drawer any other way (Esc, backdrop,
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

    entry_or_default = socket.assigns.entry || struct(socket.assigns.schema)
    updated_entry = Map.put(entry_or_default, field, asset)

    socket
    |> assign(:entry, updated_entry)
    |> assign(:form, to_form(updated_changeset, []))
    # Ship while the FK is still a change — the drawer-save path re-bakes the
    # changeset (apply_changes/change), after which there is nothing to ship.
    |> ship_all_field_changes()
    |> push_event("b:validate", %{
      target: "#{socket.assigns.singular}[#{relation_key}]",
      value: asset.id
    })
  end

  # Append a delivered asset to the gallery assoc: existing objects are
  # slimmed to plain maps (put_assoc with mixed nil-ID structs would raise
  # duplicate-PK — see CLAUDE.md "put_assoc with multiple new records"),
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
    changeset = socket.assigns.form.source
    current_gallery = gallery_at(changeset, path, key) || %Brando.Galleries.Gallery{}

    gallery_changeset =
      current_gallery
      |> forget_unsaved_objects()
      |> change(%{config_target: new_gallery.config_target})
      |> put_assoc(:gallery_objects, new_gallery.gallery_objects)

    updated_changeset =
      if path == [] do
        put_assoc(changeset, key, gallery_changeset)
      else
        EctoNestedChangeset.update_at(changeset, path ++ [key], fn _ -> gallery_changeset end)
      end

    assign(socket, :form, to_form(updated_changeset, []))
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

  defp assign_entry(%{assigns: %{initial_update: false}} = socket) do
    socket
  end

  defp assign_entry(%{assigns: %{entry_id: nil}} = socket) do
    schema = socket.assigns.schema
    current_user = socket.assigns.current_user
    assign(socket, :entry, prepare_empty_entry(schema, current_user))
  end

  # Editing an existing entry never reaches this far — the update-form path
  # loads the entry asynchronously (start_entry_load/1) before the pipeline
  # runs, so only the skip- and create-clauses above remain.

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

    assign(socket, :entry, apply(context, :"get_#{singular}!", [query_params]))
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
    socket
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

    Brando.LivePreview.update(schema, changeset, cache_key, updated_entry_assocs)

    socket
  end

  defp maybe_full_rerender_live_preview(%{assigns: %{has_blocks?: true}} = socket, true) do
    fetch_root_blocks(socket, :live_preview_full_rerender, 1200)
    socket
  end

  defp maybe_full_rerender_live_preview(socket, false) do
    socket
  end

  defp maybe_assign_block_map(socket) do
    blocks = socket.assigns.form_blueprint.blocks

    socket
    |> assign_new(:block_map, fn -> build_block_map(socket) end)
    |> assign_new(:block_changesets, fn -> Map.new(blocks, &{&1.name, nil}) end)
  end

  defp assign_block_map(socket) do
    blocks = socket.assigns.form_blueprint.blocks

    socket
    |> assign(:block_map, build_block_map(socket))
    |> assign(:block_changesets, Map.new(blocks, &{&1.name, nil}))
  end

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
    |> assign_transformer_statuses()
    |> assign(
      :has_alternates?,
      (schema.has_trait(Brando.Trait.Translatable) and schema.has_alternates?()) && entry.id
    )
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
    Brando.LivePreview.has_live_preview_target(schema)
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

  defp force_svelte_remounts(socket) do
    push_event(socket, "b:component:remount", %{})
  end

  # Maps FK fields (e.g. :cover_id) to {assoc_field, schema_module}
  # for loading associated records when receiving remote field changes.
  defp build_asset_fk_map(schema) do
    image_fields =
      if function_exported?(schema, :__image_fields__, 0),
        do: Enum.map(schema.__image_fields__(), &{:"#{&1.name}_id", {&1.name, Brando.Images.Image}}),
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

  # Ship all non-block changeset changes to other users.
  # Used on field blur, save, and after image/video/file selection.
  defp ship_all_field_changes(socket) do
    entry = socket.assigns[:entry]
    user_id = socket.assigns.current_user.id

    if entry && entry.id do
      do_ship_field_changes(socket, entry.id, user_id)
    else
      socket
    end
  end

  defp do_ship_field_changes(socket, entry_id, user_id) do
    changeset = socket.assigns.form.source
    schema = changeset.data.__struct__

    # Only ship belongs_to associations (FK changes), not has_many/many_to_many
    # which have complex nested changesets that can't be put_assoc'd on the receiver
    belongs_to_assocs =
      schema.__schema__(:associations)
      |> Enum.filter(fn assoc_name ->
        case schema.__schema__(:association, assoc_name) do
          %Ecto.Association.BelongsTo{} -> true
          _ -> false
        end
      end)

    # Exclude block-related fields, rendered fields, has_many/many_to_many assocs
    block_fields =
      if function_exported?(schema, :__blocks_fields__, 0) do
        schema.__blocks_fields__()
        |> Enum.flat_map(fn %{name: name} ->
          name_str = to_string(name)
          [name, :"rendered_#{name_str}", :"entry_#{name_str}"]
        end)
      else
        []
      end

    # Collect all has_many/many_to_many association names to skip
    all_assocs = schema.__schema__(:associations)
    has_many_assocs = all_assocs -- belongs_to_assocs

    skip_fields = [:updated_at, :inserted_at | block_fields ++ has_many_assocs]

    changes =
      changeset.changes
      |> Map.drop(skip_fields)
      |> Enum.map(fn {field, value} ->
        %{field: field, value: value, assoc?: field in belongs_to_assocs}
      end)

    if changes != [] do
      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        "brando:field_sync:#{entry_id}",
        {:fields_shipped, %{changes: changes, user_id: user_id}}
      )
    end

    socket
  end

  defp extract_tab_names(%{assigns: %{form_blueprint: %{tabs: tabs}}} = socket) do
    socket
    |> assign_new(:active_tab, fn ->
      first_tab = List.first(tabs)
      Map.get(first_tab, :name)
    end)
    |> assign_new(:tabs, fn -> Enum.map(tabs, & &1.name) end)
  end

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
      socket
      |> assign(:all_blocks_received?, true)
      |> assign(:all_transformers_received?, true)
      |> push_event("b:submit", %{})
    else
      socket
      |> then(fn s -> if blocks_ready?, do: assign(s, :all_blocks_received?, true), else: s end)
      |> then(fn s ->
        if transformers_ready?, do: assign(s, :all_transformers_received?, true), else: s
      end)
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

      {:ok, preview_url, expiration_days} =
        Brando.LivePreview.share(
          schema,
          changeset,
          user,
          updated_entry_assocs
        )

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
    end
  end

  # live preview for schema without blocks
  def event_tag_received(%{assigns: %{has_blocks?: false}} = socket, :live_preview) do
    changeset = socket.assigns.form.source
    updated_entry_assocs = socket.assigns.updated_entry_assocs
    schema = socket.assigns.schema

    if changeset.errors == [] do
      case Brando.LivePreview.initialize(schema, changeset, updated_entry_assocs) do
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
      |> push_errors(changeset, form_blueprint, schema)
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
        # fetch all blocks' rendered_html
        case Brando.LivePreview.initialize(schema, changeset, updated_entry_assocs) do
          {:ok, cache_key} ->
            socket
            |> assign(:live_preview_active?, true)
            |> assign(:live_preview_cache_key, cache_key)
            |> enable_live_preview_in_blocks()
            |> clear_blocks_root_changesets()
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
        socket
        |> clear_blocks_root_changesets()
        |> push_errors(changeset, form_blueprint, schema)
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

      Brando.LivePreview.update_cache(cache_key, schema, changeset, updated_entry_assocs)
      send(self(), {:toast, gettext("Opening standalone live preview...")})

      url = "/__livepreview?key=#{cache_key}&mode=standalone"

      socket
      |> push_event("b:open_window", %{url: url})
    else
      form_blueprint = socket.assigns.form_blueprint

      socket
      |> push_errors(changeset, form_blueprint, schema)
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

        Brando.LivePreview.update_cache(cache_key, schema, changeset, updated_entry_assocs)
        send(self(), {:toast, gettext("Opening standalone live preview...")})

        url = "/__livepreview?key=#{cache_key}&mode=standalone"

        socket
        |> clear_blocks_root_changesets()
        |> push_event("b:open_window", %{url: url})
      else
        socket
        |> clear_blocks_root_changesets()
        |> push_errors(changeset, form_blueprint, schema)
      end
    end
  end

  def event_tag_received(socket, :live_preview_full_rerender) do
    block_changesets = socket.assigns.block_changesets
    changeset = socket.assigns.form.source
    cache_key = socket.assigns.live_preview_cache_key
    updated_entry_assocs = socket.assigns.updated_entry_assocs

    if Enum.any?(Map.values(block_changesets), &is_nil/1) do
      socket
    else
      schema = socket.assigns.schema
      changeset = assoc_all_block_fields(block_changesets, changeset)
      Brando.LivePreview.rerender(schema, changeset, cache_key, updated_entry_assocs)
      clear_blocks_root_changesets(socket)
    end
  end

  # A media association changed — refresh the cached HTML for the SAME cache key and
  # tell the iframe to reload itself, letting the host frontend re-initialize and
  # mount the new video/gallery player. A morphdom rerender can't run the frontend's
  # JS boot for newly introduced media, so it would leave a gray box.
  #
  # We deliberately keep the same cache key: minting a new one (via `initialize`)
  # would desync the key held by every block component and break all subsequent
  # morphdom updates until live preview is toggled off and on again.
  def event_tag_received(socket, :live_preview_reload) do
    block_changesets = socket.assigns.block_changesets
    changeset = socket.assigns.form.source
    cache_key = socket.assigns.live_preview_cache_key
    updated_entry_assocs = socket.assigns.updated_entry_assocs

    if Enum.any?(Map.values(block_changesets), &is_nil/1) do
      socket
    else
      schema = socket.assigns.schema
      changeset = assoc_all_block_fields(block_changesets, changeset)
      Brando.LivePreview.reload(schema, changeset, cache_key, updated_entry_assocs)
      clear_blocks_root_changesets(socket)
    end
  end

  # when inserting or deleting blocks we want a full rerender of the live preview.
  def event_tag_received(socket, :live_preview_update) do
    block_changesets = socket.assigns.block_changesets
    changeset = socket.assigns.form.source
    cache_key = socket.assigns.live_preview_cache_key
    updated_entry_assocs = socket.assigns.updated_entry_assocs

    if Enum.any?(Map.values(block_changesets), &is_nil/1) do
      socket
    else
      schema = socket.assigns.schema
      changeset = assoc_all_block_fields(block_changesets, changeset)
      Brando.LivePreview.update(schema, changeset, cache_key, updated_entry_assocs)
      clear_blocks_root_changesets(socket)
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

  def assign_entry_fields_demanding_live_preview_rerender(socket, schema) do
    lp_opts = Brando.LivePreview.get_target_config(schema)
    assign(socket, :fields_demanding_full_live_preview_rerender, lp_opts.rerender_on_change)
  end

  def assign_entry_fields_demanding_live_preview_reassign(socket, schema) do
    lp_opts = Brando.LivePreview.get_target_config(schema)
    assign(socket, :fields_demanding_live_preview_reassign, lp_opts.reassign_on_change)
  end

  # Loading shell while the async entry load is in flight. Deliberately a
  # separate DOM id without the Brando.Form hook — the hook's mounted()
  # expects the real form markup, and hooks only mount when their element
  # enters the DOM, so the real form must arrive as a fresh element.
  def render(%{entry_loading?: true} = assigns) do
    ~H"""
    <div>
      <div id={"#{@id}-loading"} class="brando-form form-loading">
        <div class="form-content">
          <div :if={@header} class="form-header">
            <h1>
              {render_slot(@header)}
            </h1>
          </div>
        </div>
        <.entry_loader id={"#{@id}-loader-shell"} status={@entry_load_status} entering />
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <.entry_loader :if={!@blocks_ready?} id={"#{@id}-loader"} status={@entry_load_status} />
      <div
        id={"#{@id}-el"}
        class="brando-form"
        phx-hook="Brando.Form"
        data-deliver-topic={@deliver_topic}
        data-entry-id={@entry_id}
      >
        <div class="form-content">
          <div :if={@header} class="form-header">
            <h1>
              {render_slot(@header)}
            </h1>
          </div>

          <div :if={@instructions} class="form-instructions">
            {render_slot(@instructions)}
          </div>

          <div class="form-tabs">
            <div class="form-tab-customs">
              <button
                :for={tab <- @tabs}
                :key={tab}
                type="button"
                class={[@active_tab == tab && "active"]}
                phx-click={JS.push("select_tab", target: @myself)}
                phx-value-name={tab}
              >
                {g(@schema, tab)}
              </button>
            </div>

            <.form_presences presences={@presences} />

            <div class="form-tab-builtins">
              <button :if={@has_meta?} phx-click={toggle_drawer("##{@id}-meta-drawer")} type="button">
                <.icon name="hero-tag" class="s" />
                <span class="tab-text">Meta</span>
              </button>
              <button
                :if={@has_revisioning?}
                phx-click={
                  JS.push("toggle_revisions_drawer_status", target: @myself)
                  |> toggle_drawer("##{@id}-revisions-drawer")
                }
                type="button"
              >
                <.icon name="hero-clock" class="s" />
                <span class="tab-text">{gettext("Revisions")}</span>
              </button>
              <button
                :if={@has_scheduled_publishing?}
                phx-click={toggle_drawer("##{@id}-scheduled-publishing-drawer")}
                type="button"
              >
                <.icon name="hero-calendar-days" class="s" />
                <span class="tab-text">{gettext("Scheduled publishing")}</span>
              </button>
              <button
                :if={@has_alternates?}
                phx-click={toggle_drawer("##{@id}-alternates-drawer")}
                type="button"
              >
                <.icon name="hero-language" class="s" />
              </button>
              <button
                :if={@has_live_preview?}
                phx-click={JS.push("open_live_preview", target: @myself)}
                class={["live-preview-toggle", @live_preview_active? && "active"]}
                type="button"
              >
                <.icon name="hero-eye" class="s" />
              </button>
              <button
                :if={@has_live_preview?}
                phx-click={JS.push("share_link", target: @myself)}
                type="button"
              >
                <.icon name="hero-arrow-top-right-on-square" class="s" />
              </button>
              <div class="split-dropdown">
                <button phx-click={JS.push("push_submit_redirect", target: @myself)} type="button">
                  <.icon name="hero-arrow-down-tray" class="s" />
                </button>
                <SplitDropdown.render id="save-dropdown">
                  <Button.dropdown
                    value={false}
                    event={JS.push("push_submit_redirect", target: @myself)}
                  >
                    {gettext("Save")}<span class="shortcut">⇧⌘S</span>
                  </Button.dropdown>
                  <Button.dropdown value={false} event={JS.push("push_submit", target: @myself)}>
                    {gettext("Save and continue editing")}<span class="shortcut">⌘S</span>
                  </Button.dropdown>
                  <Button.dropdown value={false} event={JS.push("push_submit_new", target: @myself)}>
                    {gettext("Save and create new")}
                  </Button.dropdown>
                </SplitDropdown.render>
              </div>
            </div>
          </div>

          <.live_component module={FilePicker} id="file-picker" />
          <.live_component module={ImagePicker} id="image-picker" />
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
            active_video_tab={@active_video_tab}
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
            phx-change="validate"
          >
            <input type="hidden" name={"#{@form.name}[#{:__force_change}]"} phx-debounce="0" />
            <div style="display:none">
              <.live_file_input upload={@uploads[:image_editor_upload]} />
            </div>
            <MetaDrawer.render
              :if={@has_meta?}
              id={"#{@id}-meta-drawer"}
              form={@form}
              blueprint={@form_blueprint}
              form_cid={@myself}
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
              tabs={@form_blueprint.tabs}
              active_tab={@active_tab}
              current_user={@current_user}
              form={@form}
              form_cid={@myself}
              form_id={@id}
              schema={@schema}
            />
          </.form>

          <.live_component
            :for={{block_field, block_module, entry_blocks, field_opts} <- @block_map}
            :if={@has_blocks? && @blocks_ready?}
            :key={block_field}
            module={BlockField}
            block_module={block_module}
            block_field={block_field}
            form_name={@form.name}
            opts={field_opts}
            id={"#{@id}-blocks-#{block_field}"}
            entry={@entry_for_blocks}
            entry_blocks={entry_blocks}
            current_user={@current_user}
            form_id={@id}
          />

          <Primitives.submit_button
            processing={@processing}
            form_id={@id}
            label={gettext("Save (⌘S)")}
            class="primary submit-button"
          />

          <div :if={@footer} class="form-footer">
            {render_slot(@footer)}
          </div>
        </div>

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

  attr :status, :map, default: nil
  attr :id, :string, required: true
  attr :entering, :boolean, default: false

  # Full-viewport overlay shown while an entry loads and while its block
  # tree renders. The phase steps give the user a sense of scale ("ah, 132
  # blocks — that's why it takes a moment") instead of a frozen screen.
  #
  # Two instances exist across the load: the loading shell's (delayed
  # fade-in via `entering`, so fast loads never flash it) and the main
  # render's continuation (instantly opaque — the shell's overlay is
  # discarded in the same patch — fading out via phx-remove when done).
  def entry_loader(assigns) do
    ~H"""
    <div
      class={["form-loader", @entering && "entering"]}
      id={@id}
      phx-remove={JS.hide(transition: {"form-loader-out", "opacity-100", "opacity-0"}, time: 200)}
    >
      <div class="form-loader-card">
        <div class="form-loader-title">
          {gettext("Opening entry")}
        </div>
        <ol :if={@status} class="form-loader-steps">
          <li class={entry_loader_step(@status.phase, :entry)}>
            {gettext("Fetching content")}
          </li>
          <li :if={@status.blocks?} class={entry_loader_step(@status.phase, :blocks)}>
            <%= if @status.block_count do %>
              {ngettext("Loading %{count} block", "Loading %{count} blocks", @status.block_count)}
            <% else %>
              {gettext("Loading blocks")}
            <% end %>
          </li>
          <li :if={@status.blocks?} class={entry_loader_step(@status.phase, :rendering)}>
            {gettext("Building block editor")}
          </li>
        </ol>
      </div>
    </div>
    """
  end

  @entry_load_phases [:entry, :blocks, :rendering]

  defp entry_loader_step(current_phase, step) do
    current_idx = Enum.find_index(@entry_load_phases, &(&1 == current_phase)) || 0
    step_idx = Enum.find_index(@entry_load_phases, &(&1 == step))

    cond do
      step_idx < current_idx -> "done"
      step_idx == current_idx -> "active"
      true -> "pending"
    end
  end

  attr :presences, :list

  def form_presences(assigns) do
    ~H"""
    <div class="page-presences">
      <div
        :for={{_, user} <- @presences}
        :key={user.id}
        class="user-presence visible"
        data-presence-user-id={user.id}
      >
        <div class="avatar" data-popover={user.name}>
          <Content.image image={user.avatar} size={:thumb} />
        </div>
      </div>
    </div>
    """
  end

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
      |> assign(:relations, Brando.Blueprint.Relations.__relations__(assigns.schema))

    ~H"""
    <%= for {fieldset, idx} <- @indexed_fields do %>
      <%= if fieldset.__struct__ == Brando.Blueprint.Forms.Alert do %>
        <.alert type={fieldset.type}>
          <:icon>
            <.icon name="hero-exclamation-triangle" />
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

  def handle_event("validate", params, socket) do
    # This is also the recovery event for the main form, and it is what
    # rebuilds the entry from the recovered params — see
    # `maybe_finish_live_preview_recovery/1`.
    socket = assign(socket, :form_recovered?, true)
    schema = socket.assigns.schema
    entry = socket.assigns.entry
    current_user = socket.assigns.current_user
    singular = socket.assigns.singular
    dirty_fields = socket.assigns.dirty_fields
    has_blocks? = socket.assigns.has_blocks?

    entry_params = Map.get(params, singular)
    entry_or_default = entry || struct(schema)

    changeset = validate(schema, entry_or_default, entry_params, current_user)
    changed_fields = Map.keys(changeset.changes)

    socket =
      if changed_fields == dirty_fields do
        socket
      else
        Phoenix.PubSub.broadcast(
          Brando.pubsub(),
          "brando:dirty_fields:#{entry.id}",
          {:dirty_fields, changed_fields, current_user.id}
        )

        assign(socket, :dirty_fields, changed_fields)
      end

    # The recomputed form is assigned before the `_target` branch, and that
    # placement is load-bearing. Form *recovery* pushes this same event with a
    # `_target` naming the first non-hidden input in the form — which here is
    # the `image_editor_upload` file input a few lines into the markup, not an
    # entry field (`view.ts:2450`, `channel.ex:848-853`). Assigning inside the
    # `[^singular | rest]` branch meant every recovered value was recomputed and
    # then dropped, so a reconnect silently restored nothing.
    socket = assign(socket, :form, to_form(changeset, []))

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

    file_count =
      case params["file_count"] do
        count when is_integer(count) ->
          count

        count when is_binary(count) ->
          case Integer.parse(count) do
            {parsed, _} -> parsed
            _ -> 0
          end

        _ ->
          0
      end

    send_update(ImagePicker,
      id: "image-picker",
      event: "open_block_upload_browser",
      upload_name: upload_name,
      file_count: file_count,
      config_target: config_target,
      initial_folder: params["initial_folder"],
      recent_folders: recent_folders,
      form_id: socket.assigns.id
    )

    # drawer visibility is pushed by the ImagePicker itself (avoids patch race)
    {:noreply, socket}
  end

  def handle_event("tiptap_link_dialog", params, socket) do
    content_language = socket.assigns.current_user.config.content_language

    send_update(TipTapLinkDialog,
      id: "tiptap-link-dialog",
      event: :open,
      current_href: params["current_href"] || "",
      current_target: params["current_target"],
      current_identifier_id: params["current_identifier_id"],
      mark_type: params["mark_type"] || "link",
      tiptap_id: params["tiptap_id"],
      language: content_language
    )

    {:noreply, socket}
  end

  def handle_event("focus", %{"field" => field}, socket) do
    current_user = socket.assigns.current_user
    entry = socket.assigns.entry
    old_field = socket.assigns[:focused_field]

    if entry && entry.id do
      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        "brando:active_field:#{entry.id}",
        {:active_field, field, current_user.id}
      )

      # Clear block focus/lock when a regular field gets focus
      send(self(), :force_ship_focused_block)
    end

    # Ship all field changeset diffs on blur
    socket =
      if old_field && old_field != field && entry && entry.id do
        ship_all_field_changes(socket)
      else
        socket
      end

    {:noreply, assign(socket, :focused_field, field)}
  end

  def handle_event("focus", _, socket) do
    {:noreply, socket}
  end

  def handle_event("blur", _, socket) do
    entry = socket.assigns[:entry]

    socket =
      if socket.assigns[:focused_field] && entry && entry.id do
        ship_all_field_changes(socket)
      else
        socket
      end

    {:noreply, assign(socket, :focused_field, nil)}
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
      entry_or_default
      |> schema.changeset(entry_params, current_user)
      |> Brando.Utils.set_action()
      |> Brando.Trait.run_trait_before_save_callbacks(schema, current_user)

    singular = schema.__naming__().singular
    translated_singular = Brando.Blueprint.get_singular(schema)
    context = schema.__modules__().context
    mutation_type = (get_field(changeset, :id) && :update) || :create

    # if redirect_on_save is set in form, use this
    redirect_fn =
      form_blueprint.redirect_on_save ||
        fn socket, _entry, _mutation_type ->
          generated_list_view = schema.__modules__().admin_list_view
          Brando.routes().admin_live_path(socket, generated_list_view)
        end

    # redirect to "create new"
    redirect_new_fn = fn _socket, _entry, _mutation_type ->
      schema.__admin_route__(:create, [])
    end

    send(self(), {:progress_popup, "Associating block fields..."})

    new_changeset =
      block_changesets
      |> assoc_all_block_fields(changeset)
      |> then(&assoc_all_transformer_fields(&1, socket.assigns.transformer_changesets))

    entry_for_blocks = build_entry_for_blocks(new_changeset, block_map)

    send(self(), {:progress_popup, "Rendering blocks for entry..."})

    rendered_changeset =
      render_blocks_for_entry(
        block_map,
        new_changeset,
        entry_for_blocks
      )

    send(self(), {:progress_popup, "Saving entry..."})

    case apply(context, :"#{mutation_type}_#{singular}", [rendered_changeset, current_user]) do
      {:ok, entry} ->
        send(self(), {:progress_popup, "Entry saved."})

        Brando.Trait.run_trait_after_save_callbacks(
          schema,
          entry,
          rendered_changeset,
          current_user
        )

        maybe_run_form_after_save(form_blueprint, entry, current_user)

        mutation_message =
          Brando.Gettext
          |> Gettext.dgettext("mutations", "#{mutation_type}", singular: translated_singular)
          |> String.capitalize()

        send(self(), {:toast, mutation_message})

        maybe_redirected_socket =
          case save_redirect_target do
            :self ->
              update_url = schema.__admin_route__(:update, [entry.id])

              if mutation_type == :create do
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
                |> reload_all_blocks()
                |> push_patch(to: update_url)
              else
                if schema.has_trait(Brando.Trait.Revisioned) do
                  id = "#{socket.assigns.id}-revisions-drawer"
                  send_update(RevisionsDrawer, id: id, action: :refresh_revisions)
                end

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
                |> reload_all_blocks()
              end

            :listing ->
              push_navigate(socket, to: Callback.call(redirect_fn, [socket, entry, mutation_type]))

            :new ->
              push_navigate(socket, to: redirect_new_fn.(socket, entry, mutation_type))
          end

        {:noreply, assign(maybe_redirected_socket, :save_redirect_target, :listing)}

      {:error, %Ecto.Changeset{} = changeset} ->
        require Logger
        Logger.error(inspect(changeset, pretty: true))
        send(self(), {:progress_popup, "Saving entry failed..."})

        {:noreply,
         socket
         |> assign(:processing, false)
         |> assign(:form, to_form(changeset, []))
         |> push_errors(changeset, form_blueprint, schema)}
    end
  end

  def handle_event("save", _params, %{assigns: %{has_blocks?: true}} = socket) do
    # has blocks, but not all blocks have been received
    # Force-ship the currently focused block before collecting for save
    send(self(), :force_ship_focused_block)
    fetch_root_blocks(socket, :save, 150)
    fetch_transformer_data(socket, :save)
    send(self(), {:progress_popup, "Saving..."})

    {:noreply,
     socket
     |> ship_all_field_changes()
     |> assign(:processing, true)}
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
      entry_or_default
      |> schema.changeset(entry_params, current_user)
      |> Brando.Utils.set_action()
      |> Brando.Trait.run_trait_before_save_callbacks(schema, current_user)
      |> assoc_all_transformer_fields(socket.assigns.transformer_changesets)

    singular = schema.__naming__().singular
    context = schema.__modules__().context

    mutation_type = (get_field(changeset, :id) && :update) || :create

    # if redirect_on_save is set in form, use this
    redirect_fn =
      form_blueprint.redirect_on_save ||
        fn _socket, _entry, _mutation_type ->
          schema.__admin_route__(:list, [schema.__modules__().admin_list_view])
        end

    # redirect to "create new"
    redirect_new_fn = fn _socket, _entry, _mutation_type ->
      schema.__admin_route__(:create, [])
    end

    case apply(context, :"#{mutation_type}_#{singular}", [changeset, current_user]) do
      {:ok, entry} ->
        Brando.Trait.run_trait_after_save_callbacks(schema, entry, changeset, current_user)
        maybe_run_form_after_save(form_blueprint, entry, current_user)
        send(self(), {:toast, "#{String.capitalize(singular)} #{mutation_type}d"})

        maybe_redirected_socket =
          case save_redirect_target do
            :self ->
              if mutation_type == :create do
                generated_route = schema.__admin_route__(:update, [entry.id])

                push_navigate(socket, to: generated_route)
              else
                if schema.has_trait(Brando.Trait.Revisioned) do
                  id = "#{socket.assigns.id}-revisions-drawer"
                  send_update(RevisionsDrawer, id: id, action: :refresh_revisions)
                end

                # update entry!
                socket
                |> assign(:entry_id, entry.id)
                |> assign_refreshed_entry()
                |> assign_refreshed_form()
              end

            :listing ->
              push_navigate(socket, to: Callback.call(redirect_fn, [socket, entry, mutation_type]))

            :new ->
              push_navigate(socket, to: redirect_new_fn.(socket, entry, mutation_type))
          end

        {:noreply, assign(maybe_redirected_socket, :save_redirect_target, :listing)}

      {:error, %Ecto.Changeset{} = changeset} ->
        require Logger
        Logger.error(inspect(changeset, pretty: true))

        {:noreply,
         socket
         |> assign(:form, to_form(changeset, []))
         |> push_errors(changeset, form_blueprint, schema)}
    end
  end

  def handle_event(
        "duplicate_image",
        %{"image_id" => image_id},
        %{assigns: %{singular: singular, current_user: current_user}} = socket
      ) do
    {:ok, image} = Brando.Images.duplicate_image(image_id, current_user)

    send_update(__MODULE__,
      id: "#{singular}_form",
      action: :update_edit_image,
      image: image
    )

    send(self(), {:toast, gettext("Image duplicated")})

    {:noreply, socket}
  end

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
        # Crop was already applied via the HTTP replace_crop endpoint.
        # The controller's Crop.save_replace already queued processing.
        image_id = params["image_id"] || edit_image.image.id
        {:ok, img} = Brando.Images.get_image(image_id)
        img
      else
        # No crop — just update focal point and reprocess from the original file.
        image =
          case edit_image do
            %{image: image} when not is_nil(image) ->
              image

            _ ->
              {:ok, img} = Brando.Images.get_image(params["image_id"])
              img
          end

        x = params["focal_x"]
        y = params["focal_y"]

        changeset =
          image
          |> Brando.Images.Image.changeset(
            %{focal: %{x: x, y: y}, status: :unprocessed},
            current_user
          )
          |> Map.put(:action, :update)

        {:ok, img} = Brando.Repo.update(changeset)
        img
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
      Brando.Images.Processing.queue_processing(updated_image, current_user)
    end

    # For crop_applied, processing was already queued by the controller.
    # With Oban inline testing, the broadcast was sent before we subscribed.
    # Re-fetch to get the latest state (may already be processed).
    updated_image =
      if params["crop_applied"] do
        {:ok, fresh} = Brando.Images.get_image(updated_image.id)
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
      # Non-block path: update entry with the image so the Image input
      # detects the change when the form re-validates (same pattern as new_copy).
      schema = socket.assigns.schema
      field_atom = String.to_existing_atom("#{edit_image.field}")
      entry = socket.assigns.entry || struct(schema)
      field_path = edit_image.path ++ [field_atom]
      access_path = Brando.Utils.build_access_path(field_path)
      updated_entry = put_in(entry, access_path, updated_image)

      image_changeset = change(updated_image)
      updated_edit_image = Map.merge(edit_image, %{image: updated_image})

      {:noreply,
       socket
       |> assign(:entry, updated_entry)
       |> assign(:edit_image, updated_edit_image)
       |> assign(:image_changeset, image_changeset)
       |> push_event("b:validate", %{})}
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

  def handle_event("reset_video_field", _, socket) do
    edit_video = socket.assigns.edit_video

    {:noreply,
     socket
     |> assign(:video_changeset, nil)
     |> assign(:editing_video?, false)
     |> assign(:edit_video, %{edit_video | video: nil})
     |> assign_drawer_recovery_state()}
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

          {:error, %Ecto.Changeset{} = failed_changeset} ->
            require Logger
            Logger.error("==> reset_video_thumbnail failed: #{inspect(failed_changeset.errors)}")
            send(self(), {:toast, gettext("Could not reset video thumbnail")})
            {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("parse_video_url", _, socket) do
    # Placeholder for URL parsing functionality
    send(self(), {:toast, gettext("URL parsing not yet implemented")})
    {:noreply, socket}
  end

  def handle_event("extract_thumbnail", _, socket) do
    # Placeholder for thumbnail extraction functionality
    send(self(), {:toast, gettext("Thumbnail extraction not yet implemented")})
    {:noreply, socket}
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
    updated_changeset = EctoNestedChangeset.update_at(changeset, full_path, fn _ -> nil end)
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
     |> assign(:form, to_form(updated_changeset, []))
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
    updated_changeset = EctoNestedChangeset.update_at(changeset, full_path, fn _ -> nil end)
    updated_edit_image = Map.put(edit_image, :image, nil)

    {:noreply,
     socket
     |> assign(:entry, Map.put(entry, edit_image.field, nil))
     |> assign(:image_changeset, nil)
     # Same as reset_file_field above — this closes the image drawer, so the
     # guard flag must come down or the entry can never be saved again.
     |> assign(:editing_image?, false)
     |> assign(:edit_image, updated_edit_image)
     |> assign(:form, to_form(updated_changeset, []))
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

  def handle_event(
        "ai_generate_input",
        %{"field_name" => field_name, "field_key" => field_key},
        socket
      ) do
    with {:ok, field_atom} <- safe_to_existing_atom(field_key),
         {:ok, ai_opts} <-
           fetch_field_ai_opts(socket.assigns.form_blueprint, field_atom, socket.assigns.schema),
         {:ok, prompt} <- build_ai_prompt(socket, ai_opts),
         {:ok, path, key, string_path} <-
           parse_form_field_name(field_name, socket.assigns.singular),
         {:ok, %{text: generated_text}} <- Brando.AI.generate_text(prompt, ai_opts) do
      updated_socket =
        socket
        |> update_changeset(path, key, generated_text)
        |> maybe_send_ai_update_to_blocks(string_path, generated_text)
        |> maybe_invalidate_live_preview_assign(string_path, :string_path)
        |> maybe_fetch_root_blocks(:live_preview_update, 0)
        |> maybe_force_ai_component_remount(socket.assigns.form_blueprint, field_atom)

      {:noreply, updated_socket}
    else
      {:error, reason} ->
        send(self(), {:toast, ai_error_message(reason)})
        {:noreply, socket}
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

    Brando.Trait.run_trait_after_save_callbacks(
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
     |> assign(:form, to_form(updated_changeset, []))
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
    image_changeset =
      socket.assigns.edit_image.image
      |> change(%{
        title: image_params["title"],
        credits: image_params["credits"],
        alt: image_params["alt"]
      })
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :image_changeset, image_changeset)}
  end

  def handle_event("validate_image", _, socket) do
    {:noreply, socket}
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
      %Brando.Images.Image{}
      |> Brando.Images.Image.changeset(new_image_params, current_user)
      |> Map.put(:action, :insert)
      |> Brando.Trait.run_trait_before_save_callbacks(
        Brando.Images.Image,
        current_user
      )

    {:ok, new_image} = Brando.Repo.insert(validated_changeset)

    Brando.Trait.run_trait_after_save_callbacks(
      Brando.Images.Image,
      new_image,
      validated_changeset,
      current_user
    )

    if new_image.status !== :processed do
      Brando.Images.Processing.queue_processing(new_image, current_user)
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
      |> Brando.Images.Image.changeset(image_params, current_user)
      |> Map.put(:action, :update)
      |> Brando.Trait.run_trait_before_save_callbacks(
        Brando.Images.Image,
        current_user
      )

    {:ok, _} = Brando.Images.update_image(validated_changeset, current_user)

    # Reload from DB — the Oban processing job may have updated
    # status/sizes since the drawer was opened.
    {:ok, updated_image} = Brando.Images.get_image(image.id)

    Brando.Trait.run_trait_after_save_callbacks(
      Brando.Images.Image,
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
      Brando.Images.Processing.queue_processing(updated_image, current_user, field_full_path)
    end

    target_field_name =
      Enum.join([singular | Enum.map(relation_full_path, &"[#{to_string(&1)}]")])

    {:noreply,
     socket
     # ship BEFORE the re-bake below — apply_changes/change() bakes pending
     # changes into data, leaving nothing for ship_all_field_changes to see
     |> ship_all_field_changes()
     |> assign(:entry, updated_entry)
     |> assign(:form, to_form(updated_changeset, []))
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

    Brando.Trait.run_trait_after_save_callbacks(
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
     |> assign(:form, to_form(updated_changeset, []))
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
    fetch_root_blocks(socket, :share, 500)
    {:noreply, socket}
  end

  def handle_event("store_revision", _, socket) do
    send(self(), :force_ship_focused_block)
    send(self(), {:toast, gettext("Saving a revision...")})

    socket =
      socket
      |> clear_blocks_root_changesets()
      |> reset_transformer_changesets()

    fetch_transformer_data(socket, :store_revision)

    {:noreply, fetch_root_blocks(socket, :store_revision, 150)}
  end

  # restore live preview after reconnect via form recovery
  def handle_event(
        "recover_live_preview_state",
        %{"live_preview" => %{"cache_key" => cache_key}},
        socket
      )
      when cache_key != "" do
    schema = socket.assigns.schema

    socket =
      socket
      |> assign(:live_preview_active?, true)
      |> assign(:live_preview_cache_key, cache_key)
      |> assign_entry_fields_demanding_live_preview_rerender(schema)
      |> assign_entry_fields_demanding_live_preview_reassign(schema)
      |> push_event("b:live_preview", %{cache_key: cache_key})
      |> push_event("js-exec", %{to: "#sidebar", attr: "data-js-hide"})

    socket =
      if socket.assigns.has_blocks? do
        enable_live_preview_in_blocks(socket)
      else
        socket
      end

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
    Brando.LivePreview.cleanup_cache(socket.assigns.live_preview_cache_key)

    socket
    |> assign(:live_preview_active?, false)
    |> assign(:live_preview_cache_key, nil)
    |> disable_live_preview_in_blocks()
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
    fetch_root_blocks(socket, :live_preview, 500)
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
    fetch_root_blocks(socket, :live_preview_standalone, 500)
    {:noreply, socket}
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

  # TODO: This is not a very good solution. We should just add a class with JS.add_class to the tab,
  # we probably don't need state for this.
  def handle_event("select_tab", %{"tab" => video_tab}, socket) do
    {:noreply, assign(socket, :active_video_tab, video_tab)}
  end

  def handle_event("save_redirect_target", _, socket) do
    {:noreply, assign(socket, :save_redirect_target, :self)}
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
      {key, _} -> Brando.LivePreview.invalidate_var(cache_key, key)
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
    socket
  end

  defp maybe_fetch_root_blocks(%{assigns: %{live_preview_active?: false}} = socket, _, _) do
    socket
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

  # Reset the per-field accumulator between provide_root_blocks rounds.
  # (BlockFields materialize their answer from the op store, so there is no
  # per-component gather state left to clear.)
  defp clear_blocks_root_changesets(socket) do
    blocks = socket.assigns.form_blueprint.blocks
    assign(socket, :block_changesets, Map.new(blocks, &{&1.name, nil}))
  end

  defp reload_all_blocks(socket) do
    block_map = socket.assigns.block_map
    id = socket.assigns.id

    for {block_field_name, _schema, _entry_blocks, _opts} <- block_map do
      block_field_id = "#{id}-blocks-#{block_field_name}"
      send_update(BlockField, id: block_field_id, event: "reload_all_blocks")
    end

    socket
  end

  defp enable_live_preview_in_blocks(socket) do
    block_map = socket.assigns.block_map
    id = socket.assigns.id
    cache_key = socket.assigns.live_preview_cache_key

    Enum.each(block_map, fn {block_field_name, _schema, _entry_blocks, _opts} ->
      block_field_id = "#{id}-blocks-#{block_field_name}"

      send_update(BlockField,
        id: block_field_id,
        event: "enable_live_preview",
        cache_key: cache_key
      )
    end)

    socket
  end

  defp disable_live_preview_in_blocks(socket) do
    block_map = socket.assigns.block_map
    id = socket.assigns.id

    Enum.each(block_map, fn {block_field_name, _schema, _entry_blocks, _opts} ->
      block_field_id = "#{id}-blocks-#{block_field_name}"

      send_update(BlockField,
        id: block_field_id,
        event: "disable_live_preview"
      )
    end)

    socket
  end

  defp maybe_run_form_after_save(%{after_save: nil}, _, _), do: nil

  defp maybe_run_form_after_save(%{after_save: after_save}, entry, current_user) do
    Callback.call(after_save, [entry, current_user])
  end

  defp validate(schema, entry, params, user) do
    entry
    |> schema.changeset(params, user)
    |> Map.put(:action, :validate)
  end

  defp assoc_all_block_fields(block_changesets, changeset) do
    Enum.reduce(block_changesets, changeset, fn {field_name, block_cs}, updated_changeset ->
      updated_block_cs =
        block_cs
        |> Brando.Content.Blocks.reject_deleted(true)
        |> Brando.Content.Blocks.strip_render_artifacts()
        |> Brando.Utils.set_action()

      Ecto.Changeset.put_assoc(updated_changeset, :"entry_#{field_name}", updated_block_cs)
    end)
  end

  defp assoc_all_transformer_fields(changeset, transformer_changesets) do
    Enum.reduce(transformer_changesets, changeset, fn
      {_field_name, nil}, acc -> acc
      {field_name, data}, acc -> Ecto.Changeset.put_assoc(acc, field_name, data)
    end)
  end

  defp store_revision(socket, changeset) do
    case Ecto.Changeset.apply_action(changeset, :update) do
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

      {:error, invalid_changeset} ->
        socket
        |> assign(:form, to_form(invalid_changeset, []))
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
  defp loaded_image?(%Brando.Images.Image{}), do: true

  defp push_errors(socket, changeset, form, schema, env \\ :save) do
    error_title = gettext("Error")

    error_notice =
      if env == :save do
        gettext("Error while saving form. Please correct marked fields and resubmit<br><br>Fields marked invalid:")
      else
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
        path = prefix ++ [field]

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

      {field, nested} when is_map(nested) ->
        flatten_nested_errors(nested, prefix ++ [field])

      _ ->
        []
    end)
  end

  @doc """
  Handle upload progress for the image editor's "save as new copy" feature.

  Applies stored focal point and config_target to the new image, then queues
  processing and forwards the result to the block component (if from a block).
  """
  def handle_image_editor_upload_progress(:image_editor_upload, entry, socket) do
    if entry.done? do
      current_user = socket.assigns.current_user
      edit_image = socket.assigns.edit_image
      config_target = Map.get(socket.assigns, :image_editor_config_target, "default")
      focal = Map.get(socket.assigns, :image_editor_focal, %{x: 50, y: 50})

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
          # Apply focal and mark for reprocessing
          changeset =
            new_image
            |> Brando.Images.Image.changeset(
              %{focal: %{x: focal.x, y: focal.y}, status: :unprocessed},
              current_user
            )
            |> Map.put(:action, :update)

          case Brando.Repo.update(changeset) do
            {:ok, updated_image} ->
              Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:image:#{updated_image.id}")

              if block_target = Map.get(edit_image, :block_target) do
                send(self(), {:register_pending_block_image, updated_image.id, block_target})
              end

              Brando.Images.Processing.queue_processing(updated_image, current_user)

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

            {:error, reason} ->
              {:noreply,
               push_event(socket, "b:alert", %{
                 title: gettext("Error creating image"),
                 type: "error",
                 message: inspect(reason)
               })}
          end
      end
    else
      {:noreply, socket}
    end
  end

  defp resolve_block_image_config(config_target) do
    resolved_target = normalize_upload_config_target(config_target) || "default"

    case Brando.Images.get_config_for(resolved_target) do
      {:ok, cfg} ->
        {cfg, resolved_target}

      _ ->
        default_config =
          Brando.config(Brando.Images)[:default_config] ||
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
    case Brando.Upload.handle_upload(meta, upload_entry, cfg, current_user) do
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

  defp upload_error_noreply(socket, _kind, %Ecto.Changeset{} = changeset) do
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
    assign_new(socket, :form, fn ->
      # this is the initial assignment of changeset with an empty entry,
      # so we add default_params here
      default_entry
      |> schema.changeset(default_params, current_user)
      |> to_form()
    end)
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
    assign_new(socket, :form, fn ->
      entry
      |> schema.changeset(%{}, current_user)
      |> to_form()
    end)
  end

  def assign_refreshed_form(%{assigns: %{entry: entry, schema: schema, current_user: current_user}} = socket) do
    assign(socket, :form, to_form(schema.changeset(entry, %{}, current_user), []))
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

  defp fetch_field_ai_opts(form_blueprint, field_atom, schema) do
    case BlueprintForms.get_field(field_atom, form_blueprint) do
      nil ->
        fetch_fallback_ai_opts(schema, field_atom, :missing_field)

      %{opts: opts} ->
        opts = opts || []

        if Keyword.has_key?(opts, :ai) do
          ai_opts = Brando.AI.normalize_ai_opts(Keyword.get(opts, :ai))

          if ai_opts == [] do
            {:error, :missing_ai_config}
          else
            {:ok, ai_opts}
          end
        else
          fetch_fallback_ai_opts(schema, field_atom, :missing_ai_config)
        end
    end
  end

  defp fetch_fallback_ai_opts(schema, field_atom, error_reason) do
    case Brando.AI.field_ai_opts(schema, field_atom) do
      [] -> {:error, error_reason}
      ai_opts -> {:ok, ai_opts}
    end
  end

  defp build_ai_prompt(socket, ai_opts) do
    case Keyword.get(ai_opts, :prompt) do
      prompt when is_binary(prompt) ->
        prompt = String.trim(prompt)

        if prompt == "" do
          {:error, :missing_prompt}
        else
          context_fields =
            ai_opts
            |> Keyword.get(:context, [])
            |> normalize_ai_context_fields()

          context_values = build_ai_context_values(socket, context_fields)

          context_lines =
            context_values
            |> Enum.map(fn {field, value} -> "#{field}: #{value}" end)
            |> Enum.reject(&(&1 == ""))

          full_prompt =
            if context_lines == [] do
              prompt
            else
              [prompt, "\n\nContext:\n", Enum.join(context_lines, "\n")]
              |> IO.iodata_to_binary()
            end

          {:ok, full_prompt}
        end

      _ ->
        {:error, :missing_prompt}
    end
  end

  defp normalize_ai_context_fields(context) when is_list(context) do
    context
    |> Enum.map(&normalize_ai_context_field/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_ai_context_fields(context) do
    context
    |> List.wrap()
    |> normalize_ai_context_fields()
  end

  defp normalize_ai_context_field(field) when is_atom(field), do: field

  defp normalize_ai_context_field(field) when is_binary(field) do
    String.to_existing_atom(field)
  rescue
    ArgumentError -> nil
  end

  defp normalize_ai_context_field(_), do: nil

  defp build_ai_context_values(socket, context_fields) do
    entry = apply_changes(socket.assigns.form.source)

    Enum.reduce(context_fields, [], fn
      :blocks, acc ->
        case render_ai_blocks_context(socket) do
          nil -> acc
          "" -> acc
          value -> acc ++ [{:blocks, value}]
        end

      field, acc ->
        value = Map.get(entry, field) |> format_ai_context_value()

        if value in [nil, ""] do
          acc
        else
          acc ++ [{field, value}]
        end
    end)
  end

  defp render_ai_blocks_context(%{assigns: %{has_blocks?: false}}), do: nil

  defp render_ai_blocks_context(%{assigns: %{form: form, block_map: block_map}}) do
    changeset = form.source
    entry_for_blocks = build_entry_for_blocks(changeset, block_map)
    rendered_changeset = render_blocks_for_entry(block_map, changeset, entry_for_blocks)

    block_map
    |> Enum.map(fn {block_field_name, _schema, _entry_blocks, _opts} ->
      rendered_field_name = :"rendered_#{block_field_name}"

      Ecto.Changeset.get_change(rendered_changeset, rendered_field_name) ||
        Ecto.Changeset.get_field(rendered_changeset, rendered_field_name)
    end)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map_join("\n\n", &HtmlSanitizeEx.strip_tags/1)
    |> String.trim()
  end

  defp format_ai_context_value(nil), do: nil

  defp format_ai_context_value(value) when is_binary(value),
    do: value |> HtmlSanitizeEx.strip_tags() |> String.trim()

  defp format_ai_context_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_ai_context_value(value) when is_float(value), do: to_string(value)
  defp format_ai_context_value(value) when is_boolean(value), do: to_string(value)

  defp format_ai_context_value(value) when is_list(value) do
    value
    |> Enum.map(&format_ai_context_value/1)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
  end

  defp format_ai_context_value(value) when is_map(value) do
    value
    |> inspect(pretty: false, limit: :infinity)
  end

  defp format_ai_context_value(value), do: to_string(value)

  defp parse_form_field_name(field_name, singular) do
    segments = Regex.scan(~r/[^\[\]]+/, field_name) |> List.flatten()

    with [root | field_segments] <- segments,
         true <- root == singular,
         false <- field_segments == [],
         {:ok, typed_segments} <- cast_form_path_segments(field_segments),
         key when is_atom(key) <- List.last(typed_segments) do
      path = Enum.drop(typed_segments, -1)
      {:ok, path, key, field_segments}
    else
      _ -> {:error, :invalid_field_name}
    end
  end

  defp cast_form_path_segments(segments) do
    Enum.reduce_while(segments, {:ok, []}, fn segment, {:ok, acc} ->
      case cast_form_path_segment(segment) do
        {:ok, casted} ->
          {:cont, {:ok, acc ++ [casted]}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
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

  defp maybe_force_ai_component_remount(socket, form_blueprint, field_atom) do
    case BlueprintForms.get_field(field_atom, form_blueprint) do
      %{type: :rich_text} -> force_svelte_remounts(socket)
      _ -> socket
    end
  end

  defp ai_error_message(:missing_field),
    do: gettext("Could not resolve AI settings for this field")

  defp ai_error_message(:missing_ai_config),
    do: gettext("No AI configuration was found for this field")

  defp ai_error_message(:missing_prompt), do: gettext("Missing AI prompt configuration")
  defp ai_error_message(:missing_model), do: gettext("Missing AI model configuration")
  defp ai_error_message(:missing_api_key), do: gettext("Missing API key for selected AI provider")
  defp ai_error_message(:empty_response), do: gettext("AI returned an empty response")

  defp ai_error_message(:invalid_field_name),
    do: gettext("Could not update this field from AI response")

  defp ai_error_message(_), do: gettext("Failed to generate text with AI")

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

    assign(socket, :form, to_form(new_changeset, []))
  end

  def update_changeset(socket, path, key, map) when is_list(path) and is_map(map) do
    changeset = socket.assigns.form.source

    new_changeset =
      EctoNestedChangeset.update_at(changeset, path ++ [key], fn _ -> Map.from_struct(map) end)

    assign(socket, :form, to_form(new_changeset, []))
  end

  def update_changeset(socket, path, key, value) when is_list(path) do
    changeset =
      socket.assigns.form.source
      |> apply_changes()
      |> change()

    new_changeset = EctoNestedChangeset.update_at(changeset, path ++ [key], fn _ -> value end)

    assign(socket, :form, to_form(new_changeset, []))
  end

  def update_changeset(socket, key, list) when is_list(list) do
    changeset = socket.assigns.form.source
    new_changeset = put_change(changeset, key, Enum.map(list, &Map.from_struct/1))

    assign(socket, :form, to_form(new_changeset, []))
  end

  def update_changeset(socket, key, value) when is_map(value) do
    changeset = socket.assigns.form.source
    new_changeset = put_change(changeset, key, Map.from_struct(value))

    assign(socket, :form, to_form(new_changeset, []))
  end

  def update_changeset(socket, key, value) do
    changeset = socket.assigns.form.source
    new_changeset = put_change(changeset, key, value)

    assign(socket, :form, to_form(new_changeset, []))
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
              <.icon name="hero-arrow-path" />
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
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
                  <path fill="none" d="M0 0h24v24H0z" /><path d="M4 5v11h16V5H4zm-2-.993C2 3.451 2.455 3 2.992 3h18.016c.548 0 .992.449.992 1.007V18H2V4.007zM1 19h22v2H1v-2z" />
                </svg>
                <span>1440px</span>
              </button>
              <button type="button" data-live-preview-target="tablet">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
                  <path fill="none" d="M0 0h24v24H0z" /><path d="M6 4v16h12V4H6zM5 2h14a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1zm7 15a1 1 0 1 1 0 2 1 1 0 0 1 0-2z" />
                </svg>
                <span>768px</span>
              </button>
              <button type="button" data-live-preview-target="mobile">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
                  <path fill="none" d="M0 0h24v24H0z" /><path d="M7 4v16h10V4H7zM6 2h12a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1zm6 15a1 1 0 1 1 0 2 1 1 0 0 1 0-2z" />
                </svg>
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
  defp requeue_processing?(%Ecto.Changeset{changes: changes}, image) do
    if Enum.any?(@processing_inputs, &Map.has_key?(changes, &1)) do
      true
    else
      # Nothing processing-relevant changed. Still queue an unprocessed image —
      # the upload that created it may never have processed, and the drawer is
      # the only place the editor can recover that from — but not if a pass is
      # already in flight, which is the case the old gate kept restarting.
      image.status != :processed and not Brando.Images.Processing.processing_queued?(image)
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
          {:ok, %{upload_url: url, video: video} = result} ->
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

    case Brando.Images.get_image(resource_id) do
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
      changes when map_size(changes) == 0 -> Ecto.Changeset.change(resource)
      changes -> Ecto.Changeset.cast(resource, changes, allowed_fields)
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
    %{
      editing_image?: editing_image?,
      editing_video?: editing_video?,
      editing_file?: editing_file?,
      edit_image: edit_image,
      edit_video: edit_video,
      edit_file: edit_file
    } = socket.assigns

    {type, resource_id, field, path, schema, changeset} =
      cond do
        editing_image? and edit_image[:id] ->
          {"image", edit_image.id, edit_image[:field], edit_image[:path], edit_image[:schema],
           socket.assigns[:image_changeset]}

        editing_video? and edit_video[:id] ->
          {"video", edit_video.id, edit_video[:field], edit_video[:path], edit_video[:schema],
           socket.assigns[:video_changeset]}

        editing_file? and edit_file[:id] ->
          {"file", edit_file.id, edit_file[:field], edit_file[:path], edit_file[:schema], socket.assigns[:file_changeset]}

        true ->
          {nil, nil, nil, [], nil, nil}
      end

    socket
    |> assign(:editing_drawer_type, type)
    |> assign(:editing_resource_id, resource_id)
    |> assign(:editing_field, field && to_string(field))
    |> assign(:editing_path, path || [])
    |> assign(:editing_schema, schema && to_string(schema))
    |> assign(:editing_drawer_changes, encode_drawer_changes(type, changeset))
  end

  # Only what the user actually changed, and only the text fields — everything
  # else in a drawer changeset either is not JSON-encodable or is not something
  # the drawer can edit. An empty map is the common case and encodes to "{}".
  defp encode_drawer_changes(type, %Ecto.Changeset{changes: changes}) do
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
      case Brando.Images.get_config_for(image) do
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
      {w, h} = Brando.Images.Operations.Sizing.get_crop_dimensions_from_cfg(cfg)
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
    case Brando.Images.get_config_for(image) do
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
end
