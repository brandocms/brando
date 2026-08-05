defmodule BrandoAdmin.UploadManager do
  @moduledoc """
  Sticky LiveView that owns every admin upload (see `docs/UPLOADER.md`).

  Runs in its own process next to `BrandoAdmin.Chrome`, so upload progress
  re-renders only this view's drawer — never the editor form. Sources hand
  files over through the `window.BrandoUploads.enqueue(files, target)` JS
  bridge (registered by the `Brando.UploadManager` hook); the manager
  validates each file at intake, uploads through its own `allow_upload`,
  stores the asset, and delivers it to the originating target with a
  best-effort PubSub broadcast (orphan-safe: the asset always ends up in
  the library even if the target UI is gone).

  Entry ↔ item matching: the JS bridge renames each file to
  `"<ref>::<original name>"`; we strip the prefix before storage.
  """

  use Phoenix.LiveView
  use Gettext, backend: Brando.Gettext

  require Logger

  alias Brando.Uploads
  alias Brando.Uploads.AssetIntent

  # Finished items clear themselves; errors stay until dismissed.
  @auto_dismiss_ms 4_000

  # e2e/acceptance runs use the Ecto SQL sandbox — the manager writes to the
  # DB at consume, so it must join the test's sandbox connection like every
  # other admin LiveView (see BrandoAdmin.live_view/0).
  if Application.compile_env(Brando.config(:otp_app), :sql_sandbox) do
    on_mount({BrandoAdmin.Mounts.LiveAcceptance, {:default, __MODULE__}})
  end

  on_mount({BrandoAdmin.UserAuth, :mount_current_user})

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:socket_connected, connected?(socket))
     |> assign(:items, %{})
     |> assign(:order, [])
     |> assign(:open?, true)
     |> allow_upload(:queue,
       accept: :any,
       max_entries: 20,
       # Intake has already applied the resolved target config's size_limit.
       # This larger value is the Phoenix transport backstop; using the 50 MB
       # fallback here rejected otherwise-valid 100 MB+ file/video configs.
       max_file_size: Uploads.manager_max_file_size(),
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  ## Intake — validate each file against its target before any bytes move.
  ## Replies with a decision per file; the JS bridge only starts uploads for
  ## accepted files (tagging them "<ref>::<name>").

  def handle_event("intake", _params, %{assigns: %{current_user: nil}} = socket) do
    {:reply, %{decisions: []}, socket}
  end

  def handle_event("intake", %{"files" => files, "target" => target}, socket) do
    case AssetIntent.normalize(target) do
      {:ok, target} -> accept_intake(files, target, socket)
      {:error, message} -> reject_intake(files, target, message, socket)
    end
  end

  # Entries that error without ever completing (validation backstop, transport
  # failure) never reach handle_progress — sweep them here or their transfer
  # slots stay wedged and the drawer row sticks at :uploading.
  def handle_event("validate_queue", _params, socket) do
    queue = socket.assigns.uploads.queue

    socket =
      Enum.reduce(queue.errors, socket, fn {entry_ref, reason}, socket ->
        # Config-level errors carry the upload config's ref, not an entry's —
        # nothing to cancel for those.
        case Enum.find(queue.entries, &(&1.ref == entry_ref)) do
          nil ->
            socket

          entry ->
            item_ref = ref_from_entry(entry)

            socket
            |> cancel_upload(:queue, entry.ref)
            |> push_released(item_ref)
            |> mark_item_error(item_ref, upload_error_label(reason))
        end
      end)

    {:noreply, socket}
  end

  ## Client-direct transport — the browser PUTs to the presigned URL and
  ## reports back here. finalize uses only server-side item state.

  def handle_event("direct_progress", %{"ref" => ref, "progress" => progress}, socket)
      when is_integer(progress) do
    {:noreply, update_item(socket, ref, %{status: :uploading, progress: min(progress, 100)})}
  end

  def handle_event("direct_complete", _params, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("direct_complete", %{"ref" => ref}, socket) do
    user = socket.assigns.current_user

    case Map.get(socket.assigns.items, ref) do
      # A replayed complete for an already-finalized ref must not create a
      # duplicate asset row.
      %{transport: :direct, status: :done} ->
        {:noreply, socket}

      %{transport: :direct} = item ->
        case finalize_item(item, user) do
          {:ok, asset} ->
            Uploads.delete_pending_intent(ref)
            Process.send_after(self(), {:auto_dismiss_item, ref}, @auto_dismiss_ms)

            {:noreply, update_item(socket, ref, %{status: :done, progress: 100, asset_id: asset.id})}

          {:error, reason} ->
            Logger.error("==> UploadManager: finalize_direct failed: #{inspect(reason)}")
            {:noreply, update_item(socket, ref, %{status: :error, error: format_error(reason)})}
        end

      # No item under this ref: this process was not the one that authorized the
      # upload. `mount/1` hard-assigns `items: %{}`, so a manager that remounted
      # mid-transfer (reconnect, or navigation that rebuilt the Chrome) has no
      # memory of it — while the bytes ARE already in the bucket. This used to
      # be a silent no-op, leaving an object with no asset row.
      #
      # The intent recorded at presign carries everything finalize needs, so
      # recover from it. There is no drawer row to update — that UI died with
      # the old process — but the asset lands in the library either way, which
      # is the same orphan-safe contract delivery already has.
      nil ->
        {:noreply, finalize_orphaned_complete(socket, ref, user)}

      item ->
        Logger.error(
          "==> UploadManager: direct_complete for ref #{inspect(ref)} with " <>
            "transport #{inspect(item.transport)}, expected :direct — ignoring."
        )

        {:noreply, socket}
    end
  end

  def handle_event("direct_error", %{"ref" => ref} = params, socket) do
    message = Map.get(params, "message", "Upload failed")
    Logger.error("==> UploadManager: direct upload failed: #{message}")

    # The transfer will not complete, so the intent has nothing left to recover.
    # Any partial object in the bucket is the reaper's to clean up — dropping
    # the intent here only stops a later forged `direct_complete` from
    # finalizing a half-written object.
    Uploads.delete_pending_intent(ref)

    {:noreply, update_item(socket, ref, %{status: :error, error: message})}
  end

  ## External transports (Mux/Bunny/Cloudflare provider hooks) — tracked in the drawer for
  ## visibility only; the provider hooks own the transfer and delivery.

  def handle_event("external_track", _params, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("external_track", %{"ref" => ref}, socket)
      when is_map_key(socket.assigns.items, ref) do
    # Never clobber an existing item (a tracked intake item holds the
    # delivery target — overwriting it would break that upload's delivery).
    {:noreply, socket}
  end

  def handle_event("external_track", %{"ref" => ref, "filename" => filename} = params, socket)
      when is_binary(ref) and byte_size(ref) <= 64 do
    item = %{
      ref: ref,
      filename: filename,
      size: Map.get(params, "size", 0),
      asset_type: :video,
      transport: :external,
      direct: nil,
      status: :uploading,
      progress: 0,
      error: nil,
      target: %{},
      asset_id: nil
    }

    socket =
      socket
      |> update(:items, &Map.put(&1, ref, item))
      |> update(:order, &(&1 ++ [ref]))
      |> assign(:open?, true)

    {:noreply, socket}
  end

  def handle_event("external_progress", %{"ref" => ref, "progress" => progress}, socket)
      when is_integer(progress) do
    {:noreply, update_item(socket, ref, %{status: :uploading, progress: min(progress, 100)})}
  end

  def handle_event("external_complete", %{"ref" => ref}, socket) do
    Process.send_after(self(), {:auto_dismiss_item, ref}, @auto_dismiss_ms)
    {:noreply, update_item(socket, ref, %{status: :done, progress: 100})}
  end

  def handle_event("external_error", %{"ref" => ref} = params, socket) do
    message = Map.get(params, "message", "Upload failed")
    {:noreply, update_item(socket, ref, %{status: :error, error: message})}
  end

  def handle_event("toggle", _params, socket) do
    {:noreply, update(socket, :open?, &(!&1))}
  end

  def handle_event("cancel_item", %{"ref" => ref}, socket) do
    socket =
      case Map.get(socket.assigns.items, ref) do
        %{transport: :direct} ->
          # A cancelled transfer must not stay finalizable — see direct_error.
          Uploads.delete_pending_intent(ref)
          # the hook aborts the in-flight XHR (and frees the transfer slot)
          push_event(socket, "b:uploads:cancel", %{ref: ref})

        _ ->
          socket =
            case find_entry(socket, ref) do
              nil -> socket
              entry -> cancel_upload(socket, :queue, entry.ref)
            end

          push_event(socket, "b:uploads:cancel", %{ref: ref})
      end

    {:noreply, drop_item(socket, ref)}
  end

  def handle_event("dismiss_item", %{"ref" => ref}, socket) do
    {:noreply, drop_item(socket, ref)}
  end

  def handle_event("dismiss_finished", _params, socket) do
    finished =
      socket.assigns.items
      |> Enum.filter(fn {_ref, item} -> item.status in [:done, :error] end)
      |> Enum.map(&elem(&1, 0))

    {:noreply, Enum.reduce(finished, socket, &drop_item(&2, &1))}
  end

  # Catch-all: the sticky manager must never crash on a malformed event —
  # that would kill the queue for every in-flight upload.
  def handle_event(event, params, socket) do
    Logger.warning("==> UploadManager: unhandled event #{inspect(event)}: #{inspect(params)}")
    {:noreply, socket}
  end

  defp accept_intake(files, target, socket) do
    asset_type = parse_asset_type(target["asset_type"])
    user = socket.assigns.current_user

    {decisions, socket} =
      Enum.map_reduce(files, socket, fn file, socket ->
        name = Map.get(file, "name", "")
        size = Map.get(file, "size", 0)
        mime_type = Map.get(file, "type", "")
        index = Map.get(file, "index", 0)

        file_meta = %{name: name, size: size, type: mime_type}

        case Uploads.initiate(asset_type, target["config_target"], file_meta, user) do
          {:ok, :server} ->
            {item, socket} =
              put_intake_item(socket, name, size, asset_type, target, transport: :server)

            {%{index: index, ref: item.ref, transport: "server"}, socket}

          {:ok, {:direct, %{upload_url: upload_url} = direct}} ->
            # key/resolved_target stay server-side on the item — finalize never
            # trusts client-provided keys.
            {item, socket} =
              put_intake_item(socket, name, size, asset_type, target,
                transport: :direct,
                direct: %{
                  key: direct.key,
                  resolved_target: direct.resolved_target,
                  mime_type: mime_type
                }
              )

            # ...and are also written down, because this process may not be here
            # when the browser reports back (see `Uploads.PendingIntent`).
            record_pending_intent(item, direct, mime_type, user)

            {%{
               index: index,
               ref: item.ref,
               transport: "direct",
               upload_url: upload_url,
               upload_headers: direct.upload_headers
             }, socket}

          {:error, message} ->
            # Keep a visible :error item — a silently dropped file looks like
            # a broken drop zone to the user.
            {item, socket} =
              put_intake_item(socket, name, size, asset_type, target,
                transport: :server,
                status: :error,
                error: message
              )

            {%{index: index, ref: item.ref, error: message}, socket}
        end
      end)

    {:reply, %{decisions: decisions}, assign(socket, :open?, true)}
  end

  defp reject_intake(files, target, message, socket) do
    asset_type_value =
      if is_map(target),
        do: Map.get(target, "asset_type", Map.get(target, :asset_type)),
        else: nil

    asset_type = parse_asset_type(asset_type_value)

    {decisions, socket} =
      Enum.map_reduce(files, socket, fn file, socket ->
        name = Map.get(file, "name", "")
        size = Map.get(file, "size", 0)
        index = Map.get(file, "index", 0)

        {item, socket} =
          put_intake_item(socket, name, size, asset_type, target,
            transport: :server,
            status: :error,
            error: message
          )

        {%{index: index, ref: item.ref, error: message}, socket}
      end)

    {:reply, %{decisions: decisions}, assign(socket, :open?, true)}
  end

  ## Progress — runs in the manager's own process; only the drawer re-renders.

  defp handle_progress(:queue, entry, socket) do
    case Map.get(socket.assigns.items, ref_from_entry(entry)) do
      nil ->
        # Untracked entry (shouldn't happen) — free both the LiveView slot
        # and the JS scheduler slot when finished.
        if entry.done? do
          socket =
            socket
            |> cancel_upload(:queue, entry.ref)
            |> push_released(ref_from_entry(entry))

          {:noreply, socket}
        else
          {:noreply, socket}
        end

      item ->
        if entry.done? do
          consume_and_deliver(socket, entry, item)
        else
          {:noreply, update_item(socket, item.ref, %{status: :uploading, progress: entry.progress})}
        end
    end
  end

  defp consume_and_deliver(socket, entry, item) do
    user = socket.assigns.current_user
    clean_entry = %{entry | client_name: strip_ref(entry.client_name)}

    {cfg, config_target} = resolve_config(item.asset_type, item.target["config_target"])
    cfg = maybe_override_upload_path(cfg, item.asset_type, item.target["folder"])

    result =
      consume_uploaded_entry(socket, entry, fn meta ->
        meta =
          meta
          |> Map.put(:config_target, config_target)
          |> maybe_put_folder_id(item.target["folder_id"])

        # Always {:ok, _} so the entry is consumed (and its temp file cleaned)
        # even on storage failure; store_upload normalizes every error shape.
        case Uploads.store_upload(meta, clean_entry, cfg, user) do
          {:ok, asset} -> {:ok, asset}
          {:error, message} -> {:ok, {:upload_error, message}}
        end
      end)

    # The transfer slot is free either way — let the JS scheduler start the
    # next queued file.
    socket = push_released(socket, item.ref)

    case result do
      {:upload_error, message} ->
        {:noreply, update_item(socket, item.ref, %{status: :error, error: message})}

      asset ->
        # Deliver BEFORE queueing processing — with Oban testing: :inline the
        # ImageProcessor runs synchronously right here, and the form must have
        # the :asset_ready message (to subscribe + register pending) first.
        deliver(item, asset)

        socket =
          if item.asset_type == :image do
            Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:image:#{asset.id}")

            Brando.Images.Processing.queue_processing(asset, user, image_field_path(item.target), silent: true)

            update_item(socket, item.ref, %{
              status: :processing,
              progress: 100,
              asset_id: asset.id
            })
          else
            # Parity with save_file: server-transport files on CDN-enabled
            # sites must still be pushed to the CDN (images push from the
            # processing worker; direct transport is already in the bucket).
            maybe_queue_cdn_upload(asset, user)
            Process.send_after(self(), {:auto_dismiss_item, item.ref}, @auto_dismiss_ms)
            update_item(socket, item.ref, %{status: :done, progress: 100, asset_id: asset.id})
          end

        {:noreply, socket}
    end
  end

  defp record_pending_intent(item, direct, mime_type, user) do
    attrs = %{
      ref: item.ref,
      key: direct.key,
      resolved_target: direct.resolved_target,
      asset_type: item.asset_type,
      mime_type: mime_type,
      filename: item.filename,
      filesize: item.size,
      target: item.target,
      creator_id: user && user.id
    }

    case Uploads.create_pending_intent(attrs) do
      {:ok, _intent} ->
        :ok

      {:error, changeset} ->
        # Non-fatal: the in-process item still finalizes normally. What is lost
        # is only the ability to recover this one upload across a remount, and
        # failing intake over it would be a worse trade.
        Logger.error("==> UploadManager: could not record pending intent: #{inspect(changeset.errors)}")

        :ok
    end
  end

  # One finalize for both paths, so a recovered completion cannot drift from an
  # in-process one. Everything it reads is server-side: the key and target come
  # from intake, never from the completion event.
  defp finalize_item(item, user) do
    finalize_params =
      maybe_put_folder_id(
        %{
          key: item.direct.key,
          resolved_target: item.direct.resolved_target,
          title: item.filename,
          mime_type: item.direct.mime_type,
          filesize: item.size
        },
        item.target["folder_id"]
      )

    with {:ok, asset} <- Uploads.finalize_direct(item.asset_type, finalize_params, user) do
      deliver(item, asset)
      {:ok, asset}
    end
  rescue
    # `Brando.CDN.get_s3_config/2` raises outright when a target's CDN config
    # has gone missing or malformed — and this runs in the STICKY manager, so
    # an exception here takes every other in-flight upload down with it. The
    # module's catch-all `handle_event/3` exists for exactly this reason; the
    # finalize path has to honour it too.
    exception ->
      Logger.error(
        "==> UploadManager: finalize raised for #{inspect(item.direct.key)}: " <>
          Exception.format(:error, exception, __STACKTRACE__)
      )

      {:error, Exception.message(exception)}
  end

  defp finalize_orphaned_complete(socket, ref, user) do
    case Uploads.get_pending_intent(ref) do
      nil ->
        # Either a forged/stale ref, or an intent the reaper already swept. Both
        # are safe to ignore: nothing was authorized under this ref that we still
        # believe in, and finalize would have nothing trustworthy to work from.
        Logger.warning("==> UploadManager: direct_complete for unknown ref #{inspect(ref)} — no pending intent")

        socket

      intent ->
        Logger.info(
          "==> UploadManager: recovering direct_complete for ref #{inspect(ref)} " <>
            "from its pending intent — the authorizing manager is gone"
        )

        case finalize_item(item_from_intent(intent), user) do
          {:ok, asset} ->
            Uploads.delete_pending_intent(intent)
            Logger.info("==> UploadManager: recovered upload as asset ##{asset.id}")

            socket

          {:error, reason} ->
            # Keep the intent: the object may still be there, and the reaper is
            # the one allowed to decide it is abandoned.
            Logger.error("==> UploadManager: recovering direct_complete failed: #{inspect(reason)}")

            socket
        end
    end
  end

  # The persisted intent rehydrated into the same shape `finalize_item/2` reads
  # off a live item.
  defp item_from_intent(intent) do
    %{
      ref: intent.ref,
      filename: intent.filename,
      size: intent.filesize,
      asset_type: intent.asset_type,
      transport: :direct,
      direct: %{
        key: intent.key,
        resolved_target: intent.resolved_target,
        mime_type: intent.mime_type
      },
      target: intent.target || %{}
    }
  end

  # Delivery is best-effort and orphan-safe: the asset is already persisted;
  # broadcasting to a topic nobody subscribes to is a no-op.
  #
  # Which is also the problem, and why this logs the topic. `deliver_topic` is
  # minted per form MOUNT (`form.ex`, `"form:" <> Ecto.UUID.generate()`), while
  # the item captured its copy at intake — so a form that remounted mid-upload
  # is listening on a different topic than the one this broadcasts to, and the
  # asset lands in the library while the field it was uploaded for never hears
  # about it. Nothing distinguished that from a successful delivery in the logs.
  # Pair this line with the one `form.ex` logs at mount: same topic means the
  # delivery could land, different means it could not. See D2.
  defp deliver(%{target: %{"deliver_topic" => topic} = target}, asset) when is_binary(topic) do
    Logger.info("==> UploadManager: delivering asset ##{asset.id} to #{topic}")
    Phoenix.PubSub.broadcast(Brando.pubsub(), topic, {:asset_ready, target, asset})
  end

  defp deliver(item, asset) do
    Logger.debug("==> UploadManager: no deliver_topic for item #{item.ref}; asset ##{asset.id} kept in library")

    :ok
  end

  ## Oban ImageProcessor broadcasts on "brando:image:<id>" — flip :processing → :done.

  def handle_info({%Brando.Images.Image{id: id}, [:image, :updated], _path}, socket) do
    socket =
      socket.assigns.items
      |> Enum.filter(fn {_ref, item} -> item.asset_id == id and item.status == :processing end)
      |> Enum.reduce(socket, fn {ref, _item}, socket ->
        Process.send_after(self(), {:auto_dismiss_item, ref}, @auto_dismiss_ms)
        update_item(socket, ref, %{status: :done})
      end)

    # Per-image subscriptions would otherwise accumulate for the whole admin
    # session — the manager is sticky and never dies on navigation.
    Phoenix.PubSub.unsubscribe(Brando.pubsub(), "brando:image:#{id}")

    {:noreply, socket}
  end

  # ImageProcessor broadcasts [:image, :error] when its final attempt fails —
  # without it the drawer item pins at :processing forever.
  def handle_info({%Brando.Images.Image{id: id}, [:image, :error], _path}, socket) do
    socket =
      socket.assigns.items
      |> Enum.filter(fn {_ref, item} -> item.asset_id == id and item.status == :processing end)
      |> Enum.reduce(socket, fn {ref, _item}, socket ->
        update_item(socket, ref, %{status: :error, error: gettext("Image processing failed")})
      end)

    Phoenix.PubSub.unsubscribe(Brando.pubsub(), "brando:image:#{id}")

    {:noreply, socket}
  end

  def handle_info({:auto_dismiss_item, ref}, socket) do
    case Map.get(socket.assigns.items, ref) do
      %{status: :done} -> {:noreply, drop_item(socket, ref)}
      _ -> {:noreply, socket}
    end
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  ## Render — the drawer plus the hidden live_file_input the JS upload API needs.

  def render(assigns) do
    ~H"""
    <div
      :if={@socket_connected && @current_user}
      id="brando-upload-manager"
      phx-hook="Brando.UploadManager"
      data-max-concurrent-transfers={Uploads.max_concurrent_transfers()}
    >
      <form phx-change="validate_queue" class="upload-manager-queue-form">
        <.live_file_input upload={@uploads.queue} />
      </form>

      <div :if={@order != []} class={["upload-manager-drawer", (@open? && "open") || "closed"]}>
        <header phx-click="toggle">
          <span class="title">{gettext("Uploads")}</span>
          <span class="count">{finished_count(@items)}/{map_size(@items)}</span>
        </header>
        <ul :if={@open?}>
          <li :for={ref <- @order} :if={item = @items[ref]} class={"upload-item status-#{item.status}"}>
            <div class="meta">
              <span class="filename" title={target_label(item.target)}>{item.filename}</span>
              <span :if={item.status == :processing} class="processing-label">{gettext("Processing…")}</span>
              <span :if={item.status == :done} class="done-label"><span class="hero-check-mini"></span></span>
              <button
                :if={item.status in [:queued, :uploading] and item.transport != :external}
                type="button"
                class="icon-button"
                phx-click="cancel_item"
                phx-value-ref={ref}
                title={gettext("Cancel")}
              >
                <span class="hero-x-mark-mini"></span>
              </button>
              <button
                :if={item.status in [:error, :processing]}
                type="button"
                class="icon-button"
                phx-click="dismiss_item"
                phx-value-ref={ref}
                title={gettext("Dismiss")}
              >
                <span class="hero-x-mark-mini"></span>
              </button>
            </div>
            <progress :if={item.status in [:queued, :uploading]} value={item.progress} max="100">
              {item.progress}%
            </progress>
            <div :if={item.status == :error} class="error-label" title={item.error}>{item.error}</div>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  ## Helpers

  defp parse_asset_type("image"), do: :image
  defp parse_asset_type("file"), do: :file
  defp parse_asset_type("video"), do: :video
  defp parse_asset_type(_), do: :unknown

  # Folder browser support — the trigger carries the confirmed folder in the
  # target; images store under that folder (mirrors the old form-side
  # upload_folder_targets handling).
  defp maybe_override_upload_path(cfg, :image, folder) when is_binary(folder) and folder != "" do
    case BrandoAdmin.Images.FolderBrowser.absolute_folder(folder, cfg.upload_path) do
      nil -> cfg
      resolved -> %{cfg | upload_path: resolved}
    end
  end

  defp maybe_override_upload_path(cfg, _asset_type, _folder), do: cfg

  defp maybe_put_folder_id(meta, folder_id) when is_integer(folder_id),
    do: Map.put(meta, :folder_id, folder_id)

  defp maybe_put_folder_id(meta, folder_id) when is_binary(folder_id) do
    case Integer.parse(folder_id) do
      {id, ""} -> Map.put(meta, :folder_id, id)
      _ -> meta
    end
  end

  defp maybe_put_folder_id(meta, _), do: meta

  # Entry-field images must carry their (possibly nested) field path into the
  # Oban job — the [:image, :updated] broadcast routes by it, and an empty
  # path never reaches nested (subform) fields. The worker converts string
  # segments back through existing atoms only.
  defp image_field_path(%{"kind" => "entry_field", "path" => path}) when is_list(path), do: path
  defp image_field_path(_target), do: []

  defp resolve_config(:image, config_target), do: Uploads.resolve_image_config(config_target)
  defp resolve_config(:file, config_target), do: Uploads.resolve_file_config(config_target)
  defp resolve_config(:video, config_target), do: Uploads.resolve_video_config(config_target)

  defp ref_from_entry(entry) do
    case String.split(entry.client_name, "::", parts: 2) do
      [ref, _name] -> ref
      _ -> nil
    end
  end

  defp strip_ref(client_name) do
    case String.split(client_name, "::", parts: 2) do
      [_ref, name] -> name
      _ -> client_name
    end
  end

  defp find_entry(socket, ref) do
    Enum.find(socket.assigns.uploads.queue.entries, &(ref_from_entry(&1) == ref))
  end

  defp put_intake_item(socket, filename, size, asset_type, target, opts) do
    ref = Ecto.UUID.generate()

    item = %{
      ref: ref,
      filename: filename,
      size: size,
      asset_type: asset_type,
      transport: Keyword.fetch!(opts, :transport),
      direct: Keyword.get(opts, :direct),
      status: Keyword.get(opts, :status, :queued),
      progress: 0,
      error: Keyword.get(opts, :error),
      target: target,
      asset_id: nil
    }

    socket =
      socket
      |> update(:items, &Map.put(&1, ref, item))
      |> update(:order, &(&1 ++ [ref]))

    {item, socket}
  end

  defp update_item(socket, ref, attrs) do
    update(socket, :items, fn items ->
      case Map.get(items, ref) do
        nil -> items
        item -> Map.put(items, ref, Map.merge(item, attrs))
      end
    end)
  end

  defp maybe_queue_cdn_upload(%Brando.Files.File{cdn: cdn} = file, user) when cdn != true do
    if Brando.CDN.enabled?(Brando.Files) do
      Brando.CDN.queue_upload(file, user, [])
    end
  end

  defp maybe_queue_cdn_upload(_asset, _user), do: :ok

  defp mark_item_error(socket, nil, _message), do: socket

  defp mark_item_error(socket, ref, message),
    do: update_item(socket, ref, %{status: :error, error: message})

  # Frees the JS scheduler's transfer slot (b:uploads:released is its only
  # release signal for server-transport files).
  defp push_released(socket, nil), do: socket
  defp push_released(socket, ref), do: push_event(socket, "b:uploads:released", %{ref: ref})

  defp upload_error_label(reason) when reason in [:too_large, :too_many_files, :not_accepted],
    do: Brando.Upload.error_to_string(reason)

  defp upload_error_label(reason), do: inspect(reason)

  defp drop_item(socket, ref) do
    socket
    |> update(:items, &Map.delete(&1, ref))
    |> update(:order, &List.delete(&1, ref))
  end

  defp finished_count(items) do
    Enum.count(items, fn {_ref, item} -> item.status in [:done, :error] end)
  end

  defp target_label(%{"var_key" => var_key}) when is_binary(var_key), do: var_key
  defp target_label(_), do: nil

  # Used by the direct-transport finalize path; server-transport errors are
  # normalized to user-safe messages by `Brando.Uploads.store_upload/4`.
  defp format_error(message) when is_binary(message), do: message

  defp format_error(%Ecto.Changeset{} = changeset) do
    Logger.error("==> UploadManager: changeset errors: #{inspect(changeset.errors, pretty: true)}")

    gettext("Could not store uploaded file")
  end

  defp format_error(reason), do: inspect(reason)
end
