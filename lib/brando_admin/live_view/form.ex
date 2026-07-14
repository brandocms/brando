defmodule BrandoAdmin.LiveView.Form do
  @moduledoc """
  A module that keeps using definitions for form live views

  This can be used in your application as:

      use BrandoAdmin.LiveView.Form, schema: MyApp.Projects.Project

  """
  import Phoenix.LiveView
  import Phoenix.Component
  use Gettext, backend: Brando.Gettext

  defmacro __using__(opts) do
    schema = Keyword.fetch!(opts, :schema)
    skip_image_hooks = Keyword.get(opts, :skip_image_hooks, false)

    quote do
      use BrandoAdmin, :live_view

      on_mount({BrandoAdmin.LiveView.Form, {:setup, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_progress_popup, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_alert, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_content_language, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_dirty_fields, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_active_field, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_block_presence, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_block_sync, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_modules, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_focal_point, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_focus, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_mutations, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_mutation_listener, unquote(schema)}})

      unless unquote(skip_image_hooks) do
        on_mount({BrandoAdmin.LiveView.Form, {:hooks_images, unquote(schema)}})
      end

      on_mount({BrandoAdmin.LiveView.Form, {:hooks_asset_delivery, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_tiptap_link, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_videos, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_video_events, unquote(schema)}})

      # Catch port exits from image processing (ImageMagick, etc)
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_port_exits, unquote(schema)}})
    end
  end

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

      Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:dirty_fields:#{entry_id}")
      Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:active_field:#{entry_id}")
      Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:block_presence:#{entry_id}")
      Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:field_sync:#{entry_id}")

      {:cont, assign(socket, :current_focused_block_uid, nil)}
    else
      {:cont, assign(socket, :socket_connected, false)}
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
      {:cont, assign(socket, :socket_connected, false)}
    end
  end

  def on_mount({:hooks_images, _schema}, _params, _session, socket) do
    {:cont,
     socket
     |> assign(:pending_block_image_updates, %{})
     |> attach_hook(:b_form_images, :handle_info, &handle_hooks_image_info/2)}
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

  def on_mount({:hooks_tiptap_link, _schema}, _params, _session, socket) do
    {:cont, attach_hook(socket, :b_form_tiptap_link, :handle_info, &handle_hooks_tiptap_link_info/2)}
  end

  defp maybe_arm_entry_scope(%{"entry_id" => entry_id}, _uri, %{assigns: %{entry_id: nil}} = socket) do
    Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:dirty_fields:#{entry_id}")
    Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:active_field:#{entry_id}")
    Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:block_presence:#{entry_id}")
    Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:field_sync:#{entry_id}")

    {:cont,
     socket
     |> assign_action(:update)
     |> assign_entry_id(entry_id)}
  end

  defp maybe_arm_entry_scope(_params, _uri, socket), do: {:cont, socket}

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

        case full_path do
          [:transformer, relation_key | _] ->
            relation_atom = String.to_existing_atom(relation_key)
            transformer_id = "#{target_id}-transformer-#{relation_atom}"

            send_update(BrandoAdmin.Components.Form.Transformer,
              id: transformer_id,
              event: "image_updated",
              image: image
            )

            {:halt, socket}

          _ ->
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
              {:cont, socket}
            end
        end

      ["gallery", _schema, field_name] ->
        # Gallery images during processing - update the gallery input
        schema = socket.assigns.schema
        singular = schema.__naming__().singular
        target_id = "#{singular}_#{field_name}"

        send_update(BrandoAdmin.Components.Form.Input.Gallery,
          id: target_id,
          action: :update_image,
          updated_image: image,
          force_validation: true
        )

        {:halt, socket}

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

        # Route transformer image updates to the Transformer component
        case full_path do
          [:transformer, relation_key | _] ->
            relation_atom = String.to_existing_atom(relation_key)
            transformer_id = "#{target_id}-transformer-#{relation_atom}"

            send_update(BrandoAdmin.Components.Form.Transformer,
              id: transformer_id,
              event: "image_updated",
              image: image
            )

            {:halt, socket}

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
              {:cont, socket}
            end
        end

      ["gallery", _schema, field_name] ->
        schema = socket.assigns.schema
        singular = schema.__naming__().singular
        target_id = "#{singular}_#{field_name}"

        # update image in gallery input
        send_update(BrandoAdmin.Components.Form.Input.Gallery,
          id: target_id,
          action: :update_image,
          updated_image: image,
          force_validation: true
        )

        {:halt, socket}

      _ ->
        # Check if this is a pending block image update (e.g. block upload or
        # "save as new copy" from a block). Uses stable {module, id} tuples.
        pending = Map.get(socket.assigns, :pending_block_image_updates, %{})

        case Map.pop(pending, image.id) do
          {nil, _} ->
            {:cont, socket}

          {{module, id}, remaining} ->
            send_update(module, id: id, event: "image_processed", image: image)
            {:halt, assign(socket, :pending_block_image_updates, remaining)}

          {unexpected_target, remaining} ->
            require Logger

            Logger.warning("Dropping pending block image update with unexpected target: #{inspect(unexpected_target)}")

            {:halt, assign(socket, :pending_block_image_updates, remaining)}
        end
    end
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

  # Asset delivery from the sticky UploadManager (docs/UPLOADER.md §6.3/§7).
  # Orphan-safe: the asset is already persisted when this fires; if the target
  # component is gone, send_update logs a miss and nothing else happens.
  defp handle_asset_delivery_info({:asset_ready, target, asset}, socket) do
    # Gallery additions must land ONE PER RENDER CYCLE — parallel uploads
    # deliver in quick succession and LiveView batches the resulting
    # send_updates, making the block process multiple adds against the same
    # initial state (adds get lost; the old flow serialized via the
    # client-side next_file dance). Queue them with a small spacing instead.
    if target["kind"] in ["block_ref_gallery", "entry_field_gallery"] do
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

  defp deliver_asset(%{"kind" => "block_var", "component_id" => component_id} = target, asset, _socket)
       when is_binary(component_id) do
    asset_type = (target["asset_type"] == "image" && :image) || :file

    # Mirror the old var upload flow: track processing updates for the image
    # so the picker/pending flows keep working once the Oban worker finishes.
    if asset_type == :image do
      Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:image:#{asset.id}")
    end

    send_update(BrandoAdmin.Components.Form.Input.RenderVar,
      id: component_id,
      event: "upload_complete",
      asset_type: asset_type,
      asset: asset
    )
  end

  # Picture refs get their image_id only when processing completes (thumbs need
  # sizes) — register as pending; the [:image, :updated] hook forwards
  # `image_processed` to the block, which runs update_ref_data + propagate.
  defp deliver_asset(
         %{"kind" => "block_ref_picture", "component_id" => component_id},
         %Brando.Images.Image{} = image,
         _socket
       )
       when is_binary(component_id) do
    Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:image:#{image.id}")

    send(
      self(),
      {:register_pending_block_image, image.id, {BrandoAdmin.Components.Form.Input.Blocks.PictureBlock, component_id}}
    )

    maybe_forward_already_processed(image, BrandoAdmin.Components.Form.Input.Blocks.PictureBlock, component_id)
  end

  # Gallery refs add the image_id immediately (placeholder renders while
  # processing), then the pending registration swaps in the processed struct.
  defp deliver_asset(
         %{"kind" => "block_ref_gallery", "component_id" => component_id},
         %Brando.Images.Image{} = image,
         _socket
       )
       when is_binary(component_id) do
    Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:image:#{image.id}")

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
      Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:image:#{asset.id}")
    end

    # Inline-Oban / fast-queue race (same recovery block refs get via
    # maybe_forward_already_processed): processing may complete before this
    # delivery runs, and the broadcast fired before we subscribed — refetch so
    # the processed struct lands in the changeset, not the :unprocessed one.
    asset = refresh_processed_image(asset)

    path =
      (target["path"] || [])
      |> Enum.map(fn
        seg when is_integer(seg) -> seg
        seg when is_binary(seg) -> String.to_existing_atom(seg)
      end)

    send_update(BrandoAdmin.Components.Form,
      id: "#{singular}_form",
      event: "entry_field_upload_complete",
      asset_type: asset_type,
      field: String.to_existing_atom(field),
      path: path,
      asset: asset
    )
  end

  defp deliver_asset(
         %{"kind" => "entry_field_gallery", "field" => field},
         %Brando.Images.Image{} = image,
         socket
       )
       when is_binary(field) do
    singular = socket.assigns.schema.__naming__().singular

    Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:image:#{image.id}")

    send_update(BrandoAdmin.Components.Form,
      id: "#{singular}_form",
      event: "entry_field_upload_complete",
      asset_type: :gallery,
      field: String.to_existing_atom(field),
      asset: refresh_processed_image(image)
    )
  end

  defp deliver_asset(
         %{"kind" => "entry_field_gallery", "field" => field},
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
      asset: video
    )
  end

  defp deliver_asset(target, asset, _socket) do
    require Logger

    Logger.debug(
      "==> asset_ready: no deliverable target (#{inspect(target)}) — asset ##{asset.id} remains in the library"
    )
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
          singular = schema.__naming__().singular
          form_id = "#{singular}_form"

          # Look up which relations use this module
          relations = schema.__relations__()

          for rel <- relations,
              rel.type == :has_many,
              get_in(rel.opts, [:module]) == video_schema do
            transformer_id = "#{form_id}-transformer-#{rel.name}"

            send_update(BrandoAdmin.Components.Form.Transformer,
              id: transformer_id,
              event: "video_updated",
              video: video
            )
          end

          {:halt, socket}
        else
          {:cont, socket}
        end

      _ ->
        {:cont, socket}
    end
  end

  defp handle_hooks_video_info(_, socket), do: {:cont, socket}

  # Port exit hooks - catch normal exits from image processing ports (ImageMagick, etc.)
  defp handle_hooks_port_exits({:EXIT, _port, :normal}, socket), do: {:halt, socket}
  defp handle_hooks_port_exits(_, socket), do: {:cont, socket}

  # Video event hooks - handle generic video uploader events
  # These work with any upload strategy (Mux, Cloudflare, S3, Bunny, Vimeo, etc.)

  defp handle_hooks_video_event("files_selected", %{"files" => _files}, socket) do
    # Files selected, tell hook to start uploading
    {:halt, push_event(socket, "start_upload_queue", %{})}
  end

  # Generic event for getting upload URL - works with any strategy
  # The hook can be named MuxUploader, CloudflareUploader, S3Uploader, etc.
  # but they all send generic events with no provider name
  defp handle_hooks_video_event("get_video_upload_url", %{"filename" => filename}, socket) do
    schema = socket.assigns.schema
    singular = schema.__naming__().singular
    form_id = "#{singular}_form"

    # Delegate to Form component - it will push event back to JS when ready
    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :get_video_upload_url,
      filename: filename
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
        # TODO: there are updated dirty fields from other users.
        require Logger

        Logger.debug("""

        ==> dirty_fields

        #{inspect(fields, pretty: true)}
        #{inspect(user_id, pretty: true)}

        """)

        socket
      end

    {:halt, socket}
  end

  defp handle_hooks_dirty_fields_info(_, socket), do: {:cont, socket}

  defp handle_hooks_active_field_info({:active_field, field, user_id}, socket) do
    socket =
      if user_id == socket.assigns.current_user.id do
        Brando.presence().update_active_field(socket.assigns.uri.path, user_id, field)
        socket
      else
        push_event(socket, "b:set_active_field", %{user_id: user_id, field: field})
      end

    {:halt, socket}
  end

  defp handle_hooks_active_field_info(_, socket), do: {:cont, socket}

  defp handle_hooks_block_presence_info({:block_focus, %{uid: uid, user_id: user_id}}, socket) do
    socket =
      if user_id == socket.assigns.current_user.id do
        socket
      else
        push_event(socket, "b:set_active_block", %{uid: uid, user_id: user_id})
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

  # Block-level presence — fired by Brando.Block JS hook on any focusin
  defp handle_hooks_block_focused_event("block_focused", %{"uid" => uid}, socket) do
    entry_id = socket.assigns[:entry_id]
    current_user_id = socket.assigns.current_user.id
    old_uid = socket.assigns[:current_focused_block_uid]

    if entry_id do
      # If switching blocks, blur the old one — trigger data shipping
      if old_uid && old_uid != uid do
        send(self(), {:ship_block_data, old_uid, current_user_id})

        Phoenix.PubSub.broadcast(
          Brando.pubsub(),
          "brando:block_presence:#{entry_id}",
          {:block_blur, %{uid: old_uid, user_id: current_user_id}}
        )
      end

      # Focus new block
      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        "brando:block_presence:#{entry_id}",
        {:block_focus, %{uid: uid, user_id: current_user_id}}
      )
    end

    {:halt, assign(socket, :current_focused_block_uid, uid)}
  end

  # Fired by the Block JS hook when focus settles after a focusout. Blur alone
  # must ship — the focus-switch path above only fires when ANOTHER block is
  # focused, which left edits unshipped on plain blur and on ref-to-ref moves
  # inside one block. `still_inside` distinguishes moving between refs in the
  # same block (ship content, keep presence) from leaving the block entirely
  # (ship + presence blur).
  defp handle_hooks_block_focused_event("block_blurred", %{"uid" => uid} = params, socket) do
    entry_id = socket.assigns[:entry_id]
    current_user_id = socket.assigns.current_user.id
    still_inside = Map.get(params, "still_inside", false)

    if entry_id do
      send(self(), {:ship_block_data, uid, current_user_id})

      unless still_inside do
        Phoenix.PubSub.broadcast(
          Brando.pubsub(),
          "brando:block_presence:#{entry_id}",
          {:block_blur, %{uid: uid, user_id: current_user_id}}
        )
      end
    end

    socket =
      if !still_inside and socket.assigns[:current_focused_block_uid] == uid do
        assign(socket, :current_focused_block_uid, nil)
      else
        socket
      end

    {:halt, socket}
  end

  defp handle_hooks_block_focused_event(_, _, socket), do: {:cont, socket}

  # Force-ship the currently focused block (triggered before save)
  defp handle_hooks_block_sync_info(:force_ship_focused_block, socket) do
    current_uid = socket.assigns[:current_focused_block_uid]
    entry_id = socket.assigns[:entry_id]
    current_user_id = socket.assigns.current_user.id

    if current_uid && entry_id do
      send(self(), {:ship_block_data, current_uid, current_user_id})

      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        "brando:block_presence:#{entry_id}",
        {:block_blur, %{uid: current_uid, user_id: current_user_id}}
      )
    end

    {:halt, assign(socket, :current_focused_block_uid, nil)}
  end

  # Block sync — routes {:ship_block_data, ...} and structural PubSub messages to BlockFields
  defp handle_hooks_block_sync_info({:ship_block_data, uid, _user_id}, socket) do
    send_to_block_fields(socket, event: "fetch_block_for_shipping", uid: uid)
    {:halt, socket}
  end

  # Always forwarded — BlockField decides whether to apply or defer. A shipped
  # snapshot must never be silently dropped: when we're focused on the same
  # root, BlockField parks it as pending and applies it on our blur (dropping
  # it meant our next blur re-shipped stale state over the remote edit).
  defp handle_hooks_block_sync_info({:block_ops_shipped, %{user_id: user_id} = msg}, socket) do
    if user_id != socket.assigns.current_user.id do
      send_to_block_fields(socket,
        event: "apply_remote_block_ops",
        uid: msg.uid,
        snapshot: msg.snapshot,
        user_id: msg.user_id,
        focused_uid: socket.assigns[:current_focused_block_uid]
      )
    end

    {:halt, socket}
  end

  defp handle_hooks_block_sync_info({:block_added, %{user_id: user_id} = msg}, socket) do
    if user_id != socket.assigns.current_user.id do
      send_to_block_fields(socket,
        event: "remote_block_added",
        uid: msg.uid,
        module_id: msg.module_id,
        sequence: msg.sequence,
        user_id: msg.user_id
      )
    end

    {:halt, socket}
  end

  defp handle_hooks_block_sync_info({:block_deleted, %{user_id: user_id} = msg}, socket) do
    if user_id != socket.assigns.current_user.id do
      send_to_block_fields(socket, event: "remote_block_deleted", uid: msg.uid)
    end

    {:halt, socket}
  end

  # A late joiner asks connected editors for their unsaved state. Blocks
  # replay from the op store; unsaved ENTRY FIELD changes (title, slug, ...)
  # ship through the regular field-sync path — without this, a joiner only
  # sees fields as they were in the database.
  defp handle_hooks_block_sync_info({:blocks_sync_request, %{user_id: user_id} = msg}, socket) do
    if user_id != socket.assigns.current_user.id do
      send_to_block_fields(socket,
        event: "remote_sync_requested",
        origin_block_field: msg.block_field
      )

      if schema = socket.assigns[:schema] do
        singular = schema.__naming__().singular

        send_update(BrandoAdmin.Components.Form,
          id: "#{singular}_form",
          event: "ship_field_changes"
        )
      end
    end

    {:halt, socket}
  end

  defp handle_hooks_block_sync_info({:block_restored, %{user_id: user_id} = msg}, socket) do
    if user_id != socket.assigns.current_user.id do
      send_to_block_fields(socket,
        event: "remote_block_restored",
        snapshot: msg.snapshot,
        origin_block_field: msg.block_field
      )
    end

    {:halt, socket}
  end

  defp handle_hooks_block_sync_info({:blocks_reordered, %{user_id: user_id} = msg}, socket) do
    if user_id != socket.assigns.current_user.id do
      send_to_block_fields(socket, event: "remote_blocks_reordered", block_list: msg.block_list)
    end

    {:halt, socket}
  end

  # Field sync — ship field changeset diffs between users
  defp handle_hooks_block_sync_info({:fields_shipped, %{user_id: user_id} = msg}, socket) do
    if user_id != socket.assigns.current_user.id do
      schema = socket.assigns[:schema]

      if schema do
        singular = schema.__naming__().singular
        form_id = "#{singular}_form"

        send_update(BrandoAdmin.Components.Form,
          id: form_id,
          event: "apply_remote_field_changes",
          changes: msg.changes
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
      singular = schema.__naming__().singular
      form_id = "#{singular}_form"

      for %{name: field} <- schema.__blocks_fields__() do
        block_field_id = "#{form_id}-blocks-#{field}"

        send_update(
          BrandoAdmin.Components.Form.BlockField,
          [{:id, block_field_id} | opts]
        )
      end
    end
  end

  defp handle_hooks_tiptap_link_info({:tiptap_set_link, tiptap_id, link_data}, socket) do
    {:halt, push_event(socket, "b:tiptap:set_link:#{tiptap_id}", link_data)}
  end

  defp handle_hooks_tiptap_link_info(_, socket), do: {:cont, socket}

  defp handle_hooks_modules_info({_module, [:module, action]}, socket) when action in [:created, :updated] do
    schema = socket.assigns.schema

    for %{name: field} <- schema.__blocks_fields__() do
      target_id = "block-field-#{field}-module-picker"

      send_update(BrandoAdmin.Components.Form.BlockField.ModulePicker,
        id: target_id,
        event: :refresh_modules
      )
    end

    {:halt, socket}
  end

  defp handle_hooks_modules_info(_, socket), do: {:cont, socket}

  defp handle_hooks_mutation_listener_info({:register_mutation_listener, schema, target}, socket) do
    Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:mutations:#{inspect(schema)}")

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

  defp assign_title(%{assigns: %{schema: schema}} = socket) do
    translated_singular = Brando.Blueprint.get_singular(schema)
    entry_id = socket.assigns.entry_id || gettext("New")

    assign(
      socket,
      :page_title,
      "#{translated_singular} [\##{entry_id}]"
    )
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
