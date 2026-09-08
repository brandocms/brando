defmodule BrandoAdmin.Images.ImageListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Images.Image
  use Gettext, backend: Brando.Gettext

  import Ecto.Query

  alias Brando.Images
  alias Brando.Images.Image
  alias BrandoAdmin.Components.Assets.FileBrowser
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Workspace
  alias BrandoAdmin.Images.FolderBrowser
  alias BrandoAdmin.LiveView.AssetListHelpers

  @impl true
  def mount(_params, _session, socket) do
    deliver_topic = "form:" <> Ecto.UUID.generate()
    if connected?(socket), do: Phoenix.PubSub.subscribe(Brando.pubsub(), deliver_topic)

    socket =
      socket
      |> assign(:deliver_topic, deliver_topic)
      |> assign(:recent_folders, [])
      |> assign(:custom_folders, [])
      |> assign(:folders, [""])
      |> assign(:child_folders, [])
      |> assign(:current_folder, "")
      |> assign(:current_folder_abs, nil)
      |> assign(:upload_root, FolderBrowser.scope_for(nil))
      |> assign(:upload_folder, nil)
      |> assign(:breadcrumbs, [%{label: "Root", folder: ""}])
      |> assign(:new_folder, "")
      |> assign(:show_new_folder_form, false)
      |> assign(:visible_image_count, 0)
      |> assign(:current_folder_config_target, "default")
      |> assign(:clipboard_ids, [])
      |> assign_folder_state(nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    folder_filter = params["filter:folder_id"] || params["filter:path"]
    {:noreply, assign_folder_state(socket, folder_filter)}
  end

  @impl true
  def handle_event("focus", _, socket), do: {:noreply, socket}
  def handle_event("blur", _, socket), do: {:noreply, socket}

  def handle_event("validate", params, socket) do
    folder = get_in(params, ["upload", "folder"]) || socket.assigns.current_folder_abs
    {:noreply, assign(socket, :upload_folder, folder)}
  end

  def handle_event("assets_go_root", _, socket) do
    {:noreply, AssetListHelpers.patch_folder_filter(socket, nil)}
  end

  def handle_event("assets_go_folder", %{"folder" => folder}, socket) do
    folder_id = FolderBrowser.folder_id_for(folder, socket.assigns.upload_root)
    {:noreply, AssetListHelpers.patch_folder_filter(socket, folder_id)}
  end

  def handle_event("assets_go_parent", _, socket) do
    {:noreply, AssetListHelpers.go_parent(socket)}
  end

  def handle_event("assets_go_recent", %{"folder" => folder}, socket) do
    relative = FolderBrowser.relative_folder(folder, socket.assigns.upload_root)
    folder_id = FolderBrowser.folder_id_for(relative, socket.assigns.upload_root)
    {:noreply, AssetListHelpers.patch_folder_filter(socket, folder_id)}
  end

  def handle_event("assets_show_new_folder_form", _, socket) do
    {:noreply, assign(socket, :show_new_folder_form, true)}
  end

  def handle_event("assets_cancel_new_folder_form", _, socket) do
    {:noreply,
     socket
     |> assign(:new_folder, "")
     |> assign(:show_new_folder_form, false)}
  end

  def handle_event("assets_create_folder", %{"folder" => %{"name" => folder_name}}, socket) do
    {:noreply, AssetListHelpers.create_folder(socket, folder_name)}
  end

  def handle_event("assets_move_selected_to_folder", %{"folder" => folder, "ids" => ids}, socket) do
    ids = AssetListHelpers.parse_selected_ids(ids)
    absolute_folder = FolderBrowser.absolute_folder(folder, socket.assigns.upload_root)

    cond do
      ids == [] ->
        {:noreply, socket}

      not AssetListHelpers.folder_under_root?(absolute_folder, socket.assigns.upload_root) ->
        {:noreply, socket}

      true ->
        folder_id = FolderBrowser.folder_id_for(folder, socket.assigns.upload_root)
        AssetListHelpers.move_entries_to_folder(Image, ids, folder_id)
        AssetListHelpers.update_list_entries(socket.assigns.schema)

        send(self(), {:toast, gettext("Moved %{count} images", count: length(ids))})

        send_update(Content.List,
          id: AssetListHelpers.listing_id(socket.assigns.schema),
          action: :clear_selection
        )

        {:noreply, assign_folder_state(socket, socket.assigns.current_folder)}
    end
  end

  @impl true
  def handle_event("assets_cut_selected", %{"ids" => ids}, socket) do
    ids = AssetListHelpers.parse_selected_ids(ids)

    if ids == [] do
      {:noreply, socket}
    else
      send(self(), {:toast, gettext("Cut %{count} images", count: length(ids))})

      send_update(Content.List,
        id: AssetListHelpers.listing_id(socket.assigns.schema),
        action: :clear_selection
      )

      {:noreply, assign(socket, :clipboard_ids, ids)}
    end
  end

  @impl true
  def handle_event("assets_paste_selected", _, %{assigns: %{clipboard_ids: []}} = socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("assets_paste_selected", _, socket) do
    folder_id = FolderBrowser.folder_id_for(socket.assigns.current_folder, socket.assigns.upload_root)
    ids = socket.assigns.clipboard_ids

    AssetListHelpers.move_entries_to_folder(Image, ids, folder_id)
    AssetListHelpers.update_list_entries(socket.assigns.schema)

    send(
      self(),
      {:toast,
       gettext("Moved %{count} images to %{folder}",
         count: length(ids),
         folder: folder_label_for_display(socket.assigns.current_folder_abs)
       )}
    )

    {:noreply,
     socket
     |> assign(:clipboard_ids, [])
     |> assign_folder_state(socket.assigns.current_folder)}
  end

  @impl true
  def handle_event("assets_clear_clipboard", _, socket) do
    {:noreply, assign(socket, :clipboard_ids, [])}
  end

  @impl true
  def handle_info({:asset_ready, %{"kind" => "asset_library"}, image}, socket) do
    Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:image:#{image.id}")
    AssetListHelpers.update_list_entries(socket.assigns.schema)

    socket =
      if socket.assigns.current_folder == "" && image.folder_id do
        AssetListHelpers.patch_folder_filter(socket, image.folder_id)
      else
        assign_folder_state(socket, socket.assigns.current_folder)
      end

    {:noreply, socket}
  end

  def handle_info({%Image{} = image, [:image, :updated], _path}, socket) do
    if image.status == :processed, do: Phoenix.PubSub.unsubscribe(Brando.pubsub(), "brando:image:#{image.id}")
    AssetListHelpers.update_list_entries(socket.assigns.schema)
    {:noreply, assign_folder_state(socket, socket.assigns.current_folder)}
  end

  def handle_info({%Image{}, [:image, _event], _path}, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="admin-workspace media-workspace images-workspace workspace-list">
      <Workspace.header
        title={gettext("Images")}
        subtitle={gettext("Browse folders, upload images, and manage your library.")}
      />

      <.live_component
        module={FileBrowser}
        id="assets-image-browser"
        mode={:inline}
        root_name={gettext("Images")}
        folders_description={gettext("Browse this location")}
        upload_root={@upload_root}
        current_folder={@current_folder}
        breadcrumbs={@breadcrumbs}
        recent_folders={@recent_folders}
        child_folders={@child_folders}
        show_new_folder_form={@show_new_folder_form}
        new_folder={@new_folder}
        go_root_event="assets_go_root"
        go_folder_event="assets_go_folder"
        go_parent_event="assets_go_parent"
        go_recent_event="assets_go_recent"
        enable_folder_drop={true}
        folder_drop_event="assets_move_selected_to_folder"
        show_new_folder_event="assets_show_new_folder_form"
        cancel_new_folder_event="assets_cancel_new_folder_form"
        create_folder_event="assets_create_folder"
        main_id="assets-image-browser-main"
      >
        <:main_header>
          <div class="image-picker-main-header">
            <h3>{if @current_folder == "", do: gettext("Root folder"), else: Path.basename(@current_folder)}</h3>
            <div class="image-picker-main-actions">
              <span>
                {ngettext("%{count} image", "%{count} images", @visible_image_count, count: @visible_image_count)}
              </span>
              <span :if={@clipboard_ids != []} class="clipboard-status">
                {gettext("Cut queue")}: {length(@clipboard_ids)}
              </span>
              <div
                id="library-image-upload"
                phx-hook="Brando.UploadTrigger"
                data-kind="asset_library"
                data-component-id="assets-image-browser"
                data-asset-type="image"
                data-deliver-topic={@deliver_topic}
                data-config-target={@current_folder_config_target || "default"}
                data-folder={@effective_upload_folder}
                data-folder-id={@effective_upload_folder_id}
                data-click-mode="trigger"
                class="library-upload-trigger"
              >
                <button type="button" class="folder-action upload-trigger"><.icon name="hero-arrow-up-tray" />{if @current_folder ==
                                                                                                                    "",
                                                                                                                  do:
                                                                                                                    gettext(
                                                                                                                      "Upload to %{folder}",
                                                                                                                      folder:
                                                                                                                        @effective_upload_folder
                                                                                                                    ),
                                                                                                                  else:
                                                                                                                    gettext(
                                                                                                                      "Upload"
                                                                                                                    )}</button>
                <input type="file" class="file-input" multiple aria-label={gettext("Upload images")} />
              </div>
              <button
                :if={@clipboard_ids != []}
                type="button"
                class="folder-action"
                phx-click="assets_paste_selected"
              >
                {gettext("Paste")}
              </button>
              <button
                :if={@clipboard_ids != []}
                type="button"
                class="folder-action"
                phx-click="assets_clear_clipboard"
              >
                {gettext("Clear")}
              </button>
            </div>
          </div>
        </:main_header>

        <.live_component
          module={Content.List}
          id={"content_listing_#{@schema}_default"}
          schema={@schema}
          current_user={@current_user}
          uri={@uri}
          params={AssetListHelpers.list_params(@params)}
          listing={:default}
          hidden_filters={[:folder_id]}
          empty_title={gettext("No images in this view")}
          empty_description={gettext("Choose a folder, upload an image, or adjust your search.")}
          extra_selection_actions={[
            %{event: "assets_cut_selected", label: gettext("Cut selected")}
          ]}
        />
      </.live_component>
    </div>
    """
  end

  defp assign_folder_state(socket, folder_filter) do
    {:ok, images} =
      Images.list_images(%{select: [:id, :path, :folder_id, :config_target], order: "desc id"})

    images = ensure_image_folder_ids(images, socket.assigns.upload_root)

    folders =
      FolderBrowser.folders_from_entries(images, socket.assigns.upload_root)
      |> Kernel.++(socket.assigns.custom_folders)
      |> Enum.map(&(FolderBrowser.normalize_folder(&1) || ""))
      |> Enum.uniq()
      |> Enum.sort()

    current_folder = AssetListHelpers.resolve_current_folder(folder_filter, socket.assigns.upload_root)
    current_folder = if current_folder in folders, do: current_folder, else: ""

    current_folder_abs =
      if current_folder == "" do
        nil
      else
        FolderBrowser.absolute_folder(current_folder, socket.assigns.upload_root)
      end

    child_folders = FolderBrowser.child_folders(folders, current_folder)
    breadcrumbs = FolderBrowser.breadcrumbs(current_folder)
    visible_images = FolderBrowser.entries_in_folder(images, current_folder, socket.assigns.upload_root)

    current_folder_config_target =
      resolve_folder_config_target(images, visible_images, current_folder, current_folder_abs, socket.assigns.upload_root)

    {upload_cfg, _} = Brando.Uploads.resolve_image_config(current_folder_config_target)
    effective_upload_folder = current_folder_abs || upload_cfg.upload_path

    recent_folders =
      if current_folder_abs do
        FolderBrowser.push_recent_folder(socket.assigns.recent_folders, current_folder_abs)
      else
        socket.assigns.recent_folders
      end

    socket
    |> assign(:folders, folders)
    |> assign(:child_folders, child_folders)
    |> assign(:current_folder, current_folder)
    |> assign(:current_folder_abs, current_folder_abs)
    |> assign(:breadcrumbs, breadcrumbs)
    |> assign(:recent_folders, recent_folders)
    |> assign(:visible_image_count, length(visible_images))
    |> assign(:current_folder_config_target, current_folder_config_target)
    |> assign(:effective_upload_folder, effective_upload_folder)
    |> assign(
      :effective_upload_folder_id,
      FolderBrowser.folder_id_for(effective_upload_folder, socket.assigns.upload_root)
    )
  end

  defp folder_label_for_display(folder) do
    case FolderBrowser.relative_folder(folder, FolderBrowser.scope_for(nil)) do
      "" -> "Root"
      value -> value
    end
  end

  # NOTE:
  # Assets list uploads must honor field-specific image configs when users browse
  # into those folders. We infer the folder target from existing images in the
  # exact folder first, then fall back to longest matching upload_path prefix.
  defp resolve_folder_config_target(images, visible_images, current_folder, current_folder_abs, upload_root) do
    most_common_config_target(visible_images) ||
      resolve_config_target_from_folder_prefix(images, current_folder, current_folder_abs, upload_root) ||
      "default"
  end

  defp most_common_config_target(images) do
    images
    |> Enum.map(&normalize_config_target(&1.config_target))
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(%{}, fn config_target, acc ->
      Map.update(acc, config_target, 1, &(&1 + 1))
    end)
    |> case do
      counts when map_size(counts) == 0 ->
        nil

      counts ->
        counts
        |> Enum.max_by(fn {_config_target, count} -> count end)
        |> elem(0)
    end
  end

  defp resolve_config_target_from_folder_prefix(images, current_folder, current_folder_abs, upload_root) do
    folder_abs =
      FolderBrowser.normalize_folder(current_folder_abs) ||
        FolderBrowser.absolute_folder(current_folder, upload_root)

    root = FolderBrowser.normalize_folder(upload_root)

    cond do
      is_nil(folder_abs) or is_nil(root) ->
        nil

      folder_abs == root ->
        nil

      true ->
        images
        |> Enum.map(&normalize_config_target(&1.config_target))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.map(fn config_target ->
          {config_target, upload_path_for_config_target(config_target)}
        end)
        |> Enum.filter(fn {_config_target, upload_path} ->
          is_binary(upload_path) and
            (folder_abs == upload_path || String.starts_with?(folder_abs, upload_path <> "/"))
        end)
        |> Enum.sort_by(fn {_config_target, upload_path} -> String.length(upload_path) end, :desc)
        |> case do
          [{config_target, _upload_path} | _] -> config_target
          _ -> nil
        end
    end
  end

  defp upload_path_for_config_target(config_target) do
    case Images.get_config_for(%{config_target: config_target}) do
      {:ok, cfg} -> FolderBrowser.normalize_folder(cfg.upload_path)
      _ -> nil
    end
  end

  defp normalize_config_target(config_target) when is_binary(config_target) do
    normalized = String.trim(config_target)
    if normalized == "", do: nil, else: normalized
  end

  defp normalize_config_target(_), do: nil

  # Keeps folder browsing correct for legacy assets by assigning folder_id
  # from existing image paths the first time we encounter unassigned entries.
  defp ensure_image_folder_ids(images, upload_root) do
    updates = pending_image_folder_updates(images, upload_root)

    if updates == [] do
      images
    else
      timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      Enum.each(updates, fn {folder, ids} ->
        relative = FolderBrowser.relative_folder(folder, upload_root)

        if relative not in [nil, ""] do
          folder_id = FolderBrowser.folder_id_for(relative, upload_root)

          if folder_id do
            from(i in Image, where: i.id in ^ids and is_nil(i.folder_id))
            |> Brando.Repo.update_all(set: [folder_id: folder_id, updated_at: timestamp])
          end
        end
      end)

      {:ok, refreshed} =
        Images.list_images(%{select: [:id, :path, :folder_id, :config_target], order: "desc id"})

      refreshed
    end
  end

  defp pending_image_folder_updates(images, upload_root) do
    root = FolderBrowser.normalize_folder(upload_root)

    images
    |> Enum.reduce(%{}, fn image, acc ->
      cond do
        not is_nil(image.folder_id) ->
          acc

        not is_integer(Map.get(image, :id)) ->
          acc

        not is_binary(image.path) or image.path == "" ->
          acc

        true ->
          folder =
            image.path
            |> Path.dirname()
            |> FolderBrowser.absolute_folder(root)
            |> FolderBrowser.normalize_folder()

          cond do
            is_nil(folder) or is_nil(root) ->
              acc

            folder == root ->
              acc

            String.starts_with?(folder, root <> "/") ->
              id = Map.fetch!(image, :id)
              Map.update(acc, folder, [id], &[id | &1])

            true ->
              acc
          end
      end
    end)
    |> Enum.map(fn {folder, ids} -> {folder, Enum.uniq(ids)} end)
  end
end
