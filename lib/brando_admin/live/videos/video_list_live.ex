defmodule BrandoAdmin.Videos.VideoListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Videos.Video
  use Gettext, backend: Brando.Gettext

  import Ecto.Query

  alias BrandoAdmin.Components.Assets.FileBrowser
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Images.FolderBrowser
  alias Brando.Videos
  alias Brando.Videos.Video

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
    {:noreply, patch_folder_filter(socket, nil)}
  end

  def handle_event("assets_go_folder", %{"folder" => folder}, socket) do
    folder_id = FolderBrowser.folder_id_for(folder, socket.assigns.upload_root)
    {:noreply, patch_folder_filter(socket, folder_id)}
  end

  def handle_event("assets_go_parent", _, %{assigns: %{current_folder: ""}} = socket) do
    {:noreply, socket}
  end

  def handle_event("assets_go_parent", _, socket) do
    parent =
      socket.assigns.current_folder
      |> String.split("/", trim: true)
      |> Enum.drop(-1)
      |> Enum.join("/")

    folder_id = FolderBrowser.folder_id_for(parent, socket.assigns.upload_root)
    {:noreply, patch_folder_filter(socket, folder_id)}
  end

  def handle_event("assets_go_recent", %{"folder" => folder}, socket) do
    relative = FolderBrowser.relative_folder(folder, socket.assigns.upload_root)
    folder_id = FolderBrowser.folder_id_for(relative, socket.assigns.upload_root)
    {:noreply, patch_folder_filter(socket, folder_id)}
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
    cleaned = FolderBrowser.normalize_folder(folder_name)

    if cleaned do
      absolute =
        if socket.assigns.current_folder in ["", nil] do
          cleaned
        else
          Path.join(socket.assigns.current_folder, cleaned)
        end
        |> FolderBrowser.normalize_folder()

      case FolderBrowser.create_folder(absolute, socket.assigns.upload_root) do
        {:ok, _folder} ->
          folder_id = FolderBrowser.folder_id_for(absolute, socket.assigns.upload_root)

          {:noreply,
           socket
           |> assign(:custom_folders, Enum.uniq([absolute | socket.assigns.custom_folders]))
           |> assign(:show_new_folder_form, false)
           |> assign(:new_folder, "")
           |> patch_folder_filter(folder_id)}

        {:error, _reason} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("assets_move_selected_to_folder", %{"folder" => folder, "ids" => ids}, socket) do
    ids = parse_selected_ids(ids)
    absolute_folder = FolderBrowser.absolute_folder(folder, socket.assigns.upload_root)

    cond do
      ids == [] ->
        {:noreply, socket}

      not folder_under_root?(absolute_folder, socket.assigns.upload_root) ->
        {:noreply, socket}

      true ->
        folder_id = FolderBrowser.folder_id_for(folder, socket.assigns.upload_root)
        move_entries_to_folder(Video, ids, folder_id)
        update_list_entries(socket.assigns.schema)

        send(self(), {:toast, gettext("Moved %{count} videos", count: length(ids))})

        send_update(Content.List,
          id: listing_id(socket.assigns.schema),
          action: :clear_selection
        )

        {:noreply, assign_folder_state(socket, socket.assigns.current_folder)}
    end
  end

  @impl true
  def handle_event("assets_cut_selected", %{"ids" => ids}, socket) do
    ids = parse_selected_ids(ids)

    if ids == [] do
      {:noreply, socket}
    else
      send(self(), {:toast, gettext("Cut %{count} videos", count: length(ids))})

      send_update(Content.List,
        id: listing_id(socket.assigns.schema),
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

    move_entries_to_folder(Video, ids, folder_id)
    update_list_entries(socket.assigns.schema)

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

  defp update_list_entries(schema) do
    topic = "brando:listing:content_listing_#{schema}_default"
    Phoenix.PubSub.broadcast(Brando.pubsub(), topic, {schema, [:entries, :updated], []})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Assets — Videos")} subtitle={gettext("Overview")} />

    <.live_component
      module={FileBrowser}
      id="assets-video-browser"
      mode={:inline}
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
          <h3>{folder_label_for_display(@current_folder_abs, @upload_root)}</h3>
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
        params={list_params(@params)}
        listing={:default}
        extra_selection_actions={[
          %{event: "assets_cut_selected", label: gettext("Cut selected")}
        ]}
      />
    </.live_component>
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

    current_folder = resolve_current_folder(folder_filter, socket.assigns.upload_root)
    current_folder = if current_folder in folders, do: current_folder, else: ""

    current_folder_abs =
      if current_folder == "" do
        nil
      else
        FolderBrowser.absolute_folder(current_folder, socket.assigns.upload_root)
      end

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
    |> assign(:folders, folders)
    |> assign(:child_folders, child_folders)
    |> assign(:current_folder, current_folder)
    |> assign(:current_folder_abs, current_folder_abs)
    |> assign(:breadcrumbs, breadcrumbs)
    |> assign(:recent_folders, recent_folders)
    |> assign(:visible_video_count, length(visible_videos))
  end

  defp patch_folder_filter(socket, folder) do
    uri = socket.assigns.uri
    current_params = URI.decode_query(uri.query || "")
    folder_filter = if is_nil(folder), do: "root", else: to_string(folder)

    new_params =
      current_params
      |> Map.drop(["filter:path", "page"])
      |> Map.put("filter:folder_id", folder_filter)
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
      |> URI.encode_query()

    to =
      if new_params == "" do
        uri.path
      else
        uri.path <> "?" <> new_params
      end

    push_patch(socket, to: to)
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

  defp resolve_current_folder(folder_filter, upload_root) do
    cond do
      is_nil(folder_filter) or folder_filter in ["", "root"] ->
        ""

      is_integer(folder_filter) ->
        FolderBrowser.folder_path_for_id(folder_filter, upload_root)

      is_binary(folder_filter) ->
        case Integer.parse(folder_filter) do
          {folder_id, ""} ->
            FolderBrowser.folder_path_for_id(folder_id, upload_root)

          _ ->
            FolderBrowser.relative_folder(folder_filter, upload_root) || ""
        end

      true ->
        ""
    end
  end

  defp parse_selected_ids(ids) when is_list(ids) do
    ids
    |> Enum.map(&parse_int/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp parse_selected_ids(ids) when is_binary(ids) do
    case Jason.decode(ids) do
      {:ok, parsed} -> parse_selected_ids(parsed)
      _ -> []
    end
  end

  defp parse_selected_ids(_), do: []

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp folder_under_root?(folder, upload_root) do
    normalized_folder = FolderBrowser.normalize_folder(folder)
    normalized_root = FolderBrowser.normalize_folder(upload_root)

    normalized_folder == normalized_root ||
      String.starts_with?(normalized_folder || "", (normalized_root || "") <> "/")
  end

  defp move_entries_to_folder(schema_module, ids, folder_id) when is_list(ids) do
    timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    from(entry in schema_module, where: entry.id in ^ids)
    |> Brando.Repo.update_all(set: [folder_id: folder_id, updated_at: timestamp])
  end

  defp listing_id(schema), do: "content_listing_#{schema}_default"

  defp list_params(params) when is_map(params) do
    Map.put_new(params, "filter:folder_id", "root")
  end
end
