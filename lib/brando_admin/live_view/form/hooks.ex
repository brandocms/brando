defmodule BrandoAdmin.LiveView.Form.Hooks do
  @moduledoc """
  Runtime hooks for the public `BrandoAdmin.LiveView.Form` entry point.
  """
  import Phoenix.LiveView
  import Phoenix.Component
  use Gettext, backend: Brando.Gettext

  alias Brando.Tenant.Topic
  alias Phoenix.PubSub

  def on_mount({:setup, schema}, %{"entry_id" => entry_id}, _session, socket) do
    if connected?(socket) do
      socket =
        socket
        |> assign(:socket_connected, true)
        |> set_admin_locale()
        |> assign_action(:update)
        |> assign_schema(schema)
        |> assign_entry_id(entry_id)
        |> assign_title()
        |> assign(:mutation_listeners, %{})

      subscribe_entry_topics(socket.assigns.schema, entry_id)

      {:cont, assign(socket, :current_focused_block_uid, nil)}
    else
      # The dead render gets a title too, so the tab isn't "Admin" first, and
      # the form as a skeleton for the layout to show until LiveView connects
      # and the entry has loaded (a reload, a link from elsewhere).
      socket = if socket.assigns[:current_user], do: set_admin_locale(socket), else: socket

      {:cont,
       socket
       |> assign(:socket_connected, false)
       |> assign(:page_title, Brando.Blueprint.get_singular(schema))
       |> assign(:entry_skeleton, BrandoAdmin.Components.Form.EntrySkeleton.describe(schema))}
    end
  end

  def on_mount({:setup, schema}, _params, _session, socket) do
    if connected?(socket) do
      socket =
        socket
        |> assign(:socket_connected, true)
        |> set_admin_locale()
        |> assign_action(:create)
        |> assign_schema(schema)
        |> assign_entry_id(nil)
        |> assign_title()
        |> assign(:mutation_listeners, %{})
        |> assign(:current_focused_block_uid, nil)
        # create + save-and-continue push_patches to the update route without
        # remounting — arm entry-scoped collaboration (entry_id + presence/
        # sync topics) when the patched params first carry an entry_id, or
        # block sync/presence stay silently disarmed until a full reload
        |> attach_hook(:b_form_arm_entry, :handle_params, &maybe_arm_entry_scope/3)

      {:cont, socket}
    else
      {:cont,
       socket
       |> assign(:socket_connected, false)
       |> assign(
         :page_title,
         gettext("New %{singular}", singular: String.downcase(Brando.Blueprint.get_singular(schema)))
       )}
    end
  end

  def on_mount({:hooks_images, _schema}, _params, _session, socket) do
    {:cont,
     socket
     |> assign(:pending_block_image_updates, %{})
     |> attach_hook(:b_form_images, :handle_info, &handle_hooks_image_info/2)}
  end

  # Every editor's fields, refs and vars follow the assets they show in
  # processing, whoever uploaded them.
  def on_mount({:hooks_processing_watch, _schema}, _params, _session, socket) do
    {:cont, BrandoAdmin.LiveView.Form.ProcessingWatch.attach(socket)}
  end

  def on_mount({:hooks_asset_delivery, _schema}, _params, _session, socket) do
    {:cont, attach_hook(socket, :b_form_asset_delivery, :handle_info, &handle_asset_delivery_info/2)}
  end

  def on_mount({:hooks_videos, _schema}, _params, _session, socket) do
    {:cont, attach_hook(socket, :b_form_videos, :handle_info, &handle_hooks_video_info/2)}
  end

  def on_mount({:hooks_video_events, _schema}, _params, _session, socket) do
    {:cont, attach_hook(socket, :b_form_video_events, :handle_event, &handle_hooks_video_event/3)}
  end

  def on_mount({:hooks_port_exits, _schema}, _params, _session, socket) do
    {:cont, attach_hook(socket, :b_form_port_exits, :handle_info, &handle_hooks_port_exits/2)}
  end

  def on_mount({:hooks_toast, _schema}, _params, _session, socket) do
    {:cont, attach_hook(socket, :b_form_toast, :handle_info, &handle_hooks_toast_info/2)}
  end

  def on_mount({:hooks_progress_popup, _schema}, _params, _session, socket) do
    {:cont,
     attach_hook(
       socket,
       :b_form_progress_popup,
       :handle_info,
       &handle_hooks_progress_popup_info/2
     )}
  end

  def on_mount({:hooks_alert, _schema}, _params, _session, socket) do
    {:cont, attach_hook(socket, :b_form_alert, :handle_info, &handle_hooks_alert_info/2)}
  end

  def on_mount({:hooks_content_language, _schema}, _params, _session, socket) do
    {:cont,
     attach_hook(
       socket,
       :b_form_content_language,
       :handle_info,
       &handle_hooks_content_language_info/2
     )}
  end

  def on_mount({:hooks_dirty_fields, _schema}, _params, _session, socket) do
    {:cont,
     attach_hook(
       socket,
       :b_form_dirty_fields,
       :handle_info,
       &handle_hooks_dirty_fields_info/2
     )}
  end

  def on_mount({:hooks_active_field, _schema}, _params, _session, socket) do
    {:cont,
     attach_hook(
       socket,
       :b_form_active_field,
       :handle_info,
       &handle_hooks_active_field_info/2
     )}
  end

  def on_mount({:hooks_block_presence, _schema}, _params, _session, socket) do
    {:cont,
     socket
     |> attach_hook(
       :b_form_block_presence,
       :handle_info,
       &handle_hooks_block_presence_info/2
     )
     |> attach_hook(
       :b_form_block_focused,
       :handle_event,
       &handle_hooks_block_focused_event/3
     )}
  end

  def on_mount({:hooks_block_sync, _schema}, _params, _session, socket) do
    {:cont,
     attach_hook(
       socket,
       :b_form_block_sync,
       :handle_info,
       &handle_hooks_block_sync_info/2
     )}
  end

  def on_mount({:hooks_modules, _schema}, _params, _session, socket) do
    {:cont,
     attach_hook(
       socket,
       :b_form_modules,
       :handle_info,
       &handle_hooks_modules_info/2
     )}
  end

  def on_mount({:hooks_mutation_listener, _schema}, _params, _session, socket) do
    {:cont,
     attach_hook(
       socket,
       :b_form_mutation_listener,
       :handle_info,
       &handle_hooks_mutation_listener_info/2
     )}
  end

  def on_mount({:hooks_mutations, _schema}, _params, _session, socket) do
    {:cont,
     attach_hook(
       socket,
       :b_form_mutations,
       :handle_info,
       &handle_hooks_mutations_info/2
     )}
  end

  def on_mount({:hooks_focal_point, _schema}, _params, _session, socket) do
    {:cont,
     attach_hook(
       socket,
       :b_form_focal_point,
       :handle_event,
       &handle_hooks_focal_point_event/3
     )}
  end

  def on_mount({:hooks_focus, _schema}, _params, _session, socket) do
    {:cont,
     attach_hook(
       socket,
       :b_form_focus,
       :handle_event,
       &handle_hooks_focus_event/3
     )}
  end

  def on_mount({:hooks_notes, _schema}, _params, _session, socket) do
    {:cont, attach_hook(socket, :b_form_notes, :handle_info, &handle_hooks_notes_info/2)}
  end

  def on_mount({:hooks_tiptap_link, _schema}, _params, _session, socket) do
    {:cont, attach_hook(socket, :b_form_tiptap_link, :handle_info, &handle_hooks_tiptap_link_info/2)}
  end

  defp maybe_arm_entry_scope(%{"entry_id" => entry_id}, _uri, %{assigns: %{entry_id: nil}} = socket) do
    subscribe_entry_topics(socket.assigns.schema, entry_id)

    {:cont,
     socket
     |> assign_action(:update)
     |> assign_entry_id(entry_id)
     |> assign_title()}
  end

  defp maybe_arm_entry_scope(_params, _uri, socket), do: {:cont, socket}

  defp subscribe_entry_topics(schema, entry_id) do
    Enum.each(
      ~w(dirty_fields active_field block_presence field_sync notes),
      &PubSub.subscribe(Brando.pubsub(), Topic.entry(&1, schema, entry_id))
    )
  end

  defp handle_hooks_focal_point_event(
         "update_focal_point",
         %{"field" => field, "x" => x, "y" => y},
         %{assigns: %{changeset: changeset}} = socket
       ) do
    field_atom = String.to_existing_atom(field)
    updated_focal = %{x: x, y: y}

    updated_field =
      changeset
      |> Ecto.Changeset.get_field(field_atom)
      |> Map.from_struct()
      |> Map.put(:focal, updated_focal)

    updated_changeset = Ecto.Changeset.put_change(changeset, field_atom, updated_field)
    {:halt, assign(socket, changeset: updated_changeset)}
  end

  defp handle_hooks_focal_point_event(_, _, socket), do: {:cont, socket}

  # Catch-all for focus events from portal forms (multi-select create modals, etc)
  defp handle_hooks_focus_event("focus", _, socket), do: {:halt, socket}
  defp handle_hooks_focus_event(_, _, socket), do: {:cont, socket}

  defp handle_hooks_image_info({image, [:image, :processing], path}, socket) do
    case String.split(image.config_target, ":") do
      ["image", image_schema_binary, field_name] ->
        field_atom = String.to_existing_atom(field_name)
        schema = socket.assigns.schema
        image_schema = Module.concat([image_schema_binary])

        full_path =
          if image_schema == schema do
            [field_atom]
          else
            path
          end

        singular = schema.__naming__().singular
        target_id = "#{singular}_form"

        image = Map.put(image, :status, :unprocessed)

        route_image_update(socket, singular, target_id, full_path, image, :cont)

      ["gallery", _schema, field_name] ->
        update_gallery_image(socket, field_name, image)

      _ ->
        pending = Map.get(socket.assigns, :pending_block_image_updates, %{})

        if Map.has_key?(pending, image.id) do
          {:halt, socket}
        else
          {:cont, socket}
        end
    end
  end

  defp handle_hooks_image_info({image, [:image, :updated], path}, socket) do
    maybe_unsubscribe_from_image(image)
    send_update(BrandoAdmin.Components.ImagePicker, id: "image-picker", refresh_images: true)

    case String.split(image.config_target, ":") do
      ["image", image_schema_binary, field_name] ->
        field_atom = String.to_existing_atom(field_name)
        schema = socket.assigns.schema
        image_schema = Module.concat([image_schema_binary])

        full_path =
          if image_schema != schema do
            path
          else
            [field_atom]
          end

        singular = schema.__naming__().singular
        target_id = "#{singular}_form"

        send_update(BrandoAdmin.Components.Form,
          id: target_id,
          action: :image_processed,
          image_id: image.id
        )

        route_image_update(socket, singular, target_id, full_path, image, :deliver_pending)

      ["gallery", _schema, field_name] ->
        update_gallery_image(socket, field_name, image)

      _ ->
        deliver_pending_image(socket, image)
    end
  end

  # ImageProcessor's final attempt failed. Nothing more will arrive on this
  # topic, so drop the subscription; `{:cont, socket}` because this hook has no
  # UI to update for it.
  #
  # "Final" is guaranteed by the producer, not assumed here:
  # `ImageProcessor.handle_processing_error/4` broadcasts `:error` only when
  # `job.attempt >= job.max_attempts`, so an intermediate attempt that later
  # succeeds never reaches this clause.
  defp handle_hooks_image_info({%Brando.Images.Image{id: id}, [:image, :error], _path}, socket) do
    PubSub.unsubscribe(Brando.pubsub(), "brando:image:#{id}")
    {:cont, socket}
  end

  defp handle_hooks_image_info({:register_pending_block_image, image_id, {module, id}}, socket) do
    {:halt, update(socket, :pending_block_image_updates, &Map.put(&1, image_id, {module, id}))}
  end

  defp handle_hooks_image_info({:register_pending_block_image, _image_id, invalid_target}, socket) do
    require Logger
    Logger.warning("Ignoring register_pending_block_image with non-stable target: #{inspect(invalid_target)}")
    {:halt, socket}
  end

  defp handle_hooks_image_info(_, socket), do: {:cont, socket}

  # Route transformer image updates to the Transformer component
  defp route_image_update(socket, singular, target_id, full_path, image, on_invalid_path) do
    case full_path do
      [:transformer, relation_key | _] ->
        update_transformer_image(socket, singular, relation_key, image)

      _ ->
        # Only send update_entry_relation if the path is a valid struct field path.
        if valid_struct_path?(full_path) do
          send_update(BrandoAdmin.Components.Form,
            id: target_id,
            event: "update_entry_relation",
            updated_relation: image,
            path: full_path,
            force_validation: true
          )

          {:halt, socket}
        else
          invalid_path_image_update(on_invalid_path, socket, image)
        end
    end
  end

  defp invalid_path_image_update(:cont, socket, _image), do: {:cont, socket}

  # A manager upload carries no struct path — its destination lives
  # in the pending registry instead.
  defp invalid_path_image_update(:deliver_pending, socket, image), do: deliver_pending_image(socket, image)

  # Currently unreachable: no producer emits a path headed by
  # `:transformer`. `field_full_path` comes from `queue_processing/4`,
  # whose callers pass either the default `[]` (crop.ex, form.ex:2920/
  # 3264/4153), `edit_image.path ++ [field]` (form.ex:3358 — and
  # `edit_image.path` is only ever set by `Input.Image`, which a
  # transformer never renders; it draws its own `asset_picker` because
  # "a transformer item deliberately has none"), or
  # `image_field_path(target)` (upload_manager.ex:425), which returns a
  # path only for `"kind" => "entry_field"` while the transformer
  # enqueues `"transformer_image"`. Transformer image cards are updated
  # through `pending_block_image_updates` instead, not through here.
  #
  # Kept rather than deleted, but with the id corrected: it was built off the
  # Form *component* id (`<singular>_form`) where the component is registered
  # under the HTML form id (`<singular>`), so anything that made this live
  # would have addressed a component that does not exist and failed silently.
  defp update_transformer_image(socket, singular, relation_key, image) do
    relation_atom = String.to_existing_atom(relation_key)
    transformer_id = "#{singular}-transformer-#{relation_atom}"

    send_update(BrandoAdmin.Components.Form.Transformer,
      id: transformer_id,
      event: "image_updated",
      image: image
    )

    {:halt, socket}
  end

  defp update_gallery_image(socket, field_name, image) do
    singular = socket.assigns.schema.__naming__().singular

    send_update(BrandoAdmin.Components.Form.Input.Gallery,
      id: "#{singular}_#{field_name}",
      action: :update_image,
      updated_image: image,
      force_validation: true
    )

    {:halt, socket}
  end

  # All NINE form-side subscribes sit immediately before a processing round is
  # queued — `form.ex:3550,3993,4785` (upload, focal re-crop, block re-crop) and
  # `deliver_asset/3` ×6 (`:536,556,628,653,688,717`, each on upload completion
  # for one freshly uploaded image). So the subscription can be dropped once that
  # round finishes: a later LOCALLY started round re-subscribes itself before
  # queueing. Without this they accumulated for the life of the form, one per
  # uploaded or re-cropped image, each still delivering to a process that had
  # already updated. The sticky `UploadManager` has always got this right.
  #
  # Note the qualifier: this scopes the form's interest to rounds IT starts. A
  # round started elsewhere — another admin re-cropping, a re-process from the
  # image list — no longer reaches this form, where the session-long
  # subscription used to deliver it. That is the deliberate trade; if a form
  # ever needs to follow an image it did not touch, this is the line to revisit.
  # (`form.ex:3993` subscribes and only conditionally requeues, so it can leave
  # a subscription with no round pending. Harmless — it is dropped by whichever
  # round completes next.)
  #
  # It must be `:processed`, not merely `[:image, :updated]` — `ImageUploader`
  # broadcasts `:updated` for the freshly uploaded, still-UNPROCESSED image, and
  # unsubscribing there would drop the notification the form is waiting for.
  defp maybe_unsubscribe_from_image(%{id: id, status: :processed}) do
    PubSub.unsubscribe(Brando.pubsub(), "brando:image:#{id}")
  end

  defp maybe_unsubscribe_from_image(_image), do: :ok

  # Check if this is a pending block image update (e.g. block upload or "save as
  # new copy" from a block). Uses stable {module, id} tuples.
  defp deliver_pending_image(socket, image) do
    pending = Map.get(socket.assigns, :pending_block_image_updates, %{})

    case Map.fetch(pending, image.id) do
      :error ->
        {:cont, socket}

      {:ok, {module, id}} ->
        send_update(module, id: id, event: "image_processed", image: image)

        # An image row is broadcast as :updated before its sizes exist, so
        # consuming the registration on that first update throws away the one
        # that matters and leaves the card stuck on "Processing" forever.
        if image.status == :processed do
          {:halt, assign(socket, :pending_block_image_updates, Map.delete(pending, image.id))}
        else
          {:halt, socket}
        end

      {:ok, unexpected_target} ->
        require Logger

        Logger.warning("Dropping pending block image update with unexpected target: #{inspect(unexpected_target)}")

        {:halt, assign(socket, :pending_block_image_updates, Map.delete(pending, image.id))}
    end
  end

  # Asset delivery from the sticky UploadManager (docs/UPLOADER.md §6.3/§7).
  # Orphan-safe: the asset is already persisted when this fires; if the target
  # component is gone, send_update logs a miss and nothing else happens.
  defp handle_asset_delivery_info({:asset_ready, target, asset}, socket) do
    # Gallery additions must land ONE PER RENDER CYCLE — parallel uploads
    # deliver in quick succession and LiveView batches the resulting
    # send_updates, making the block process multiple adds against the same
    # initial state (adds get lost; the old flow serialized via the
    # client-side next_file dance). Queue them with a small spacing instead.
    if target["kind"] in [
         "block_ref_gallery",
         "entry_field_gallery",
         "block_var_gallery",
         "entry_var_gallery",
         "resource_gallery"
       ] do
      queue = socket.assigns[:gallery_delivery_queue] || []

      if queue == [] do
        Process.send_after(self(), :deliver_next_gallery_asset, 25)
      end

      {:halt, assign(socket, :gallery_delivery_queue, queue ++ [{target, asset}])}
    else
      safe_deliver_asset(target, asset, socket)
      {:halt, socket}
    end
  end

  defp handle_asset_delivery_info(:deliver_next_gallery_asset, socket) do
    case socket.assigns[:gallery_delivery_queue] || [] do
      [] ->
        {:halt, socket}

      [{target, asset} | rest] ->
        safe_deliver_asset(target, asset, socket)

        if rest != [] do
          Process.send_after(self(), :deliver_next_gallery_asset, 25)
        end

        {:halt, assign(socket, :gallery_delivery_queue, rest)}
    end
  end

  defp handle_asset_delivery_info(_, socket), do: {:cont, socket}

  defp safe_deliver_asset(target, asset, socket) do
    deliver_asset(target, asset, socket)
  rescue
    error ->
      require Logger

      Logger.error(
        "==> asset_ready: delivery failed for target #{inspect(target)}: #{Exception.message(error)} — " <>
          "asset ##{asset.id} remains in the library"
      )
  end

  defguardp is_var_asset(asset)
            when is_struct(asset, Brando.Images.Image) or is_struct(asset, Brando.Files.File) or
                   is_struct(asset, Brando.Videos.Video)

  # Scalar vars hold image/file/video FKs — classify by struct (the target's
  # "asset_type" string can lie for e.g. self-hosted video), and refuse
  # anything else rather than writing a foreign id into file_id.
  defp deliver_asset(%{"kind" => kind, "component_id" => component_id} = target, asset, _socket)
       when kind in ["block_var", "entry_var", "block_var_gallery", "entry_var_gallery"] and
              is_binary(component_id) and is_var_asset(asset) do
    asset_type = var_asset_type(asset)
    asset = refresh_processed_image(asset)

    if asset_type == :image do
      PubSub.subscribe(Brando.pubsub(), "brando:image:#{asset.id}")
    end

    send_update(BrandoAdmin.Components.Form.Input.RenderVar,
      id: component_id,
      event: "upload_complete",
      expected_asset_id: target["expected_asset_id"],
      asset_type: asset_type,
      asset: asset
    )

    if asset_type == :image && asset.status != :processed do
      send(self(), {:register_pending_block_image, asset.id, {BrandoAdmin.Components.Form.Input.RenderVar, component_id}})
      maybe_forward_already_processed(asset, BrandoAdmin.Components.Form.Input.RenderVar, component_id)
    end
  end

  # Attach the uploaded image immediately, then refresh its preview after
  # processing without replacing a newer selection in the ref.
  defp deliver_asset(
         %{"kind" => "block_ref_picture", "component_id" => component_id} = target,
         %Brando.Images.Image{} = image,
         _socket
       )
       when is_binary(component_id) do
    send_update(BrandoAdmin.Components.Form.Input.Blocks.PictureBlock,
      id: component_id,
      event: "image_uploaded",
      image: image,
      expected_asset_id: target["expected_asset_id"]
    )

    PubSub.subscribe(Brando.pubsub(), "brando:image:#{image.id}")

    send(
      self(),
      {:register_pending_block_image, image.id, {BrandoAdmin.Components.Form.Input.Blocks.PictureBlock, component_id}}
    )

    maybe_forward_already_processed(image, BrandoAdmin.Components.Form.Input.Blocks.PictureBlock, component_id)
  end

  defp deliver_asset(
         %{"kind" => "block_ref_file", "component_id" => component_id} = target,
         %Brando.Files.File{} = file,
         _socket
       )
       when is_binary(component_id) do
    send_update(BrandoAdmin.Components.Form.Input.Blocks.FileBlock,
      id: component_id,
      event: "live_upload_complete",
      expected_asset_id: target["expected_asset_id"],
      file: file
    )
  end

  defp deliver_asset(
         %{"kind" => "block_ref_video", "component_id" => component_id} = target,
         %Brando.Videos.Video{} = video,
         _socket
       )
       when is_binary(component_id) do
    send_update(BrandoAdmin.Components.Form.Input.Blocks.VideoBlock,
      id: component_id,
      event: "select_video",
      expected_asset_id: target["expected_asset_id"],
      video_id: video.id
    )
  end

  # An upload from the image picker is already in the library; the open
  # picker only has to list it. It lists processed images, and processing
  # usually finishes after delivery, so follow the image: its `:updated`
  # broadcast refreshes the picker (`handle_hooks_image_info/2`). Subscribed
  # before this refresh, so an image processed in between is still listed.
  defp deliver_asset(%{"kind" => "image_picker", "component_id" => component_id}, %Brando.Images.Image{} = image, _socket)
       when is_binary(component_id) do
    PubSub.subscribe(Brando.pubsub(), "brando:image:#{image.id}")
    send_update(BrandoAdmin.Components.ImagePicker, id: component_id, refresh_images: true)
  end

  defp deliver_asset(
         %{"kind" => "video_picker", "component_id" => component_id},
         %Brando.Videos.Video{} = video,
         _socket
       )
       when is_binary(component_id) do
    send_update(BrandoAdmin.Components.VideoPicker,
      id: component_id,
      event: "upload_complete",
      asset: video
    )
  end

  defp deliver_asset(
         %{"kind" => "transformer_video", "component_id" => component_id} = target,
         %Brando.Videos.Video{} = video,
         _socket
       )
       when is_binary(component_id) do
    send_update(BrandoAdmin.Components.Form.Transformer,
      id: component_id,
      event: "upload_complete",
      asset: video,
      ref: Map.get(target, "ref")
    )
  end

  # The transformer takes the image id immediately — the card renders its
  # placeholder while processing — and the "brando:image:<id>" machinery swaps in
  # the processed struct when the sizes are done.
  defp deliver_asset(
         %{"kind" => "transformer_image", "component_id" => component_id} = target,
         %Brando.Images.Image{} = image,
         _socket
       )
       when is_binary(component_id) do
    PubSub.subscribe(Brando.pubsub(), "brando:image:#{image.id}")

    send_update(BrandoAdmin.Components.Form.Transformer,
      id: component_id,
      event: "upload_complete",
      asset: image,
      ref: Map.get(target, "ref")
    )

    # Subscribing is only half of it — the processed struct still needs somewhere
    # to go, or the card sits on "Processing" forever with no thumbnail.
    send(
      self(),
      {:register_pending_block_image, image.id, {BrandoAdmin.Components.Form.Transformer, component_id}}
    )

    # And subscribing plus registering is still only two thirds of it. Both only
    # catch a broadcast that has yet to happen: a local libvips run over a JPEG
    # finishes in well under a second, so `:processed` is regularly broadcast
    # before this LiveView even handles `:asset_ready`. The registration is then
    # stranded in `pending_block_image_updates` with nothing left to consume it,
    # and the card sits on "Processing" for the life of the form — which is the
    # exact failure the comment above says the registration prevents.
    maybe_forward_already_processed(image, BrandoAdmin.Components.Form.Transformer, component_id)
  end

  # Gallery refs add the image_id immediately (placeholder renders while
  # processing), then the pending registration swaps in the processed struct.
  defp deliver_asset(
         %{"kind" => "block_ref_gallery", "component_id" => component_id},
         %Brando.Images.Image{} = image,
         _socket
       )
       when is_binary(component_id) do
    PubSub.subscribe(Brando.pubsub(), "brando:image:#{image.id}")

    send_update(BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock,
      id: component_id,
      event: "live_upload_complete",
      image_id: image.id
    )

    send(
      self(),
      {:register_pending_block_image, image.id, {BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock, component_id}}
    )

    maybe_forward_already_processed(image, BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock, component_id)
  end

  defp deliver_asset(
         %{"kind" => "block_ref_gallery", "component_id" => component_id},
         %Brando.Videos.Video{} = video,
         _socket
       )
       when is_binary(component_id) do
    send_update(BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock,
      id: component_id,
      event: "video_created_from_url",
      video_data: %{id: video.id}
    )
  end

  # Entry schema fields (Phase 4) — route to the Form component, which updates
  # the entry changeset at the field's (possibly nested) path.
  defp deliver_asset(%{"kind" => "entry_field", "field" => field} = target, asset, socket)
       when is_binary(field) and
              (is_struct(asset, Brando.Files.File) or is_struct(asset, Brando.Images.Image) or
                 is_struct(asset, Brando.Videos.Video)) do
    singular = socket.assigns.schema.__naming__().singular

    asset_type =
      case asset do
        %Brando.Images.Image{} -> :image
        %Brando.Videos.Video{} -> :video
        _ -> :file
      end

    # processed-image updates ride the existing "brando:image:<id>" machinery
    # (config_target "image:Schema:field" routes image_processed +
    # update_entry_relation back to the form)
    if asset_type == :image do
      PubSub.subscribe(Brando.pubsub(), "brando:image:#{asset.id}")
    end

    # Inline-Oban / fast-queue race (same recovery block refs get via
    # maybe_forward_already_processed): processing may complete before this
    # delivery runs, and the broadcast fired before we subscribed — refetch so
    # the processed struct lands in the changeset, not the :unprocessed one.
    asset = refresh_processed_image(asset)

    path = target_path(target)

    send_update(BrandoAdmin.Components.Form,
      id: "#{singular}_form",
      event: "entry_field_upload_complete",
      asset_type: asset_type,
      expected_asset_id: target["expected_asset_id"],
      field: String.to_existing_atom(field),
      path: path,
      asset: asset
    )
  end

  defp deliver_asset(
         %{"kind" => "entry_field_gallery", "field" => field} = target,
         %Brando.Images.Image{} = image,
         socket
       )
       when is_binary(field) do
    singular = socket.assigns.schema.__naming__().singular

    PubSub.subscribe(Brando.pubsub(), "brando:image:#{image.id}")

    send_update(BrandoAdmin.Components.Form,
      id: "#{singular}_form",
      event: "entry_field_upload_complete",
      asset_type: :gallery,
      field: String.to_existing_atom(field),
      path: target_path(target),
      component_id: target["component_id"],
      config_target: target["config_target"],
      asset: refresh_processed_image(image)
    )
  end

  defp deliver_asset(
         %{"kind" => "entry_field_gallery", "field" => field} = target,
         %Brando.Videos.Video{} = video,
         socket
       )
       when is_binary(field) do
    singular = socket.assigns.schema.__naming__().singular

    send_update(BrandoAdmin.Components.Form,
      id: "#{singular}_form",
      event: "entry_field_upload_complete",
      asset_type: :gallery_video,
      field: String.to_existing_atom(field),
      path: target_path(target),
      component_id: target["component_id"],
      config_target: target["config_target"],
      asset: video
    )
  end

  defp deliver_asset(%{"kind" => "resource_gallery", "component_id" => component_id}, asset, _socket)
       when is_struct(asset, Brando.Images.Image) or is_struct(asset, Brando.Videos.Video) do
    module = BrandoAdmin.Components.Form.Input.GalleryObjects
    send_update(module, id: component_id, event: "upload_complete", asset: refresh_processed_image(asset))

    if is_struct(asset, Brando.Images.Image) do
      PubSub.subscribe(Brando.pubsub(), "brando:image:#{asset.id}")
      send(self(), {:register_pending_block_image, asset.id, {module, component_id}})
      maybe_forward_already_processed(asset, module, component_id)
    end
  end

  defp deliver_asset(target, asset, _socket) do
    require Logger

    Logger.debug(
      "==> asset_ready: no deliverable target (#{inspect(target)}) — asset ##{asset.id} remains in the library"
    )
  end

  defp var_asset_type(%Brando.Images.Image{}), do: :image
  defp var_asset_type(%Brando.Files.File{}), do: :file
  defp var_asset_type(%Brando.Videos.Video{}), do: :video

  defp target_path(target) do
    (target["path"] || [])
    |> Enum.map(fn
      segment when is_integer(segment) -> segment
      segment when is_binary(segment) -> String.to_existing_atom(segment)
    end)
  end

  # Processing can finish before this LV handles :asset_ready (Oban
  # testing: :inline runs it synchronously in the manager; a fast queue can
  # win the race in prod too) — the [:image, :updated] broadcast is then
  # already gone. Re-read the image and forward image_processed directly if
  # it is already done.
  defp refresh_processed_image(%Brando.Images.Image{} = image) do
    case Brando.Images.get_image(image.id) do
      {:ok, fresh} -> fresh
      _ -> image
    end
  end

  defp refresh_processed_image(asset), do: asset

  defp maybe_forward_already_processed(image, module, component_id) do
    case Brando.Images.get_image(image.id) do
      {:ok, %{status: :processed} = processed_image} ->
        send_update(module, id: component_id, event: "image_processed", image: processed_image)

      _ ->
        :ok
    end
  end

  @doc """
  Transformer component ids on `schema`'s form that own a `related_schema`.

  Extracted from the webhook routing below so it can be tested without mounting
  a LiveView — both halves of it have been wrong in production:

    * `__relations__` is `Brando.Blueprint.Relations.__relations__/1`, taking the
      module. It is NOT a function on the blueprint, so `schema.__relations__()`
      raises `UndefinedFunctionError` and takes the form down.

    * the id is keyed off the HTML form id (`<singular>`), not the Form
      *component* id (`<singular>_form`). `fieldset/field.ex` renders the
      component as `"\#{@form.id}-transformer-\#{@input.name}"`, so the `_form`
      variant silently addressed a component that does not exist — no crash, no
      log, just a card that never updates.

  Only the webhook path reaches this, which is why neither surfaced until a Mux
  callback arrived: a site with no tunnel in development never runs it.
  """
  @spec transformer_ids_for(module(), module()) :: [String.t()]
  def transformer_ids_for(schema, related_schema) do
    singular = schema.__naming__().singular

    for rel <- Brando.Blueprint.Relations.__relations__(schema),
        rel.type == :has_many,
        get_in(rel.opts, [:module]) == related_schema do
      "#{singular}-transformer-#{rel.name}"
    end
  end

  # Video hooks - handle PubSub updates
  defp handle_hooks_video_info({video, [:video, :updated], path}, socket) do
    case String.split(video.config_target, ":") do
      ["video", video_schema_binary, field_name] ->
        field_atom = String.to_existing_atom(field_name)
        schema = socket.assigns.schema
        video_schema = Module.concat([video_schema_binary])

        full_path =
          if video_schema != schema do
            path
          else
            [field_atom]
          end

        singular = schema.__naming__().singular
        target_id = "#{singular}_form"

        # Only send update_entry_relation if the path is a valid struct field path
        if valid_struct_path?(full_path) do
          send_update(BrandoAdmin.Components.Form,
            id: target_id,
            event: "update_entry_relation",
            updated_relation: video,
            path: full_path,
            force_validation: true
          )

          {:halt, socket}
        else
          {:cont, socket}
        end

      _ ->
        {:cont, socket}
    end
  end

  # 2-tuple video updates (from webhook PubSub, no path) — route to Transformer components
  defp handle_hooks_video_info({video, [:video, :updated]}, socket) do
    case String.split(video.config_target || "", ":") do
      ["video", video_schema_binary, _field_name] ->
        schema = socket.assigns.schema
        video_schema = Module.concat([video_schema_binary])

        if video_schema != schema do
          # Video belongs to a relation module — route to all Transformer components.
          # Each component checks internally if it owns this video.
          send_transformer_video_updates(schema, video_schema, video)
          {:halt, socket}
        else
          {:cont, socket}
        end

      _ ->
        {:cont, socket}
    end
  end

  defp handle_hooks_video_info(_, socket), do: {:cont, socket}

  defp send_transformer_video_updates(schema, video_schema, video) do
    for transformer_id <- transformer_ids_for(schema, video_schema) do
      send_update(BrandoAdmin.Components.Form.Transformer,
        id: transformer_id,
        event: "video_updated",
        video: video
      )
    end
  end

  # Port exit hooks - catch normal exits from image processing ports (ImageMagick, etc.)
  defp handle_hooks_port_exits({:EXIT, _port, :normal}, socket), do: {:halt, socket}
  defp handle_hooks_port_exits(_, socket), do: {:cont, socket}

  # Video event hooks - handle generic video uploader events
  # These work with the supported direct provider strategies (Mux, Bunny, and Cloudflare).

  # Generic event for getting an upload URL. Keep the complete request intact:
  # its opaque ref is the response correlation key, while size/type feed the
  # server-side provider intake policy.
  defp handle_hooks_video_event("get_video_upload_url", params, socket) when is_map(params) do
    schema = socket.assigns.schema
    singular = schema.__naming__().singular
    form_id = "#{singular}_form"

    # Delegate to Form component - it will push event back to JS when ready
    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :get_video_upload_url,
      upload_request: params
    )

    # Halt so the event doesn't propagate to LiveView-specific handlers
    {:halt, socket}
  end

  # Generic event for upload completion - works with any strategy
  defp handle_hooks_video_event("video_upload_complete", %{"video_id" => video_id}, socket) do
    schema = socket.assigns.schema
    singular = schema.__naming__().singular
    form_id = "#{singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :video_upload_complete,
      video_id: video_id
    )

    {:halt, socket}
  end

  # Generic event for upload progress - works with any strategy
  defp handle_hooks_video_event("video_upload_progress", %{"video_id" => video_id, "percentage" => percentage}, socket) do
    schema = socket.assigns.schema
    singular = schema.__naming__().singular
    form_id = "#{singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :video_upload_progress,
      video_id: video_id,
      percentage: percentage
    )

    {:halt, socket}
  end

  # Provider failures (Mux/Bunny/Cloudflare hooks push this untargeted) — route to the
  # Form component; without a clause here the event falls through to a
  # LiveView with no handle_event and crashes the whole form view.
  defp handle_hooks_video_event("upload_error", %{"error" => error} = params, socket) do
    schema = socket.assigns.schema
    singular = schema.__naming__().singular
    form_id = "#{singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :video_upload_error,
      filename: params["filename"],
      error: error
    )

    {:halt, socket}
  end

  defp handle_hooks_video_event(_, _, socket), do: {:cont, socket}

  defp handle_hooks_alert_info({:alert, message}, %{assigns: %{current_user: current_user}} = socket) do
    BrandoAdmin.Alert.send_to(current_user, message)
    {:halt, socket}
  end

  defp handle_hooks_alert_info(_, socket), do: {:cont, socket}

  defp handle_hooks_toast_info({:toast, message}, %{assigns: %{current_user: current_user}} = socket) do
    BrandoAdmin.Toast.send_to(current_user, message)
    {:halt, socket}
  end

  defp handle_hooks_toast_info(_, socket), do: {:cont, socket}

  defp handle_hooks_progress_popup_info({:progress_popup, message}, %{assigns: %{current_user: current_user}} = socket) do
    BrandoAdmin.ProgressPopup.send_to(current_user, message)
    {:halt, socket}
  end

  defp handle_hooks_progress_popup_info(_, socket), do: {:cont, socket}

  defp handle_hooks_content_language_info(
         {:set_content_language, language},
         %{assigns: %{current_user: current_user}} = socket
       ) do
    updated_data = %{config: %{content_language: language}}

    {:ok, updated_current_user} =
      Brando.Users.update_user(
        current_user,
        updated_data,
        :system,
        show_notification: false
      )

    toast_message =
      gettext("Content language is now %{language}", language: String.upcase(language))

    send(self(), {:toast, toast_message})
    # send a message that the language has switched. we use this
    # for special views like identity_live and seo_live
    send(self(), {:content_language, language})

    {:halt, assign(socket, :current_user, updated_current_user)}
  end

  defp handle_hooks_content_language_info(_, socket), do: {:cont, socket}

  defp handle_hooks_dirty_fields_info({:dirty_fields, fields, user_id}, socket) do
    socket =
      if user_id == socket.assigns.current_user.id do
        Brando.presence().update_dirty_fields(socket.assigns.uri.path, user_id, fields)
        socket
      else
        BrandoAdmin.Hooks.push_dirty_fields(socket, user_id, fields)
      end

    {:halt, socket}
  end

  defp handle_hooks_dirty_fields_info(_, socket), do: {:cont, socket}

  # The field a tab is in; `field` is nil when it left the field, which
  # releases it. Locks are per tab: our own tab records its field in its
  # presence meta (for editors who join later), our other tabs are not shown
  # as locks to us, and another editor's tabs each lock their own field.
  defp handle_hooks_active_field_info({:active_field, field, user_id, tab}, socket) do
    socket =
      cond do
        tab == BrandoAdmin.Presence.tab() ->
          schedule_active_field_write(socket.assigns.uri.path, field)
          socket

        user_id == socket.assigns.current_user.id ->
          socket

        true ->
          push_event(socket, "b:set_active_field", %{user_id: user_id, field: field, tab: tab})
      end

    {:halt, socket}
  end

  defp handle_hooks_active_field_info({:brando_active_field_write, token, path, field}, socket) do
    with ^token <- Process.get(:brando_active_field_write),
         false <- Process.get(:brando_active_field_written, nil) == field do
      Brando.presence().update_active_field(path, socket.assigns.current_user.id, field)
      Process.put(:brando_active_field_written, field)
    end

    {:halt, socket}
  end

  defp handle_hooks_active_field_info(_, socket), do: {:cont, socket}

  # The presence meta only tells editors who join later which field this tab
  # is in; the others hear it at once from the broadcast. Each write costs a
  # presence diff (a join and a leave, and a user lookup in every editor's
  # process), so a blur followed by a focus within 300 ms writes once, and a
  # field the meta already has is not written again.
  #
  # The write goes to the page it was scheduled on; navigating away drops it
  # (`BrandoAdmin.Hooks.handle_params/3`).
  defp schedule_active_field_write(path, field) do
    token = make_ref()
    Process.put(:brando_active_field_write, token)
    Process.send_after(self(), {:brando_active_field_write, token, path, field}, 300)
  end

  # Field presence: the block and the field in it another editor is in, with
  # their name for the label ("Ingrid · Caption").
  defp handle_hooks_block_presence_info({:block_focus, %{uid: uid, user_id: user_id} = focus}, socket) do
    socket =
      if user_id == socket.assigns.current_user.id do
        socket
      else
        push_event(socket, "b:set_active_block", %{
          uid: uid,
          user_id: user_id,
          field: Map.get(focus, :field),
          label: Map.get(focus, :label),
          name: presence_name(socket, user_id)
        })
      end

    {:halt, socket}
  end

  defp handle_hooks_block_presence_info({:block_blur, %{uid: uid, user_id: user_id}}, socket) do
    socket =
      if user_id == socket.assigns.current_user.id do
        socket
      else
        push_event(socket, "b:clear_block_lock", %{uid: uid, user_id: user_id})
      end

    {:halt, socket}
  end

  defp handle_hooks_block_presence_info(_, socket), do: {:cont, socket}

  defp presence_name(socket, user_id) do
    case socket.assigns[:presences] do
      %{^user_id => %{name: name}} when is_binary(name) -> name
      _ -> nil
    end
  end

  # Block and field presence — fired by the Brando.Block JS hook on focusin
  # and pointerdown, with the field (its element id) and a label for it.
  defp handle_hooks_block_focused_event("block_focused", %{"uid" => uid} = params, socket) do
    entry_id = socket.assigns[:entry_id]
    current_user_id = socket.assigns.current_user.id
    old_uid = socket.assigns[:current_focused_block_uid]
    old_field = socket.assigns[:current_focused_block_field]
    field = string_or_nil(params["field"])
    label = string_or_nil(params["label"])

    if entry_id do
      if old_uid && old_uid != uid do
        PubSub.broadcast(
          Brando.pubsub(),
          Topic.entry("block_presence", socket.assigns.schema, entry_id),
          {:block_blur, %{uid: old_uid, user_id: current_user_id}}
        )
      end

      PubSub.broadcast(
        Brando.pubsub(),
        Topic.entry("block_presence", socket.assigns.schema, entry_id),
        {:block_focus, %{uid: uid, field: field, label: label, user_id: current_user_id}}
      )
    end

    if {old_uid, old_field} != {uid, field},
      do: send_to_block_fields(socket, event: "local_focus", uid: uid, field: field)

    {:halt,
     socket
     |> assign(:current_focused_block_uid, uid)
     |> assign(:current_focused_block_field, field)
     |> assign(:current_focused_block_label, label)}
  end

  # Fired by the Block JS hook when focus settles after a focusout.
  # `still_inside` distinguishes moving between refs in the same block (keep
  # presence) from leaving the block entirely (presence blur, and the block
  # takes the other editors' changes it held back while it was in use).
  defp handle_hooks_block_focused_event("block_blurred", %{"uid" => uid} = params, socket) do
    if Map.get(params, "still_inside", false) or socket.assigns[:current_focused_block_uid] != uid do
      {:halt, socket}
    else
      {:halt, clear_block_focus(socket)}
    end
  end

  defp handle_hooks_block_focused_event(_, _, socket), do: {:cont, socket}

  defp string_or_nil(value) when is_binary(value) and value != "", do: String.slice(value, 0, 200)
  defp string_or_nil(_value), do: nil

  defp clear_block_focus(socket) do
    current_uid = socket.assigns[:current_focused_block_uid]
    entry_id = socket.assigns[:entry_id]

    if current_uid do
      if entry_id do
        PubSub.broadcast(
          Brando.pubsub(),
          Topic.entry("block_presence", socket.assigns.schema, entry_id),
          {:block_blur, %{uid: current_uid, user_id: socket.assigns.current_user.id}}
        )
      end

      send_to_block_fields(socket, event: "local_focus", uid: nil, field: nil)
    end

    socket
    |> assign(:current_focused_block_uid, nil)
    |> assign(:current_focused_block_field, nil)
    |> assign(:current_focused_block_label, nil)
  end

  # An entry field took the focus, or a save started: no block is in use.
  defp handle_hooks_block_sync_info(:clear_block_focus, socket) do
    {:halt, clear_block_focus(socket)}
  end

  # The entry's edit session (`Brando.EditSession`) broadcast an op or a
  # rebase for one block field, or rejected one of ours. The field's
  # BlockField applies it to its replica.
  defp handle_hooks_block_sync_info({:edit_session, field, message}, socket) do
    send_to_block_field(socket, field, event: "edit_session", message: message)
    {:halt, socket}
  end

  # The session a BlockField replicates died (BlockField put the monitor).
  defp handle_hooks_block_sync_info({:DOWN, ref, :process, _pid, _reason}, socket) do
    case Process.delete({:brando_edit_session_monitor, ref}) do
      nil ->
        {:cont, socket}

      component_id ->
        send_update(BrandoAdmin.Components.Form.BlockField, id: component_id, event: "edit_session_down")
        {:halt, socket}
    end
  end

  # Another tab opened the entry (another editor's, or one that reconnected).
  # Its form (`part: :fields`) gets our unsaved ENTRY FIELD values (title,
  # slug, ...), addressed to it, and the field we are in. Its block fields
  # (`part: :blocks`) need no values, since the edit session gives them their
  # state, but get our current block focus: presence is event-driven, so the
  # joiner would otherwise not see where we are until our next focus.
  defp handle_hooks_block_sync_info({:editor_joined, %{tab: tab, part: :fields}}, socket) do
    if tab != BrandoAdmin.Presence.tab() do
      if schema = socket.assigns[:schema] do
        singular = schema.__naming__().singular
        send_update(BrandoAdmin.Components.Form, id: "#{singular}_form", event: "ship_field_changes", to: tab)
        send_update(BrandoAdmin.Components.Form, id: "#{singular}_form", event: "reship_active_field")
      end
    end

    {:halt, socket}
  end

  defp handle_hooks_block_sync_info({:editor_joined, %{tab: tab, part: :blocks}}, socket) do
    if tab != BrandoAdmin.Presence.tab() do
      focused_uid = socket.assigns[:current_focused_block_uid]
      entry_id = socket.assigns[:entry_id]

      if focused_uid && entry_id do
        PubSub.broadcast(
          Brando.pubsub(),
          Topic.entry("block_presence", socket.assigns.schema, entry_id),
          {:block_focus,
           %{
             uid: focused_uid,
             field: socket.assigns[:current_focused_block_field],
             label: socket.assigns[:current_focused_block_label],
             user_id: socket.assigns.current_user.id
           }}
        )
      end
    end

    {:halt, socket}
  end

  # Field sync: the entry fields another tab changed, or, addressed to this
  # tab (`to`) when it joined, the unsaved values they hold. Two tabs of one
  # editor sync like two editors.
  defp handle_hooks_block_sync_info({:fields_shipped, %{tab: from} = msg}, socket) do
    me = BrandoAdmin.Presence.tab()

    if from != me and Map.get(msg, :to) in [nil, me] do
      schema = socket.assigns[:schema]

      if schema do
        singular = schema.__naming__().singular
        form_id = "#{singular}_form"

        send_update(BrandoAdmin.Components.Form,
          id: form_id,
          event: "apply_remote_field_changes",
          changes: msg.changes,
          clocks: Map.get(msg, :clocks)
        )
      end
    end

    {:halt, socket}
  end

  # Multi-select sync — forward selected IDs directly to the multi-select component
  defp handle_hooks_block_sync_info({:multi_select_changed, %{user_id: user_id} = msg}, socket) do
    if user_id != socket.assigns.current_user.id do
      send_update(BrandoAdmin.Components.Form.Input.MultiSelect,
        id: msg.component_id,
        event: "apply_remote_selections",
        selected_ids: msg.selected_ids
      )
    end

    {:halt, socket}
  end

  defp handle_hooks_block_sync_info(_, socket), do: {:cont, socket}

  defp send_to_block_fields(socket, opts) do
    schema = socket.assigns[:schema]

    if schema && function_exported?(schema, :__blocks_fields__, 0) do
      for %{name: field} <- schema.__blocks_fields__() do
        send_to_block_field(socket, field, opts)
      end
    end
  end

  defp send_to_block_field(socket, field, opts) do
    if schema = socket.assigns[:schema] do
      block_field_id = "#{schema.__naming__().singular}_form-blocks-#{field}"
      send_update(BrandoAdmin.Components.Form.BlockField, [{:id, block_field_id} | opts])
    end
  end

  # Someone added, answered, resolved or reopened a note on this entry, or a
  # save moved an anchor: the notes panel reloads them (`Brando.Notes`).
  defp handle_hooks_notes_info({:notes_changed, msg}, socket) do
    if schema = socket.assigns[:schema] do
      send_update(BrandoAdmin.Components.Form.NotesDrawer,
        id: "#{schema.__naming__().singular}_form-notes",
        event: :refresh,
        origin: msg.origin,
        note_event: msg.event
      )
    end

    {:halt, socket}
  end

  defp handle_hooks_notes_info(_, socket), do: {:cont, socket}

  defp handle_hooks_tiptap_link_info({:tiptap_set_link, tiptap_id, link_data}, socket) do
    {:halt, push_event(socket, "b:tiptap:set_link:#{tiptap_id}", link_data)}
  end

  defp handle_hooks_tiptap_link_info(_, socket), do: {:cont, socket}

  defp handle_hooks_modules_info({module, [:module, action]}, socket) when action in [:created, :updated] do
    schema = socket.assigns.schema

    for %{name: field} <- schema.__blocks_fields__() do
      target_id = "block-field-#{field}-module-picker"

      send_update(BrandoAdmin.Components.Form.BlockField.ModulePicker,
        id: target_id,
        event: :refresh_modules
      )
    end

    # Blocks using an updated module take its editor settings (Write with AI)
    if action == :updated and schema.__blocks_fields__() != [] do
      send_update(BrandoAdmin.Components.Form,
        id: "#{schema.__naming__().singular}_form",
        event: "module_updated",
        module_id: module.id
      )
    end

    {:halt, socket}
  end

  defp handle_hooks_modules_info(_, socket), do: {:cont, socket}

  defp handle_hooks_mutation_listener_info({:register_mutation_listener, schema, target}, socket) do
    PubSub.subscribe(Brando.pubsub(), Topic.scoped("brando:mutations:#{inspect(schema)}"))

    {:halt,
     update(socket, :mutation_listeners, fn mls ->
       Map.update(mls, schema, [target], &[target | &1])
     end)}
  end

  defp handle_hooks_mutation_listener_info(_, socket), do: {:cont, socket}

  defp handle_hooks_mutations_info({:mutation, module, _entry, _action}, socket) do
    targets = Map.get(socket.assigns.mutation_listeners, module, [])

    for target <- targets do
      send_update(
        target,
        action: :force_refresh_options
      )
    end

    {:halt, socket}
  end

  defp handle_hooks_mutations_info(_, socket), do: {:cont, socket}

  defp assign_schema(socket, schema) do
    assign_new(socket, :schema, fn ->
      schema
    end)
  end

  # The browser tab: "mmmMarbles — Project" for an entry, "New project" on
  # create. Several open forms are told apart by what they edit, not by id.
  defp assign_title(%{assigns: %{schema: schema}} = socket) do
    assign(socket, :page_title, form_title(schema, socket.assigns[:entry_id]))
  end

  @doc false
  def form_title(schema, entry_id) do
    singular = Brando.Blueprint.get_singular(schema)

    case entry_id && entry_title(schema, entry_id) do
      nil when is_nil(entry_id) -> gettext("New %{singular}", singular: String.downcase(singular))
      nil -> singular
      title -> "#{title} — #{singular}"
    end
  end

  defp entry_title(schema, entry_id) do
    with true <- function_exported?(schema, :__has_identifier__, 0) and schema.__has_identifier__(),
         %{} = entry <- Brando.Repo.get(schema, entry_id),
         entry = Brando.Repo.preload(entry, schema.__identifier_preloads__()),
         %{title: title} when is_binary(title) and title != "" <- schema.__identifier__(entry) do
      title
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp assign_entry_id(socket, entry_id) do
    assign(socket, :entry_id, entry_id)
  end

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language
    |> to_string()
    |> Gettext.put_locale()

    socket
  end

  defp assign_action(socket, action) do
    assign(socket, :form_action, action)
  end

  # Check if a path is a valid struct field path (contains at least one atom)
  # vs metadata path (contains only integers, which are IDs).
  # Valid paths: [:listing_image], [:media_items, 0, :image]
  # Metadata paths: [132] (just an ID)
  defp valid_struct_path?(path) when is_list(path) do
    Enum.any?(path, &is_atom/1)
  end

  defp valid_struct_path?(_), do: false
end
