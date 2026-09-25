defmodule BrandoAdmin.Videos.VideoListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Videos.Video
  use Gettext, backend: Brando.Gettext

  alias Brando.Videos
  alias Brando.Videos.Video
  alias BrandoAdmin.Components.Assets.FileBrowser
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.VideoPlayer
  alias BrandoAdmin.Components.Workspace
  alias BrandoAdmin.Images.FolderBrowser
  alias BrandoAdmin.LiveView.AssetListHelpers

  @impl true
  def mount(_params, _session, socket) do
    {:ok, default_cfg} = Videos.get_config_for(%{config_target: "default"})
    upload_root = FolderBrowser.scope_for((default_cfg && default_cfg.upload_path) || "videos/default")

    socket =
      socket
      |> assign(:recent_folders, [])
      |> assign(:custom_folders, [])
      |> assign(:folders, [""])
      |> assign(:child_folders, [])
      |> assign(:current_folder, "")
      |> assign(:current_folder_abs, nil)
      |> assign(:upload_root, upload_root)
      |> assign(:breadcrumbs, [%{label: "Root", folder: ""}])
      |> assign(:new_folder, "")
      |> assign(:show_new_folder_form, false)
      |> assign(:visible_video_count, 0)
      |> assign(:clipboard_ids, [])
      |> assign(:playing, nil)
      |> assign(:missing_metadata_count, length(Videos.list_video_ids_missing_metadata()))
      |> assign(:root_folder_ids, [])
      |> assign_folder_state(nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    folder_filter = params["filter:folder_id"] || params["filter:path"]
    {:noreply, assign_folder_state(socket, folder_filter)}
  end

  @impl true
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
        AssetListHelpers.move_entries_to_folder(Video, ids, folder_id)
        AssetListHelpers.update_list_entries(socket.assigns.schema)

        send(self(), {:toast, gettext("Moved %{count} videos", count: length(ids))})

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
      send(self(), {:toast, gettext("Cut %{count} videos", count: length(ids))})

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

    AssetListHelpers.move_entries_to_folder(Video, ids, folder_id)
    AssetListHelpers.update_list_entries(socket.assigns.schema)

    send(
      self(),
      {:toast,
       gettext("Moved %{count} videos to %{folder}",
         count: length(ids),
         folder: folder_label_for_display(socket.assigns.current_folder_abs, socket.assigns.upload_root)
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

  def handle_event("rename_video", %{"video_id" => id, "title" => title}, socket) do
    title = String.trim(title)

    with {id, ""} <- Integer.parse(id),
         {:ok, video} <- Videos.get_video(%{matches: %{id: id}}),
         true <- title != (video.title || "") do
      case Videos.update_video(id, %{title: blank_to_nil(title)}, socket.assigns.current_user) do
        {:ok, _} ->
          {:noreply, socket}

        {:error, _} ->
          send(self(), {:toast, gettext("Could not rename the video")})
          {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("play_video", %{"id" => id}, socket) do
    case Videos.get_video(%{matches: %{id: id}, preload: [:file]}) do
      {:ok, video} -> {:noreply, assign(socket, :playing, video)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("close_video", _, socket), do: {:noreply, assign(socket, :playing, nil)}

  def handle_event("fetch_metadata", _, socket) do
    {:ok, count} = Videos.enqueue_metadata(Videos.list_video_ids_missing_metadata(), socket.assigns.current_user)

    send(self(), {:toast, ngettext("Looking up %{count} video", "Looking up %{count} videos", count)})
    {:noreply, assign(socket, :missing_metadata_count, 0)}
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(title), do: title

  @impl true
  def render(assigns) do
    ~H"""
    <div class="admin-workspace workspace-list media-workspace videos-workspace">
      <Workspace.header title={gettext("Videos")}>
        <button
          :if={@missing_metadata_count > 0}
          type="button"
          class="workspace-button"
          phx-click="fetch_metadata"
          title={gettext("Look up thumbnails, titles and durations at each video's source")}
        >
          {gettext("Fetch thumbnails and titles")}
          <span class="alt-text-missing">
            {ngettext("%{count} missing", "%{count} missing", @missing_metadata_count)}
          </span>
        </button>
      </Workspace.header>

      <Content.modal
        :if={@playing}
        id="video-player-modal"
        title={Brando.Videos.display_title(@playing) || gettext("Untitled")}
        icon="hero-film"
        show
        wide
        close={JS.push("close_video")}
      >
        <VideoPlayer.player video={@playing} />
      </Content.modal>

      <.live_component
        module={FileBrowser}
        id="assets-video-browser"
        mode={:inline}
        root_name={gettext("Videos")}
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
        main_id="assets-video-browser-main"
      >
        <:main_header>
          <div class="image-picker-main-header">
            <h3>{if @current_folder == "", do: gettext("Library root"), else: Path.basename(@current_folder)}</h3>
            <div class="image-picker-main-actions">
              <span>
                {ngettext("%{count} video", "%{count} videos", @visible_video_count, count: @visible_video_count)}
              </span>
              <span :if={@clipboard_ids != []} class="clipboard-status">
                {gettext("Cut queue")}: {length(@clipboard_ids)}
              </span>
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
          params={AssetListHelpers.list_params(@params, @root_folder_ids)}
          listing={:default}
          hidden_filters={[:folder_id]}
          empty_title={gettext("No videos in this view")}
          empty_description={gettext("Choose a folder or adjust your search.")}
          extra_selection_actions={[
            %{event: "assets_cut_selected", label: gettext("Cut selected")}
          ]}
        />
      </.live_component>
    </div>
    """
  end

  defp assign_folder_state(socket, folder_filter) do
    {:ok, videos} =
      Videos.list_videos(%{select: [:folder_id, :config_target, :remote_id, :type], order: "desc id"})

    folder_entries = folder_entries(videos)

    folders =
      FolderBrowser.folders_from_entries(folder_entries, socket.assigns.upload_root)
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

    root_folder_ids = FolderBrowser.root_folder_ids(socket.assigns.upload_root)
    child_folders = FolderBrowser.child_folders(folders, current_folder)
    breadcrumbs = FolderBrowser.breadcrumbs(current_folder)
    visible_videos = FolderBrowser.entries_in_folder(folder_entries, current_folder, socket.assigns.upload_root)

    recent_folders =
      if current_folder_abs do
        FolderBrowser.push_recent_folder(socket.assigns.recent_folders, current_folder_abs)
      else
        socket.assigns.recent_folders
      end

    socket
    |> assign(:root_folder_ids, root_folder_ids)
    |> assign(:folders, folders)
    |> assign(:child_folders, child_folders)
    |> assign(:current_folder, current_folder)
    |> assign(:current_folder_abs, current_folder_abs)
    |> assign(:breadcrumbs, breadcrumbs)
    |> assign(:recent_folders, recent_folders)
    |> assign(
      :visible_video_count,
      if(current_folder == "",
        do: Enum.count(videos, &(is_nil(&1.folder_id) or &1.folder_id in root_folder_ids)),
        else: length(visible_videos)
      )
    )
  end

  defp folder_label_for_display(folder, upload_root) do
    case FolderBrowser.relative_folder(folder, upload_root) do
      "" -> "Root"
      value -> value
    end
  end

  defp folder_entries(videos) do
    Enum.map(videos, fn video ->
      %{
        folder_id: video.folder_id,
        config_target: video.config_target,
        path: folder_entry_path(video)
      }
    end)
  end

  defp folder_entry_path(%{type: :upload, remote_id: remote_id}) when is_binary(remote_id), do: remote_id
  defp folder_entry_path(_video), do: nil
end
