defmodule BrandoAdmin.Videos.VideoListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Videos.Video
  use Gettext, backend: Brando.Gettext

  on_mount BrandoAdmin.Work

  alias Brando.Media.Folder
  alias Brando.Videos
  alias Brando.Videos.Video
  alias Brando.Worker.VideoMetadataSweep
  alias BrandoAdmin.Components.Assets.FileBrowser
  alias BrandoAdmin.Components.Assets.MediaField
  alias BrandoAdmin.Components.Assets.ProviderLibraryPanel
  alias BrandoAdmin.Components.Assets.ProviderVideoUpload
  alias BrandoAdmin.Components.Assets.SortByUse
  alias BrandoAdmin.Components.Assets.VideoFromURL
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.VideoPlayer
  alias BrandoAdmin.Components.Work, as: WorkComponent
  alias BrandoAdmin.Components.Workspace
  alias BrandoAdmin.Images.FolderBrowser
  alias BrandoAdmin.LiveView.AssetListHelpers
  alias BrandoAdmin.Work

  @impl true
  def mount(_params, _session, socket) do
    {:ok, default_cfg} = Videos.get_config_for(%{config_target: "default"})
    upload_root = FolderBrowser.scope_for((default_cfg && default_cfg.upload_path) || "videos/default")

    # Uploads go through the upload manager, which delivers here
    deliver_topic = "form:" <> Ecto.UUID.generate()
    if connected?(socket), do: Phoenix.PubSub.subscribe(Brando.pubsub(), deliver_topic)

    # The library uploads with the default config, as the root is its folder
    {upload_cfg, _target} = Brando.Uploads.resolve_video_config("default")

    socket =
      socket
      |> assign(:deliver_topic, deliver_topic)
      |> assign(:upload_strategy, upload_cfg.upload_strategy)
      |> assign(:video_upload_available?, Brando.Uploads.video_upload_available?(upload_cfg))
      # "Add from URL" and "Add from <provider>" link an external video, so
      # they follow the default config's `allow_external_urls`, as a field's
      # picker follows its field's.
      |> assign(:allow_external_urls?, upload_cfg.allow_external_urls)
      |> assign(
        :library_providers,
        ProviderLibraryPanel.providers(socket.assigns.current_user, upload_cfg.allow_external_urls)
      )
      # The open "Add from URL" dialog: its opening, or nil
      |> assign(:url_add, nil)
      |> assign(:library, nil)
      |> VideoFromURL.assign_defaults()
      |> assign(:current_folder_id, nil)
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
      |> assign(:all_folders?, false)
      |> assign(:clipboard_ids, [])
      |> assign(:playing, nil)
      |> assign(:missing_metadata_count, length(Videos.list_video_ids_missing_metadata()))
      |> assign(:root_folder_ids, [])
      |> assign(:sweep, nil)
      |> assign(:sweep_result, nil)
      |> assign(:unused_count, 0)
      |> assign(:unused_ids, [])
      |> assign(:deleting_unused?, false)
      |> assign_folder_state(nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    folder_filter = params["filter:folder_id"] || params["filter:path"]

    {:noreply,
     socket
     |> assign_folder_state(folder_filter)
     |> AssetListHelpers.assign_unused_count(params, &Videos.list_videos/1)
     |> AssetListHelpers.assign_all_folders(params, &Videos.list_videos/1, :visible_video_count)}
  end

  @impl true
  def handle_event("assets_go_root", _, socket) do
    {:noreply, AssetListHelpers.patch_folder_filter(socket, nil)}
  end

  def handle_event("assets_go_folder", %{"folder" => folder}, socket) do
    {:noreply, AssetListHelpers.open_folder(socket, folder)}
  end

  def handle_event("assets_go_parent", _, socket) do
    {:noreply, AssetListHelpers.go_parent(socket)}
  end

  def handle_event("assets_go_recent", %{"folder" => folder}, socket) do
    relative = FolderBrowser.relative_folder(folder, socket.assigns.upload_root)
    {:noreply, AssetListHelpers.open_folder(socket, relative)}
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

      AssetListHelpers.move_entries_to_folder(socket, Video, ids, folder) != :ok ->
        {:noreply, socket}

      true ->
        AssetListHelpers.update_list_entries(socket.assigns.schema)

        send(self(), {:toast, gettext("Moved %{count} videos", count: length(ids))})

        send_update(Content.List,
          id: AssetListHelpers.listing_id(socket.assigns.schema),
          action: :clear_selection
        )

        {:noreply, refresh(socket)}
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
    ids = socket.assigns.clipboard_ids

    if AssetListHelpers.move_entries_to_folder(socket, Video, ids, socket.assigns.current_folder) == :ok do
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
       |> refresh()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("assets_clear_clipboard", _, socket) do
    {:noreply, assign(socket, :clipboard_ids, [])}
  end

  # Sort the videos loose in this folder into folders for the entries that
  # use them (see `BrandoAdmin.Media.Sweep`): a preview first, then the move.
  def handle_event("sweep_open", _, socket), do: {:noreply, AssetListHelpers.open_sweep(socket, :video)}
  def handle_event("sweep_close", _, socket), do: {:noreply, assign(socket, :sweep, nil)}

  def handle_event("sweep_apply", params, socket) do
    socket = AssetListHelpers.apply_sweep(socket, params)
    {:noreply, refresh(socket)}
  end

  def handle_event("sweep_undo", _, socket) do
    socket = AssetListHelpers.undo_sweep(socket)
    {:noreply, refresh(socket)}
  end

  def handle_event("sweep_dismiss", _, socket), do: {:noreply, assign(socket, :sweep_result, nil)}

  # A provider (Mux, Bunny, Cloudflare, Vimeo) takes the file from the
  # browser itself: its hook asks for a destination, then reports the file
  # sent. The upload drawer shows the progress. The video goes into the
  # folder the file was picked in, which the hook sends as `opening` (the
  # element's `data-ref` when the file was queued).
  def handle_event("get_video_upload_url", params, socket) do
    folder_id = library_folder_id(params["opening"], socket.assigns.upload_root)

    {:noreply, ProviderVideoUpload.initiate(socket, socket.assigns.current_user, "default", params, folder_id: folder_id)}
  end

  # Only a completion with the token signed for this user's request counts
  # (`ProviderVideoUpload.complete/3`).
  def handle_event("video_upload_complete", params, socket) do
    case ProviderVideoUpload.complete(ProviderVideoUpload.actor(socket), params) do
      {:ok, _video} ->
        AssetListHelpers.update_list_entries(socket.assigns.schema)
        {:noreply, refresh(socket)}

      {:error, reason} ->
        send(self(), {:toast, Brando.Uploads.video_upload_error_message(reason)})
        {:noreply, socket}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("video_upload_progress", _params, socket), do: {:noreply, socket}
  def handle_event("upload_error", _params, socket), do: {:noreply, socket}

  # "Add from URL": the address is read in the browser, its title looked up
  # at the provider (`VideoFromURL`), and the video goes into the folder in
  # view when the paste was made, as an upload does.
  # Each opening has an input of its own: the hook reads a file's size in the
  # browser before it pushes, and a push from a dialog closed meanwhile then
  # finds no element to go to.
  def handle_event("open_url_add", _, %{assigns: %{allow_external_urls?: true}} = socket) do
    {:noreply, socket |> assign(:library, nil) |> assign(:url_add, System.unique_integer([:positive]))}
  end

  def handle_event("open_url_add", _, socket), do: {:noreply, socket}

  # Closing drops a lookup still running: the editor changed their mind.
  def handle_event("close_url_add", _, socket) do
    {:noreply, socket |> assign(:url_add, nil) |> VideoFromURL.cancel()}
  end

  def handle_event("url", params, %{assigns: %{url_add: opening}} = socket) when is_integer(opening) do
    {:noreply, VideoFromURL.start(socket, params, %{config_target: "default", folder_id: add_folder_id(socket)})}
  end

  def handle_event("url", _params, socket), do: {:noreply, socket}

  # "Add from <provider>": the provider's own library, whose videos go into
  # the folder in view. One Brando holds already stays where it is.
  def handle_event("open_library", %{"strategy" => strategy}, socket) do
    case ProviderLibraryPanel.open(socket, strategy) do
      {:ok, socket} -> {:noreply, socket |> assign(:url_add, nil) |> VideoFromURL.cancel()}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("close_library", _, socket), do: {:noreply, assign(socket, :library, nil)}

  def handle_event("search_library", %{"query" => query}, socket) do
    {:noreply, ProviderLibraryPanel.search(socket, query)}
  end

  def handle_event("more_library", _, socket), do: {:noreply, ProviderLibraryPanel.more(socket)}

  def handle_event("add_from_library", %{"remote-id" => remote_id}, socket) do
    opts = [config_target: "default", folder_id: add_folder_id(socket)]

    case ProviderLibraryPanel.add(socket, remote_id, socket.assigns.current_user, opts) do
      {:ok, _video, socket} ->
        AssetListHelpers.update_list_entries(socket.assigns.schema)
        {:noreply, refresh(socket)}

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  # With the "Not in use" filter on: delete every unused video in view, this
  # folder's or, at the root, the whole library's, as the listing's Delete does.
  def handle_event("delete_unused", _, socket) do
    {:noreply, AssetListHelpers.delete_unused(socket, :video, &Videos.list_videos/1)}
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

  # Every video missing details gets a job of its own, one insert each: a
  # job queues them (`Brando.Worker.VideoMetadataSweep`), so a library of
  # thousands leaves the list responsive, and leaving it does not cut that
  # short.
  #
  # The sweep and its lookups report as one piece of work (BrandoAdmin.Work),
  # started here so the button is busy before the sweep runs.
  #
  # The lookups store what they find as the system, so asking for them needs
  # the right to update videos, in both authorization modes.
  def handle_event("fetch_metadata", _, socket) do
    user = socket.assigns.current_user

    # `run/4` reads the role afresh: the list may have opened before a demotion
    case Brando.Authorization.Boundary.run(user, :update, Video, fn _ -> {:ok, :allowed} end) do
      {:ok, :allowed} -> start_lookups(socket, user)
      _ -> {:noreply, put_flash(socket, :error, gettext("You do not have permission for this action."))}
    end
  end

  defp start_lookups(socket, user) do
    count = socket.assigns.missing_metadata_count

    Work.start(
      user,
      VideoMetadataSweep.work_key(),
      ngettext("Looking up %{count} video", "Looking up %{count} videos", count)
    )

    case VideoMetadataSweep.enqueue(user) do
      {:ok, _job} ->
        {:noreply, socket}

      {:error, _reason} ->
        Work.fail(user, VideoMetadataSweep.work_key(), gettext("Could not look the videos up"))
        {:noreply, socket}
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(title), do: title

  # Where a video added from a URL or a provider library goes: the folder in
  # view, the root's own at the root.
  defp add_folder_id(socket), do: library_folder_id(socket.assigns.current_folder_id, socket.assigns.upload_root)

  # A folder of this library, or none: the browser names it.
  defp library_folder_id(folder_id, upload_root) do
    with {id, ""} <- Integer.parse(to_string(folder_id || "")),
         %Folder{library: true, scope: scope, path: path} <- Brando.Repo.get(Folder, id),
         true <- AssetListHelpers.folder_under_root?(FolderBrowser.absolute_folder(path, scope), upload_root) do
      id
    else
      _ -> nil
    end
  end

  # A video the upload manager stored (`:local`, `:s3`)
  @impl true
  def handle_info({:asset_ready, %{"kind" => "asset_library"}, %Video{}}, socket) do
    AssetListHelpers.update_list_entries(socket.assigns.schema)
    {:noreply, refresh(socket)}
  end

  def handle_info({:asset_ready, _target, _asset}, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:delete_unused, result, socket) do
    socket = AssetListHelpers.finish_delete_unused(socket, result)

    {:noreply,
     socket
     |> refresh()}
  end

  def handle_async(:library_page, result, socket), do: {:noreply, ProviderLibraryPanel.page_loaded(socket, result)}

  def handle_async(:url_video, result, socket) do
    case VideoFromURL.finish(socket, result, socket.assigns.current_user) do
      {:ok, video, socket} ->
        send(self(), {:toast, gettext("Added %{title}", title: Videos.display_title(video) || gettext("Untitled"))})
        AssetListHelpers.update_list_entries(socket.assigns.schema)
        {:noreply, socket |> assign(:url_add, nil) |> refresh()}

      {:error, :forbidden, socket} ->
        send(self(), {:toast, gettext("You do not have permission for this action.")})
        {:noreply, socket}

      {:error, _reason, socket} ->
        {:noreply, socket}

      {:ignore, socket} ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="admin-workspace workspace-list media-workspace videos-workspace">
      <Workspace.header icon={@page_icon} title={gettext("Videos")}>
        <WorkComponent.button
          :if={@missing_metadata_count > 0 || @work[VideoMetadataSweep.work_key()]}
          key={VideoMetadataSweep.work_key()}
          work={@work[VideoMetadataSweep.work_key()]}
          running={gettext("Fetching thumbnails and titles")}
          disabled={@missing_metadata_count == 0}
          phx-click="fetch_metadata"
          title={gettext("Look up thumbnails, titles and durations at each video's source")}
        >
          {gettext("Fetch thumbnails and titles")}
          <span :if={@missing_metadata_count > 0} class="alt-text-missing">
            {ngettext("%{count} missing", "%{count} missing", @missing_metadata_count)}
          </span>
        </WorkComponent.button>
      </Workspace.header>

      <Content.modal
        :if={@playing}
        id="video-player-modal"
        title={Brando.Videos.display_title(@playing) || gettext("Untitled")}
        icon="film"
        show
        wide
        close={JS.push("close_video")}
      >
        <VideoPlayer.player video={@playing} />
      </Content.modal>

      <%!-- Outside the folder browser, a component: the URL hook pushes to
            its own element, which then reaches this LiveView. --%>
      <Content.modal
        :if={@url_add}
        id="video-add-url"
        title={gettext("Add from URL")}
        subtitle={add_destination(@current_folder)}
        icon="link"
        show
        close={JS.push("close_url_add")}
      >
        <div class="video-library-add">
          <p class="video-library-add-lede">
            {gettext(
              "A YouTube or Vimeo address, or the address of a video file or stream. The title, thumbnail and duration are looked up at the source."
            )}
          </p>
          <VideoFromURL.input id={"video-library-#{@url_add}"} creating={@creating_video} />
        </div>
      </Content.modal>

      <Content.modal
        :if={@library}
        id="video-add-library"
        title={gettext("Add from %{provider}", provider: @library.label)}
        subtitle={add_destination(@current_folder)}
        icon="cloud-download"
        show
        wide
        close={JS.push("close_library")}
      >
        <div class="video-library-add">
          <ProviderLibraryPanel.panel id="video-library" library={@library} heading={false} select_existing={false} />
        </div>
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
        enable_folder_drop={BrandoAdmin.Authorization.allowed?(:update, @schema)}
        allow_new_folder={BrandoAdmin.Authorization.allowed?(:update, @schema)}
        folder_drop_event="assets_move_selected_to_folder"
        show_new_folder_event="assets_show_new_folder_form"
        cancel_new_folder_event="assets_cancel_new_folder_form"
        create_folder_event="assets_create_folder"
        main_id="assets-video-browser-main"
      >
        <:main_header>
          <div class="image-picker-main-header">
            <h3>
              {cond do
                @all_folders? -> gettext("All folders")
                @current_folder == "" -> gettext("Library root")
                true -> Path.basename(@current_folder)
              end}
            </h3>
            <div class="image-picker-main-actions">
              <span>
                {ngettext("%{count} video", "%{count} videos", @visible_video_count, count: @visible_video_count)}
              </span>
              <span :if={@clipboard_ids != []} class="clipboard-status">
                {gettext("Cut queue")}: {length(@clipboard_ids)}
              </span>
              <%!-- Into the folder in view; at the root, the default config's
                    folder, which the root is. --%>
              <div
                :if={
                  @video_upload_available? and @upload_strategy in [:local, :s3] and
                    BrandoAdmin.Authorization.allowed?(:create, @schema)
                }
                id="library-video-upload"
                phx-hook="Brando.UploadTrigger"
                data-kind="asset_library"
                data-component-id="assets-video-browser"
                data-asset-type="video"
                data-deliver-topic={@deliver_topic}
                data-config-target="default"
                data-folder={@current_folder_abs}
                data-folder-id={@current_folder_id}
                data-click-mode="trigger"
                data-accept=".mp4,.webm,.mov,.avi,.ogv"
                class="library-upload-trigger"
              >
                <button type="button" class="folder-action upload-trigger"><.icon name="upload" />{gettext("Upload")}</button>
                <input type="file" class="file-input" accept="video/*" multiple aria-label={gettext("Upload videos")} />
              </div>
              <div
                :if={
                  @video_upload_available? and @upload_strategy not in [:local, :s3] and
                    BrandoAdmin.Authorization.allowed?(:create, @schema)
                }
                id="library-video-provider-upload"
                phx-hook={MediaField.video_uploader_hook(@upload_strategy)}
                data-ref={@current_folder_id}
                class="library-upload-trigger"
              >
                <button
                  type="button"
                  class="folder-action"
                  onclick="this.closest('[phx-hook]').querySelector('.file-input').click()"
                ><.icon name="upload" />{gettext("Upload")}</button>
                <input type="file" class="file-input" accept="video/*" multiple aria-label={gettext("Upload videos")} />
              </div>
              <button
                :if={@allow_external_urls? and BrandoAdmin.Authorization.allowed?(:create, @schema)}
                type="button"
                class="folder-action"
                aria-haspopup="dialog"
                phx-click="open_url_add"
              >
                <.icon name="link" />{gettext("Add from URL")}
              </button>
              <button
                :for={provider <- @library_providers}
                type="button"
                class="folder-action"
                aria-haspopup="dialog"
                phx-click="open_library"
                phx-value-strategy={provider.strategy}
              >
                <.icon name="cloud-download" />{gettext("Add from %{provider}", provider: provider.label)}
              </button>
              <SortByUse.sort_button
                :if={
                  @visible_video_count > 0 and !@all_folders? and !AssetListHelpers.unused_filter?(@params) and
                    BrandoAdmin.Authorization.allowed?(:update, @schema)
                }
                asset_type={:video}
              />
              <SortByUse.delete_unused_button
                :if={
                  AssetListHelpers.unused_filter?(@params) and @unused_count > 0 and
                    BrandoAdmin.Authorization.allowed?(:delete, @schema)
                }
                asset_type={:video}
                count={@unused_count}
                busy={@deleting_unused?}
              />
              <button
                :if={@clipboard_ids != [] and BrandoAdmin.Authorization.allowed?(:update, @schema)}
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

        <SortByUse.result :if={@sweep_result} asset_type={:video} result={@sweep_result} />
        <SortByUse.modal :if={@sweep} sweep={@sweep} />

        <.live_component
          module={Content.List}
          id={"content_listing_#{@schema}_default"}
          schema={@schema}
          current_user={@current_user}
          uri={@uri}
          params={AssetListHelpers.list_params(@params, @root_folder_ids)}
          listing={:default}
          saved_views={false}
          hidden_filters={[:folder_id]}
          empty_title={gettext("No videos in this view")}
          empty_description={gettext("Choose a folder or adjust your search.")}
          extra_selection_actions={
            if BrandoAdmin.Authorization.allowed?(:update, @schema),
              do: [%{event: "assets_cut_selected", label: gettext("Cut selected")}],
              else: []
          }
        />
      </.live_component>
    </div>
    """
  end

  # The lookups are in: the thumbnails and titles they found, and what is
  # still missing. Called by `on_mount BrandoAdmin.Work`.
  def handle_work(%Work{key: key, status: status}, socket) when status != :running do
    if key == VideoMetadataSweep.work_key() do
      socket
      |> assign(:missing_metadata_count, length(Videos.list_video_ids_missing_metadata()))
      |> refresh()
    else
      socket
    end
  end

  def handle_work(_work, socket), do: socket

  # After a change: the folders, and the counts the header shows (unused,
  # all folders), as handle_params assigns them.
  defp refresh(socket) do
    socket
    |> assign_folder_state(socket.assigns.current_folder)
    |> AssetListHelpers.refresh_counts(&Videos.list_videos/1, :visible_video_count)
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
    # The folder uploads go into: the root's own at the root
    |> assign(
      :current_folder_id,
      FolderBrowser.folder_id_for(
        current_folder,
        socket.assigns.upload_root,
        socket.assigns.current_user,
        socket.assigns.schema
      )
    )
    |> assign(
      :visible_video_count,
      if(current_folder == "",
        do: Enum.count(videos, &(is_nil(&1.folder_id) or &1.folder_id in root_folder_ids)),
        else: length(visible_videos)
      )
    )
  end

  defp add_destination(""), do: gettext("Goes into %{folder}", folder: gettext("Library root"))
  defp add_destination(folder), do: gettext("Goes into %{folder}", folder: String.replace(folder, "/", " › "))

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
