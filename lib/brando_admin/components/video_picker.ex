defmodule BrandoAdmin.Components.VideoPicker do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext
  use BrandoAdmin.Components.PickerHelpers

  alias BrandoAdmin.Components.Assets.FileBrowser
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Images.FolderBrowser
  alias Phoenix.LiveView.JS

  def mount(socket) do
    {:ok,
     socket
     |> assign_new(:z_index, fn -> 1100 end)
     |> assign_defaults()
     |> stream(:visible_videos, [])}
  end

  def update(
        %{
          config_target: config_target,
          event_target: event_target,
          multi: multi,
          selected_videos: selected_videos
        } =
          assigns,
        socket
      ) do
    {resolved_config, resolved_target} = Brando.Uploads.resolve_video_config(config_target)

    {:ok,
     socket
     |> assign(:config_target, resolved_target)
     |> assign(:event_target, event_target)
     |> assign(:multi, multi)
     |> assign(:selected_videos, selected_videos)
     |> assign(
       :upload_strategy,
       assigns[:upload_strategy] || resolved_config.upload_strategy
     )
     |> assign(:allow_uploads?, resolved_config.allow_uploads)
     |> assign(:allow_external_urls?, resolved_config.allow_external_urls)
     |> assign(:video_config, resolved_config)
     |> assign(:new_folder, "")
     |> assign(:show_new_folder_form, false)
     |> assign_new(:current_user, fn -> assigns[:current_user] end)
     |> assign_new(:upload_progress, fn -> nil end)
     |> assign_videos()
     |> assign_folder_state(nil)
     |> assign_video_upload_available()
     |> push_selection_state()}
  end

  def update(%{selected_videos: selected_videos}, socket) do
    {:ok,
     socket
     |> assign(:selected_videos, selected_videos)
     |> push_selection_state()}
  end

  def update(%{event: "upload_complete", asset: %Brando.Videos.Video{} = video}, socket) do
    send_update(socket.assigns.event_target, %{event: "select_video", id: video.id})

    {:ok,
     socket
     |> assign(:upload_progress, nil)
     |> assign_videos()
     |> assign_folder_state(socket.assigns.current_folder)
     |> push_selection_state()}
  end

  def update(%{refresh_videos: true} = assigns, socket) do
    requested_folder = Map.get(assigns, :requested_folder)

    {:ok,
     socket
     |> assign_defaults()
     |> assign_videos()
     |> assign_folder_state(requested_folder || socket.assigns.current_folder)
     |> push_selection_state()}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign_defaults()
     |> assign(assigns)
     |> assign_video_upload_available()}
  end

  # Whether to offer the direct "Upload file" button — computed once per update
  # (not in the template) from the resolved upload strategy + provider credentials.
  defp assign_video_upload_available(socket) do
    assign(
      socket,
      :video_upload_available?,
      Brando.Uploads.video_upload_available?(%{
        socket.assigns.video_config
        | upload_strategy: socket.assigns.upload_strategy
      })
    )
  end

  defp assign_videos(socket) do
    {:ok, videos} =
      Brando.Videos.list_videos(%{
        filter: %{config_target: socket.assigns.config_target},
        order: "desc id",
        preload: [:thumbnail, :file]
      })

    assign(socket, :videos, videos)
  end

  defp assign_defaults(socket) do
    socket
    |> assign_new(:multi, fn -> false end)
    |> assign_new(:videos, fn -> [] end)
    |> assign_new(:config_target, fn -> nil end)
    |> assign_new(:event_target, fn -> nil end)
    |> assign_new(:selected_videos, fn -> [] end)
    |> assign_new(:current_user, fn -> nil end)
    |> assign_new(:upload_strategy, fn -> Brando.default_video_upload_strategy() end)
    |> assign_new(:allow_uploads?, fn -> true end)
    |> assign_new(:allow_external_urls?, fn -> true end)
    |> assign_new(:video_config, fn -> Brando.Type.VideoConfig.default_config() end)
    |> assign_new(:upload_progress, fn -> nil end)
    |> assign_new(:show_url_input, fn -> false end)
    |> assign_new(:url_input, fn -> "" end)
    |> assign_new(:creating_video, fn -> false end)
    |> assign_new(:playing_video, fn -> nil end)
    |> assign_new(:editing_video_id, fn -> nil end)
    # Folder state
    |> assign_new(:folders, fn -> [""] end)
    |> assign_new(:custom_folders, fn -> [] end)
    |> assign_new(:child_folders, fn -> [] end)
    |> assign_new(:breadcrumbs, fn -> [%{label: "Root", folder: ""}] end)
    |> assign_new(:current_folder, fn -> "" end)
    |> assign_new(:new_folder, fn -> "" end)
    |> assign_new(:show_new_folder_form, fn -> false end)
    |> assign_new(:upload_root, fn -> "videos/default" end)
    |> assign_new(:recent_folders, fn -> [] end)
    |> assign_new(:recent_folders_for_root, fn -> [] end)
    # Organize state
    |> assign_new(:organize_selected, fn -> [] end)
    |> assign_new(:last_organize_selected_id, fn -> nil end)
    |> assign_new(:video_count, fn -> 0 end)
    |> assign_new(:visible_item_ids, fn -> [] end)
  end

  # -- PickerHelpers callbacks --

  defp on_folder_change(socket) do
    push_selection_state(socket)
  end

  defp push_selection_state(socket) do
    selected_ids = Enum.map(socket.assigns.selected_videos, &normalize_item_id/1)
    organize_ids = socket.assigns.organize_selected

    push_event(socket, "video_picker_selection_changed", %{
      selected_ids: selected_ids,
      organize_ids: organize_ids
    })
  end

  defp assign_folder_state(socket, requested_folder) do
    upload_root = video_upload_root(socket.assigns.config_target)

    entries = folder_entries(socket.assigns.videos)

    folders =
      FolderBrowser.folders_from_entries(entries, upload_root)
      |> Kernel.++(socket.assigns.custom_folders)
      |> Enum.map(&(FolderBrowser.normalize_folder(&1) || ""))
      |> Enum.uniq()
      |> Enum.sort()

    requested_relative =
      case requested_folder do
        nil ->
          socket.assigns.current_folder

        folder ->
          FolderBrowser.relative_folder(folder, upload_root)
      end

    current_folder =
      if requested_relative in folders do
        requested_relative
      else
        ""
      end

    matched_entries =
      FolderBrowser.entries_in_folder(
        entries,
        current_folder,
        upload_root
      )

    matched_ids = MapSet.new(Enum.map(matched_entries, & &1.id))

    # Videos with nil folder_id and nil path belong to root
    unassigned_ids =
      if current_folder == "" do
        entries
        |> Enum.filter(&(is_nil(&1.folder_id) and is_nil(&1.path)))
        |> Enum.map(& &1.id)
        |> MapSet.new()
      else
        MapSet.new()
      end

    visible_ids = MapSet.union(matched_ids, unassigned_ids)

    visible_video_structs =
      socket.assigns.videos
      |> Enum.filter(&(&1.id in visible_ids))
      |> Enum.sort_by(& &1.id, :desc)

    child_folders = FolderBrowser.child_folders(folders, current_folder)
    breadcrumbs = FolderBrowser.breadcrumbs(current_folder)

    recent_folders_for_root =
      socket.assigns.recent_folders
      |> Enum.map(&FolderBrowser.normalize_folder/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&folder_under_root?(&1, upload_root))
      |> Enum.reject(&(FolderBrowser.relative_folder(&1, upload_root) == ""))
      |> Enum.take(5)

    socket
    |> assign(:upload_root, upload_root)
    |> assign(:folders, folders)
    |> assign(:current_folder, current_folder)
    |> assign(:video_count, length(visible_video_structs))
    |> assign(:visible_item_ids, Enum.map(visible_video_structs, & &1.id))
    |> stream(:visible_videos, visible_video_structs, reset: true)
    |> assign(:child_folders, child_folders)
    |> assign(:breadcrumbs, breadcrumbs)
    |> assign(:recent_folders_for_root, recent_folders_for_root)
  end

  defp folder_entries(videos) do
    Enum.map(videos, fn video ->
      %{
        id: video.id,
        folder_id: video.folder_id,
        config_target: video.config_target,
        path: folder_entry_path(video)
      }
    end)
  end

  defp folder_entry_path(%{type: :upload, remote_id: rid}) when is_binary(rid), do: rid
  defp folder_entry_path(_), do: nil

  # -- Video-specific event handlers --

  def handle_event("organize_select_video", %{"id" => id} = params, socket) do
    case parse_item_id(id) do
      {:ok, parsed_id} ->
        meta? = truthy?(params["meta"])

        socket =
          if meta?,
            do: organize_select_range(socket, parsed_id),
            else: organize_select_toggle(socket, parsed_id)

        {:noreply, push_selection_state(socket)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("clear_organize_selection", _, socket) do
    {:noreply,
     socket
     |> assign(:organize_selected, [])
     |> assign(:last_organize_selected_id, nil)
     |> push_selection_state()}
  end

  def handle_event("picker_move_to_folder", %{"folder" => folder, "ids" => ids}, socket) do
    ids = parse_selected_ids(ids)
    absolute_folder = FolderBrowser.absolute_folder(folder, socket.assigns.upload_root)

    cond do
      ids == [] ->
        {:noreply, socket}

      not folder_under_root?(absolute_folder, socket.assigns.upload_root) ->
        {:noreply, socket}

      true ->
        folder_id = FolderBrowser.folder_id_for(folder, socket.assigns.upload_root)
        move_videos_to_folder(ids, folder_id)

        send(self(), {:toast, gettext("Moved %{count} videos", count: length(ids))})

        {:noreply,
         socket
         |> assign(:organize_selected, [])
         |> assign(:last_organize_selected_id, nil)
         |> assign_videos()
         |> assign_folder_state(socket.assigns.current_folder)
         |> push_selection_state()}
    end
  end

  def handle_event("toggle_url_input", _, %{assigns: %{allow_external_urls?: false}} = socket) do
    {:noreply, assign(socket, :show_url_input, false)}
  end

  def handle_event("toggle_url_input", _, socket) do
    {:noreply, assign(socket, :show_url_input, !socket.assigns.show_url_input)}
  end

  def handle_event("start_rename", %{"video-id" => video_id}, socket) do
    {:noreply, assign(socket, :editing_video_id, String.to_integer(video_id))}
  end

  def handle_event("cancel_rename", _, socket) do
    {:noreply, assign(socket, :editing_video_id, nil)}
  end

  def handle_event("rename_video", %{"title" => title, "video_id" => video_id}, socket) do
    video_id = if is_binary(video_id), do: String.to_integer(video_id), else: video_id

    Brando.Videos.Video
    |> Brando.Repo.get!(video_id)
    |> Ecto.Changeset.change(%{title: title})
    |> Brando.Repo.update()

    {:noreply,
     socket
     |> assign(:editing_video_id, nil)
     |> assign_videos()
     |> assign_folder_state(socket.assigns.current_folder)
     |> push_selection_state()}
  end

  def handle_event(
        "play_video",
        %{"video-id" => video_id, "type" => type} = params,
        socket
      ) do
    video_data = Enum.find(socket.assigns.videos, &(&1.id == String.to_integer(video_id)))
    source_url = Map.get(params, "source-url", "")

    {preview_type, playback_url} =
      case Brando.Videos.Helpers.get_playback_url(video_data) do
        {:ok, url} when video_data.type not in [:youtube, :vimeo] -> {:external_file, url}
        _ -> {video_data.type, source_url}
      end

    video = %{
      id: video_id,
      source_url: playback_url,
      type: preview_type || String.to_existing_atom(type),
      unique_id: System.unique_integer([:positive]),
      width: video_data.width,
      height: video_data.height
    }

    {:noreply, assign(socket, :playing_video, video)}
  end

  def handle_event("close_video_player", _, socket) do
    {:noreply, assign(socket, :playing_video, nil)}
  end

  def handle_event("url", _params, %{assigns: %{allow_external_urls?: false}} = socket) do
    {:noreply, assign(socket, :creating_video, false)}
  end

  def handle_event("url", params, socket) do
    %{
      "width" => width,
      "height" => height,
      "source" => source,
      "remoteId" => remote_id,
      "url" => url
    } = params

    video_type =
      case source do
        "vimeo" -> :vimeo
        "youtube" -> :youtube
        "file" -> :external_file
        _ -> :external_file
      end

    {title, description, _thumbnail_url} =
      case video_type do
        :youtube -> fetch_oembed_metadata("youtube", url)
        :vimeo -> fetch_oembed_metadata("vimeo", url)
        _ -> {extract_title_from_url(url), nil, nil}
      end

    video_params = %{
      type: video_type,
      source_url: url,
      remote_id: remote_id,
      width: width,
      height: height,
      title: title,
      caption: description,
      aspect_ratio: calculate_aspect_ratio(width, height),
      config_target: normalize_video_config_target(socket.assigns.config_target)
    }

    case Brando.Videos.create_video(video_params, Map.get(socket.assigns, :current_user)) do
      {:ok, video} ->
        send_update(socket.assigns.event_target, %{
          event: "video_created_from_url",
          video_data: Map.from_struct(video),
          video_changeset: Ecto.Changeset.change(video)
        })

        {:noreply,
         socket
         |> assign(:creating_video, false)
         |> assign(:show_url_input, false)
         |> update(:selected_videos, &Enum.uniq([video.id | &1]))
         |> assign_videos()
         |> assign_folder_state(socket.assigns.current_folder)
         |> push_selection_state()}

      {:error, changeset} ->
        error_msg =
          Enum.map_join(changeset.errors, ", ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)

        require Logger
        Logger.warning("Video changeset error: #{error_msg}")
        {:noreply, assign(socket, :creating_video, false)}
    end
  end

  def handle_event(
        "get_video_upload_url",
        %{
          "request_ref" => request_ref,
          "filename" => filename,
          "size" => size,
          "mime_type" => mime_type
        },
        socket
      ) do
    user = socket.assigns.current_user

    {video_config, config_target} =
      Brando.Uploads.resolve_video_config(socket.assigns.config_target)

    # The picker may receive a tuple target from form inputs. Resolve and
    # serialize it once so provider-created rows retain the same config target
    # used for filtering, metadata, limits, and upload strategy.
    video_config = %{video_config | upload_strategy: socket.assigns.upload_strategy}

    case Brando.Videos.Uploader.initiate_upload(filename, user,
           config: video_config,
           config_target: config_target,
           file_meta: %{name: filename, size: size, type: mime_type}
         ) do
      {:ok, %{upload_url: upload_url, video: video} = result} ->
        event_payload = %{
          upload_url: upload_url,
          video_id: video.id,
          filename: filename,
          request_ref: request_ref
        }

        event_payload =
          case Map.get(result, :tus_auth) do
            nil -> event_payload
            tus_auth -> Map.put(event_payload, :tus_auth, tus_auth)
          end

        {:noreply, push_event(socket, "video_upload_url_ready", event_payload)}

      {:error, reason} ->
        {:noreply,
         push_event(socket, "video_upload_url_error", %{
           error: inspect(reason),
           filename: filename,
           request_ref: request_ref
         })}
    end
  end

  def handle_event("get_video_upload_url", params, socket) do
    {:noreply,
     push_event(socket, "video_upload_url_error", %{
       error: "Invalid video upload request",
       filename: Map.get(params, "filename", ""),
       request_ref: Map.get(params, "request_ref", "")
     })}
  end

  def handle_event("video_upload_complete", %{"video_id" => video_id}, socket) do
    case Brando.Videos.get_video(%{matches: %{id: video_id}, preload: [:thumbnail]}) do
      {:ok, video} ->
        {:ok, _video} = Brando.Videos.Uploader.complete_client_upload(video)

        send_update(socket.assigns.event_target, %{
          event: "select_video",
          id: video_id
        })

        {:noreply,
         socket
         |> assign(:upload_progress, nil)
         |> assign_videos()
         |> assign_folder_state(socket.assigns.current_folder)
         |> push_selection_state()}

      {:error, _} ->
        {:noreply, assign(socket, :upload_progress, nil)}
    end
  end

  def handle_event("video_upload_progress", params, socket) do
    progress = %{
      percentage: params["percentage"],
      uploaded_mb: params["uploaded_mb"],
      total_mb: params["total_mb"]
    }

    {:noreply, assign(socket, :upload_progress, progress)}
  end

  def handle_event("upload_error", %{"error" => error, "filename" => filename}, socket) do
    require Logger
    Logger.warning("Video upload error for #{filename}: #{error}")
    {:noreply, assign(socket, :upload_progress, nil)}
  end

  def handle_event("delete_video_from_picker", %{"id" => id}, socket) do
    case parse_item_id(id) do
      {:ok, video_id} ->
        _ = Brando.Videos.delete_video(video_id, socket.assigns.current_user)

        send(self(), {:toast, gettext("Video deleted")})

        {:noreply,
         socket
         |> assign(
           :selected_videos,
           Enum.reject(socket.assigns.selected_videos, &same_item_id?(&1, video_id))
         )
         |> assign_videos()
         |> assign_folder_state(socket.assigns.current_folder)
         |> push_selection_state()}

      _ ->
        {:noreply, socket}
    end
  end

  # -- Render --

  def render(assigns) do
    ~H"""
    <div>
      <Content.drawer
        id={@id}
        title={gettext("Select video")}
        close={toggle_drawer("##{@id}")}
        z={@z_index}
        wide
        light
      >
        <:info>
          <.live_component
            module={FileBrowser}
            id={"#{@id}-top"}
            section={:top}
            mode={:drawer}
            target={@myself}
            upload_root={@upload_root}
            current_folder={@current_folder}
            breadcrumbs={@breadcrumbs}
            recent_folders={@recent_folders_for_root}
          >
            <:top_lead>
              <div class="video-picker-url-section">
                <div class="video-picker-add-actions">
                  <button
                    :if={@allow_external_urls?}
                    type="button"
                    class="video-picker-add-btn"
                    phx-click={JS.push("toggle_url_input", target: @myself)}
                  >
                    <.icon name="hero-link" />
                    <%= if @show_url_input do %>
                      {gettext("Hide URL input")}
                    <% else %>
                      {gettext("Add from URL")}
                    <% end %>
                  </button>

                  <div
                    :if={@video_upload_available? && @upload_strategy in [:local, :s3]}
                    phx-hook="Brando.UploadTrigger"
                    id={"video-uploader-#{@id}"}
                    data-kind="video_picker"
                    data-component-id={@id}
                    data-asset-type="video"
                    data-config-target={@config_target}
                    data-click-mode="trigger"
                    data-accept=".mp4,.webm,.mov,.avi,.ogv"
                  >
                    <button
                      type="button"
                      class="video-picker-add-btn upload-trigger"
                    >
                      <.icon name="hero-arrow-up-tray" />
                      {gettext("Upload file")}
                    </button>
                    <input type="file" accept="video/*" class="video-picker-file-input" />
                  </div>

                  <div
                    :if={@video_upload_available? && @upload_strategy not in [:local, :s3]}
                    phx-hook={video_uploader_hook(@upload_strategy)}
                    id={"video-provider-uploader-#{@id}"}
                    data-target={@myself}
                  >
                    <button
                      type="button"
                      class="video-picker-add-btn"
                      onclick="this.closest('[phx-hook]').querySelector('.video-picker-file-input').click()"
                    >
                      <.icon name="hero-arrow-up-tray" />
                      {gettext("Upload file")}
                    </button>
                    <input type="file" accept="video/*" class="video-picker-file-input" />
                  </div>
                </div>

                <div :if={@allow_external_urls? && @show_url_input} class="video-picker-url-input">
                  <div
                    class="video-url-parser"
                    phx-hook="Brando.VideoURLParser"
                    data-target={@myself}
                    id={"video-url-parser-#{@id}"}
                  >
                    <div class="video-picker-url-field">
                      <label>{gettext("Video URL")}</label>
                      <input
                        type="text"
                        class="text"
                        placeholder={gettext("Paste YouTube, Vimeo or direct video URL")}
                      />
                      <button type="button" class="video-picker-add-btn">
                        <%= if @creating_video do %>
                          {gettext("Creating...")}
                        <% else %>
                          {gettext("Create video")}
                        <% end %>
                      </button>
                      <div class="video-picker-analyzing hidden">
                        <div class="spinner"></div>
                        <span>{gettext("Analyzing video...")}</span>
                      </div>
                    </div>
                  </div>
                </div>

                <div :if={@upload_progress} class="video-picker-upload-progress">
                  <div class="progress-bar">
                    <div class="progress-fill" style={"width: #{@upload_progress.percentage}%"}></div>
                  </div>
                  <span class="progress-text">
                    {gettext("Uploading...")} {@upload_progress.percentage}%
                    ({@upload_progress.uploaded_mb}/{@upload_progress.total_mb} MB)
                  </span>
                </div>
              </div>
            </:top_lead>
            <:toolbar_actions>
              <div class="video-picker-view-toggle">
                <button
                  id={"#{@id}-view-grid"}
                  class="view-toggle"
                  type="button"
                  phx-click={show_grid(@id)}
                >
                  {gettext("Grid")}
                </button>
                <button
                  id={"#{@id}-view-list"}
                  class="view-toggle is-active"
                  type="button"
                  phx-click={show_list(@id)}
                >
                  {gettext("List")}
                </button>
              </div>
            </:toolbar_actions>
          </.live_component>
        </:info>

        <.live_component
          module={FileBrowser}
          id={"#{@id}-browser"}
          section={:browser}
          mode={:drawer}
          target={@myself}
          upload_root={@upload_root}
          current_folder={@current_folder}
          breadcrumbs={@breadcrumbs}
          recent_folders={@recent_folders_for_root}
          show_recent_folders={false}
          child_folders={@child_folders}
          show_new_folder_form={@show_new_folder_form}
          new_folder={@new_folder}
          main_id={"video-picker-main-#{@id}"}
          enable_folder_drop={true}
          folder_drop_event="picker_move_to_folder"
        >
          <:main_header>
            <div class="video-picker-main-header">
              <h3>{folder_label_for_display(@current_folder, @upload_root)}</h3>
              <div class="video-picker-main-actions">
                <span>
                  {ngettext("%{count} video", "%{count} videos", @video_count, count: @video_count)}
                </span>
              </div>
            </div>
          </:main_header>

          <div
            id={"video-picker-drawer-#{@id}"}
            class="video-picker list"
          >
            <%= if @video_count == 0 do %>
              <div class="video-picker-empty">
                <.icon name="hero-film" />
                <h4>{gettext("No videos in this folder")}</h4>
                <p>{gettext("Create a video from URL or choose another folder")}</p>
              </div>
            <% end %>

            <div
              :if={@organize_selected != []}
              class="video-picker-organize-bar"
            >
              <.icon name="hero-arrows-pointing-out" />
              <span>
                {ngettext(
                  "%{count} video selected for organizing",
                  "%{count} videos selected for organizing",
                  length(@organize_selected),
                  count: length(@organize_selected)
                )}
              </span>
              <span class="video-picker-organize-hint">{gettext("Drag to a folder")}</span>
              <button
                type="button"
                class="video-picker-organize-clear"
                phx-click="clear_organize_selection"
                phx-target={@myself}
              >
                {gettext("Clear")}
              </button>
            </div>

            <div
              id={"video-picker-grid-#{@id}"}
              phx-update="stream"
              phx-hook="Brando.VideoPickerGrid"
              data-target-component={@myself}
            >
              <.video_row
                :for={{dom_id, video} <- @streams.visible_videos}
                id={dom_id}
                video={video}
                multi={@multi}
                event_target={@event_target}
                myself={@myself}
                editing_video_id={@editing_video_id}
              />
            </div>
          </div>
        </.live_component>
      </Content.drawer>

      <Content.modal title={gettext("Video Preview")} id="video-player-modal">
        <div
          class="video-player-container"
          style={"padding-bottom: #{if @playing_video, do: get_aspect_ratio(@playing_video), else: "56.25%"}"}
        >
          <%= if @playing_video do %>
            <%= case @playing_video.type do %>
              <% :youtube -> %>
                <iframe
                  id={"youtube-player-#{@playing_video.unique_id}"}
                  src={get_embed_url(@playing_video)}
                  frameborder="0"
                  allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                  allowfullscreen
                  class="video-embed"
                ></iframe>
              <% :vimeo -> %>
                <iframe
                  id={"vimeo-player-#{@playing_video.unique_id}"}
                  src={get_embed_url(@playing_video)}
                  frameborder="0"
                  allow="autoplay; fullscreen; picture-in-picture"
                  allowfullscreen
                  class="video-embed"
                ></iframe>
              <% :external_file -> %>
                <video
                  id={"video-player-#{@playing_video.unique_id}"}
                  controls
                  autoplay
                  class="video-embed"
                >
                  <source src={@playing_video.source_url} />
                  {gettext("Your browser does not support the video tag.")}
                </video>
              <% _ -> %>
                <div class="video-not-supported">
                  {gettext("Video type not supported for preview")}
                </div>
            <% end %>
          <% else %>
            <div class="video-not-loaded">
              {gettext("Loading video...")}
            </div>
          <% end %>
        </div>
      </Content.modal>
    </div>
    """
  end

  # -- Sub-components --

  defp video_row(assigns) do
    assigns = assign(assigns, :editing, assigns.editing_video_id == assigns.video.id)

    ~H"""
    <div
      id={@id}
      class="video-picker__video"
      data-id={@video.id}
      phx-click={
        if @multi,
          do: JS.push("select_video", target: @event_target),
          else: JS.push("select_video", target: @event_target) |> toggle_drawer("#video-picker")
      }
      phx-value-id={@video.id}
    >
      <span class="video-picker__selected-indicator" aria-hidden="true">
        <.icon name="hero-check-mini" />
      </span>
      <.video_preview video={@video} myself={@myself} />
      <div class="video-picker__info">
        <div class="video-picker__name">
          <%= if @editing do %>
            <form
              id={"rename-video-#{@video.id}"}
              phx-submit={JS.push("rename_video", target: @myself)}
            >
              <input type="hidden" name="video_id" value={@video.id} />
              <input
                type="text"
                name="title"
                value={@video.title || ""}
                class="video-title-input"
                phx-blur={JS.dispatch("submit", to: "#rename-video-#{@video.id}")}
                phx-keydown={JS.push("cancel_rename", target: @myself)}
                phx-key="Escape"
                autofocus
              />
            </form>
          <% else %>
            <div class="video-picker__title">{@video.title || gettext("Untitled")}</div>
            <div
              :if={@video.type == :external_file && @video.source_url}
              class="video-picker__source-url"
            >
              {@video.source_url}
            </div>
          <% end %>
        </div>
        <div class="video-picker__meta">{@video.type}</div>
        <div :if={@video.width && @video.height} class="video-picker__meta">
          {@video.width}&times;{@video.height}
        </div>
        <div class="video-picker__actions">
          <button
            type="button"
            class="video-picker-action-button"
            aria-label={gettext("Video actions")}
            phx-click={toggle_dropdown("#video-picker-menu-#{@video.id}")}
            phx-click-away={hide_dropdown("#video-picker-menu-#{@video.id}")}
          >
            <.icon name="hero-ellipsis-horizontal-circle" />
          </button>
          <ul id={"video-picker-menu-#{@video.id}"} class="video-picker-action-dropdown hidden">
            <li>
              <button
                type="button"
                phx-click={
                  JS.push("start_rename", target: @myself)
                  |> hide_dropdown("#video-picker-menu-#{@video.id}")
                }
                phx-value-video-id={@video.id}
              >
                <.icon name="hero-pencil-square" />
                {gettext("Rename")}
              </button>
            </li>
            <li>
              <button
                type="button"
                phx-click={
                  JS.push("play_video", target: @myself)
                  |> show_modal("#video-player-modal")
                  |> hide_dropdown("#video-picker-menu-#{@video.id}")
                }
                phx-value-video-id={@video.id}
                phx-value-source-url={@video.source_url}
                phx-value-type={@video.type}
              >
                <.icon name="hero-play" />
                {gettext("Preview")}
              </button>
            </li>
            <li>
              <button
                type="button"
                class="delete-action"
                phx-confirm={gettext("Delete this video?")}
                phx-click={
                  JS.push("delete_video_from_picker",
                    target: @myself,
                    value: %{id: @video.id}
                  )
                  |> hide_dropdown("#video-picker-menu-#{@video.id}")
                }
              >
                <.icon name="hero-trash" />
                {gettext("Delete video")}
              </button>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp video_preview(assigns) do
    thumbnail_url =
      Brando.Videos.Helpers.thumbnail_url(assigns.video) ||
        Brando.Videos.Helpers.derive_external_thumbnail_url(assigns.video)

    assigns = assign(assigns, :thumbnail_url, thumbnail_url)

    ~H"""
    <div
      class="video-preview"
      phx-click={JS.push("play_video", target: @myself) |> show_modal("#video-player-modal")}
      phx-value-video-id={@video.id}
      phx-value-source-url={@video.source_url}
      phx-value-type={@video.type}
    >
      <%= cond do %>
        <% @video.thumbnail -> %>
          <Content.image image={@video.thumbnail} size={:smallest} />
        <% @thumbnail_url -> %>
          <img src={@thumbnail_url} loading="lazy" />
        <% @video.type == :upload && @video.file -> %>
          <video preload="metadata" muted src={Brando.Utils.media_url(@video.file)} />
        <% @video.type == :external_file && @video.source_url && !String.ends_with?(@video.source_url, ".m3u8") -> %>
          <video preload="metadata" muted src={@video.source_url} />
        <% true -> %>
          <.video_placeholder />
      <% end %>
    </div>
    """
  end

  defp video_placeholder(assigns) do
    ~H"""
    <div class="img-placeholder">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="100" height="100">
        <path fill="none" d="M0 0h24v24H0z" /><path d="M3 3.993C3 3.445 3.445 3 3.993 3h16.014c.548 0 .993.445.993.993v16.014a.994.994 0 0 1-.993.993H3.993A.994.994 0 0 1 3 20.007V3.993zM5 5v14h14V5H5zm5.622 3.415l4.879 3.252a.4.4 0 0 1 0 .666l-4.88 3.252a.4.4 0 0 1-.621-.332V8.747a.4.4 0 0 1 .622-.332z" />
      </svg>
    </div>
    """
  end

  # -- Private helpers --

  defp move_videos_to_folder(ids, folder_id) when is_list(ids) do
    import Ecto.Query
    timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    from(v in Brando.Videos.Video, where: v.id in ^ids)
    |> Brando.Repo.update_all(set: [folder_id: folder_id, updated_at: timestamp])
  end

  def show_grid(js \\ %JS{}, id) do
    js
    |> JS.add_class("grid", to: "#video-picker-drawer-#{id}")
    |> JS.remove_class("list", to: "#video-picker-drawer-#{id}")
    |> JS.add_class("is-active", to: "##{id}-view-grid")
    |> JS.remove_class("is-active", to: "##{id}-view-list")
  end

  def show_list(js \\ %JS{}, id) do
    js
    |> JS.add_class("list", to: "#video-picker-drawer-#{id}")
    |> JS.remove_class("grid", to: "#video-picker-drawer-#{id}")
    |> JS.add_class("is-active", to: "##{id}-view-list")
    |> JS.remove_class("is-active", to: "##{id}-view-grid")
  end

  defp get_embed_url(%{type: :youtube, source_url: source_url}) do
    cond do
      String.contains?(source_url, "watch?v=") ->
        String.replace(source_url, "watch?v=", "embed/") <> "?autoplay=1"

      String.contains?(source_url, "youtu.be/") ->
        video_id = source_url |> String.split("/") |> List.last()
        "https://www.youtube.com/embed/#{video_id}?autoplay=1"

      true ->
        source_url
    end
  end

  defp get_embed_url(%{type: :vimeo, source_url: source_url}) do
    video_id = String.split(source_url, "/") |> List.last()
    "https://player.vimeo.com/video/#{video_id}?autoplay=1"
  end

  defp get_embed_url(%{source_url: source_url}) do
    source_url
  end

  defp get_aspect_ratio(%{width: width, height: height})
       when is_integer(width) and is_integer(height) and width > 0 and height > 0 do
    ratio = height / width * 100
    "#{ratio}%"
  end

  defp get_aspect_ratio(_), do: "56.25%"

  defp fetch_oembed_metadata(provider, url) do
    case Brando.OEmbed.get(provider, url) do
      {:ok, data} ->
        {
          Map.get(data, "title", "#{String.capitalize(provider)} Video"),
          Map.get(data, "description"),
          Map.get(data, "thumbnail_url")
        }

      {:error, _} ->
        {"#{String.capitalize(provider)} Video", nil, nil}
    end
  end

  defp extract_title_from_url(url) do
    URI.parse(url).path
    |> Path.basename()
    |> Path.rootname()
    |> String.replace(~r/[_-]/, " ")
    |> String.trim()
    |> case do
      "" -> "Video"
      title -> title
    end
  end

  defp calculate_aspect_ratio(width, height)
       when is_integer(width) and is_integer(height) and width > 0 and height > 0 do
    ratio = width / height

    cond do
      abs(ratio - 16 / 9) < 0.01 -> "16:9"
      abs(ratio - 4 / 3) < 0.01 -> "4:3"
      abs(ratio - 21 / 9) < 0.01 -> "21:9"
      abs(ratio - 1) < 0.01 -> "1:1"
      abs(ratio - 9 / 16) < 0.01 -> "9:16"
      true -> "#{width}:#{height}"
    end
  end

  defp calculate_aspect_ratio(_, _), do: "16:9"

  defp video_uploader_hook(:mux), do: "Brando.MuxUploader"
  defp video_uploader_hook(:bunny), do: "Brando.BunnyUploader"
  defp video_uploader_hook(:cloudflare), do: "Brando.CloudflareUploader"
  defp video_uploader_hook(_strategy), do: nil

  defp video_upload_root(config_target) do
    resolved_target = normalize_video_config_target(config_target) || "default"

    case Brando.Videos.get_config_for(%{config_target: resolved_target}) do
      {:ok, %{upload_path: upload_path}} ->
        FolderBrowser.normalize_folder(upload_path) || "videos/default"

      _ ->
        "videos/default"
    end
  end

  defp normalize_video_config_target(nil), do: nil
  defp normalize_video_config_target(ct) when is_binary(ct), do: ct

  defp normalize_video_config_target({"video", schema, field}),
    do: "video:#{inspect(schema)}:#{field}"

  defp normalize_video_config_target(_), do: nil
end
