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
       max_file_size: Uploads.max_file_size(),
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
            {item, socket} = put_intake_item(socket, name, size, asset_type, target, transport: :server)
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

            {%{index: index, ref: item.ref, transport: "direct", upload_url: upload_url}, socket}

          {:error, message} ->
            {%{index: index, error: message}, socket}
        end
      end)

    {:reply, %{decisions: decisions}, assign(socket, :open?, true)}
  end

  def handle_event("validate_queue", _params, socket) do
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

      %{transport: :direct, direct: direct} = item ->
        finalize_params =
          maybe_put_folder_id(
            %{
              key: direct.key,
              resolved_target: direct.resolved_target,
              title: item.filename,
              mime_type: direct.mime_type,
              filesize: item.size
            },
            item.target["folder_id"]
          )

        case Uploads.finalize_direct(item.asset_type, finalize_params, user) do
          {:ok, asset} ->
            deliver(item, asset)
            Process.send_after(self(), {:auto_dismiss_item, ref}, @auto_dismiss_ms)
            {:noreply, update_item(socket, ref, %{status: :done, progress: 100, asset_id: asset.id})}

          {:error, reason} ->
            Logger.error("==> UploadManager: finalize_direct failed: #{inspect(reason)}")
            {:noreply, update_item(socket, ref, %{status: :error, error: format_error(reason)})}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("direct_error", %{"ref" => ref} = params, socket) do
    message = Map.get(params, "message", "Upload failed")
    Logger.error("==> UploadManager: direct upload failed: #{message}")
    {:noreply, update_item(socket, ref, %{status: :error, error: message})}
  end

  ## External transports (Mux/Bunny provider hooks) — tracked in the drawer for
  ## visibility only; the provider hooks own the transfer and delivery.

  def handle_event("external_track", _params, %{assigns: %{current_user: nil}} = socket) do
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
      |> Enum.filter(fn {_ref, item} -> item.status in [:done, :error, :orphaned] end)
      |> Enum.map(&elem(&1, 0))

    {:noreply, Enum.reduce(finished, socket, &drop_item(&2, &1))}
  end

  # Catch-all: the sticky manager must never crash on a malformed event —
  # that would kill the queue for every in-flight upload.
  def handle_event(event, params, socket) do
    Logger.warning("==> UploadManager: unhandled event #{inspect(event)}: #{inspect(params)}")
    {:noreply, socket}
  end

  ## Progress — runs in the manager's own process; only the drawer re-renders.

  defp handle_progress(:queue, entry, socket) do
    case Map.get(socket.assigns.items, ref_from_entry(entry)) do
      nil ->
        # Untracked entry (shouldn't happen) — free the slot when finished.
        if entry.done? do
          {:noreply, cancel_upload(socket, :queue, entry.ref)}
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
    socket = push_event(socket, "b:uploads:released", %{ref: item.ref})

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
            update_item(socket, item.ref, %{status: :processing, progress: 100, asset_id: asset.id})
          else
            Process.send_after(self(), {:auto_dismiss_item, item.ref}, @auto_dismiss_ms)
            update_item(socket, item.ref, %{status: :done, progress: 100, asset_id: asset.id})
          end

        {:noreply, socket}
    end
  end

  # Delivery is best-effort and orphan-safe: the asset is already persisted;
  # broadcasting to a topic nobody subscribes to is a no-op.
  defp deliver(%{target: %{"deliver_topic" => topic} = target}, asset) when is_binary(topic) do
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
      <form phx-change="validate_queue" style="display: none">
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
                :if={item.status in [:error, :orphaned]}
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

  defp maybe_put_folder_id(meta, folder_id) when is_integer(folder_id), do: Map.put(meta, :folder_id, folder_id)

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
      status: :queued,
      progress: 0,
      error: nil,
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

  defp drop_item(socket, ref) do
    socket
    |> update(:items, &Map.delete(&1, ref))
    |> update(:order, &List.delete(&1, ref))
  end

  defp finished_count(items) do
    Enum.count(items, fn {_ref, item} -> item.status in [:done, :error, :orphaned] end)
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
