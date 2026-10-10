defmodule BrandoAdmin.Components.VideoPicker do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext
  use BrandoAdmin.Components.PickerHelpers

  alias Brando.Videos.ProviderLibrary
  alias BrandoAdmin.Components.Assets.FileBrowser
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.PickerFolders
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
    {resolved_config, resolved_target} = resolve_video_config(config_target)

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
     # Opened by a field's "Add from URL" with the URL input showing; every
     # other opening starts on the library.
     |> assign(:show_url_input, !!assigns[:show_url_input] && resolved_config.allow_external_urls)
     |> assign(:library, nil)
     |> assign(:video_config, resolved_config)
     |> assign(:new_folder, "")
     |> assign(:show_new_folder_form, false)
     |> assign_new(:current_user, fn -> assigns[:current_user] end)
     |> assign_new(:upload_progress, fn -> nil end)
     |> assign_videos()
     |> assign_folder_state(nil)
     |> assign_video_upload_available()
     |> assign_library_providers()
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
     |> assign_video_upload_available()
     |> assign_library_providers()}
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

  # Provider libraries the editor can add from. Adding an existing provider
  # video is linking an external video, so it follows `allow_external_urls`
  # — which also keeps it out of `config_target: :all` pickers.
  defp assign_library_providers(socket) do
    providers =
      with true <- socket.assigns.allow_external_urls?,
           :ok <- Brando.Authorization.Media.authorize(socket.assigns.current_user, :video) do
        ProviderLibrary.providers()
      else
        _ -> []
      end

    assign(socket, :library_providers, providers)
  end

  # `config_target: :all` browses every video without adding any, for pickers
  # that are not choosing for a field (the AI assistant's attachments).
  defp resolve_video_config(:all) do
    {%{Brando.Type.VideoConfig.default_config() | allow_uploads: false, allow_external_urls: false}, :all}
  end

  defp resolve_video_config(config_target), do: Brando.Uploads.resolve_video_config(config_target)

  defp assign_videos(socket) do
    filter = if socket.assigns.config_target == :all, do: %{}, else: %{config_target: socket.assigns.config_target}

    {:ok, videos} =
      Brando.Videos.list_videos(%{
        filter: filter,
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
    |> assign_new(:library_providers, fn -> [] end)
    |> assign_new(:library, fn -> nil end)
    |> assign_new(:url_input, fn -> "" end)
    |> assign_new(:creating_video, fn -> false end)
    |> assign_new(:url_video_ref, fn -> nil end)
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
      PickerFolders.recent_folders_for_root(socket.assigns.recent_folders, upload_root, &folder_under_root?/2)

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
    {:noreply,
     socket
     |> assign(:show_url_input, !socket.assigns.show_url_input)
     |> assign(:library, nil)}
  end

  def handle_event("open_library", %{"strategy" => strategy}, socket) do
    case Enum.find(socket.assigns.library_providers, &(Atom.to_string(&1.strategy) == strategy)) do
      nil ->
        {:noreply, socket}

      provider ->
        library = %{
          strategy: provider.strategy,
          label: provider.label,
          search?: provider.search?,
          query: "",
          items: [],
          next: nil,
          loading?: false,
          error: nil,
          ref: nil
        }

        {:noreply,
         socket
         |> assign(:show_url_input, false)
         |> assign(:library, library)
         |> load_library_page(nil)}
    end
  end

  def handle_event("close_library", _, socket), do: {:noreply, assign(socket, :library, nil)}

  def handle_event("search_library", %{"query" => query}, %{assigns: %{library: %{} = library}} = socket) do
    {:noreply,
     socket
     |> assign(:library, %{library | query: String.trim(query), items: [], next: nil})
     |> load_library_page(nil)}
  end

  def handle_event("more_library", _, %{assigns: %{library: %{next: next}}} = socket) when not is_nil(next) do
    {:noreply, load_library_page(socket, next)}
  end

  # Synchronous, unlike the listing: it creates a record, and runs under the
  # editor's authorization and tenant context, which an async task would not
  # carry.
  def handle_event("add_from_library", %{"remote-id" => remote_id}, %{assigns: %{library: %{} = library}} = socket) do
    opts = [config_target: normalize_video_config_target(socket.assigns.config_target)]

    case ProviderLibrary.import(library.strategy, remote_id, socket.assigns.current_user, opts) do
      {:ok, video} ->
        # Handed over the way "Add from URL" hands over a new video. A picker
        # opened without a field (nothing to select into) just gains it.
        if target = socket.assigns.event_target do
          send_update(target, %{
            event: "video_created_from_url",
            video_data: Map.from_struct(video),
            video_changeset: Ecto.Changeset.change(video)
          })
        end

        items =
          Enum.map(library.items, fn
            %{remote_id: ^remote_id} = item -> %{item | video_id: video.id}
            item -> item
          end)

        {:noreply,
         socket
         |> assign(:library, %{library | items: items, error: nil})
         |> update(:selected_videos, &Enum.uniq([video.id | &1]))
         |> assign_videos()
         |> assign_folder_state(socket.assigns.current_folder)
         |> push_selection_state()}

      {:error, reason} ->
        {:noreply, assign(socket, :library, %{library | error: library_error(reason, library.label)})}
    end
  end

  def handle_event(event, _params, socket)
      when event in ["search_library", "more_library", "add_from_library"],
      do: {:noreply, socket}

  # From the video drawer, which opens this picker already configured for its
  # field: "Add from URL" shows the URL input, "Select video" hides it.
  def handle_event("set_url_input", %{"show" => show}, socket) do
    {:noreply, assign(socket, :show_url_input, show in [true, "true"] && socket.assigns.allow_external_urls?)}
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
        # No file link (an account without `video_files`): Vimeo's own player.
        _ when video_data.type == :vimeo_account -> {:vimeo, video_data.source_url}
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

    video_type = url_video_type(source)
    ref = make_ref()

    video_params = %{
      type: video_type,
      source_url: url,
      remote_id: url_remote_id(video_type, url, remote_id),
      width: width,
      height: height,
      aspect_ratio: calculate_aspect_ratio(width, height),
      config_target: normalize_video_config_target(socket.assigns.config_target)
    }

    # The title comes from the provider's oEmbed endpoint. Asked from here, a
    # slow provider would hold up the whole editor, so it is asked off the
    # LiveView process.
    {:noreply,
     socket
     |> assign(:creating_video, true)
     |> assign(:url_video_ref, ref)
     |> start_async(
       :url_video,
       Brando.Tenant.capture_context(fn -> {ref, video_params, url_video_metadata(video_type, url)} end)
     )}
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
        # `inspect/1` here pushed the raw term to the browser, so a missing
        # credential surfaced to the editor as `:provider_not_configured`.
        # Same channel as the drawer's, now the same text as well.
        {:noreply,
         push_event(socket, "video_upload_url_error", %{
           error: Brando.Uploads.video_upload_error_message(reason),
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

  def handle_async(:library_page, {:ok, {ref, cursor, result}}, socket) do
    case socket.assigns.library do
      %{ref: ^ref} = library -> {:noreply, assign(socket, :library, apply_library_page(library, cursor, result))}
      # Closed, or superseded by a newer search.
      _ -> {:noreply, socket}
    end
  end

  def handle_async(:library_page, {:exit, _reason}, %{assigns: %{library: %{} = library}} = socket) do
    {:noreply,
     assign(socket, :library, %{library | loading?: false, error: library_error(:provider_error, library.label)})}
  end

  def handle_async(:library_page, _result, socket), do: {:noreply, socket}

  def handle_async(:url_video, {:ok, {ref, video_params, {title, description, _thumbnail_url}}}, socket) do
    case socket.assigns do
      %{url_video_ref: ^ref} -> create_url_video(socket, Map.merge(video_params, %{title: title, caption: description}))
      # Superseded by a newer URL.
      _ -> {:noreply, socket}
    end
  end

  def handle_async(:url_video, {:exit, reason}, socket) do
    require Logger
    Logger.warning("Video from URL failed: #{inspect(reason)}")
    {:noreply, assign(socket, :creating_video, false)}
  end

  defp create_url_video(socket, video_params) do
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

  defp apply_library_page(library, cursor, {:ok, %{items: items, next: next}}) do
    items = if cursor, do: library.items ++ items, else: items
    %{library | items: items, next: next, loading?: false}
  end

  defp apply_library_page(library, _cursor, {:error, reason}),
    do: %{library | loading?: false, error: library_error(reason, library.label)}

  defp load_library_page(socket, cursor) do
    library = socket.assigns.library
    ref = make_ref()
    strategy = library.strategy
    opts = [cursor: cursor, query: library.query]

    socket
    |> assign(:library, %{library | loading?: true, error: nil, ref: ref})
    |> start_async(
      :library_page,
      Brando.Tenant.capture_context(fn -> {ref, cursor, ProviderLibrary.list(strategy, opts)} end)
    )
  end

  # The client parser hands back everything after `vimeo.com/` — including an
  # unlisted video's hash — so a Vimeo id is taken from the URL instead.
  defp url_remote_id(:vimeo, url, remote_id) do
    case Brando.Videos.VimeoURL.parse(url) do
      {:ok, %{id: id}} -> id
      :error -> remote_id
    end
  end

  defp url_remote_id(_video_type, _url, remote_id), do: remote_id

  defp library_error(:signed_playback_not_supported, _provider),
    do: gettext("This video needs signed playback, which Brando does not support.")

  defp library_error(:not_found, provider), do: gettext("%{provider} no longer has this video.", provider: provider)

  defp library_error(reason, _provider) when is_binary(reason), do: reason

  defp library_error(_reason, provider),
    do: gettext("Could not reach %{provider}. Try again in a moment.", provider: provider)

  defp library_item_meta(item) do
    [
      library_duration(item.duration),
      item.width && item.height && "#{item.width} × #{item.height}",
      is_binary(item.created_at) && String.slice(item.created_at, 0, 10)
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" · ")
  end

  defp library_duration(seconds) when is_number(seconds) and seconds > 0 do
    total = round(seconds)
    minutes = div(total, 60)
    "#{minutes}:#{total |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp library_duration(_seconds), do: nil

  defp library_status(%{status: :processing}), do: gettext("Processing")
  defp library_status(%{status: :errored}), do: gettext("Failed")
  defp library_status(_item), do: gettext("Signed playback")

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
        workspace
        icon="film"
        subtitle={gettext("Select a video from your library.")}
      >
        <:info>
          <.live_component
            module={FileBrowser}
            id={"#{@id}-top"}
            section={:top}
            mode={:drawer}
            root_name={gettext("Videos")}
            target={@myself}
            upload_root={@upload_root}
            current_folder={@current_folder}
            breadcrumbs={@breadcrumbs}
            recent_folders={@recent_folders_for_root}
          >
            <:toolbar_actions>
              <div class="image-picker-view-toggle">
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
            <div class="image-picker-main-header">
              <h3>{if @current_folder == "", do: gettext("Root folder"), else: Path.basename(@current_folder)}</h3>
              <div class="image-picker-main-actions">
                <span>
                  {ngettext("%{count} video", "%{count} videos", @video_count, count: @video_count)}
                </span>
                <div class="video-picker-add-actions">
                  <button
                    :if={@allow_external_urls?}
                    type="button"
                    class="video-picker-add-btn"
                    phx-click={JS.push("toggle_url_input", target: @myself)}
                  >
                    <.icon name="link" />
                    <%= if @show_url_input do %>
                      {gettext("Hide URL input")}
                    <% else %>
                      {gettext("Add from URL")}
                    <% end %>
                  </button>

                  <button
                    :for={provider <- @library_providers}
                    type="button"
                    class="video-picker-add-btn"
                    aria-expanded={to_string(@library != nil && @library.strategy == provider.strategy)}
                    aria-controls={"#{@id}-library"}
                    phx-click={JS.push("open_library", value: %{strategy: provider.strategy}, target: @myself)}
                  >
                    <.icon name="cloud-download" />
                    {gettext("Add from %{provider}", provider: provider.label)}
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
                      <.icon name="upload" />
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
                      <.icon name="upload" />
                      {gettext("Upload file")}
                    </button>
                    <input type="file" accept="video/*" class="video-picker-file-input" />
                  </div>
                </div>
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
                  <label for={"#{@id}-source-url"}>{gettext("Video URL")}</label>
                  <input
                    id={"#{@id}-source-url"}
                    type="text"
                    class="text"
                    placeholder={gettext("Paste YouTube, Vimeo or direct video URL")}
                    phx-mounted={JS.focus()}
                  />
                  <button type="button" class="video-picker-add-btn">
                    <%= if @creating_video do %>
                      {gettext("Creating...")}
                    <% else %>
                      {gettext("Create video")}
                    <% end %>
                  </button>
                  <%!-- The hook shows this while it reads the URL; from then on the
                       server keeps it up until the provider has answered. --%>
                  <div class={["video-picker-analyzing", !@creating_video && "hidden"]}>
                    <div class="spinner"></div>
                    <span>{gettext("Analyzing video...")}</span>
                  </div>
                </div>
              </div>
            </div>

            <section
              :if={@library}
              id={"#{@id}-library"}
              class="video-picker-library"
              aria-label={gettext("%{provider} library", provider: @library.label)}
            >
              <div class="video-picker-library-header">
                <div>
                  <h4>{gettext("%{provider} library", provider: @library.label)}</h4>
                  <p>
                    {gettext(
                      "Videos already in your %{provider} account. Deleting one here later leaves it in %{provider}.",
                      provider: @library.label
                    )}
                  </p>
                </div>
                <button
                  type="button"
                  class="video-picker-library-close"
                  aria-label={gettext("Close")}
                  phx-click="close_library"
                  phx-target={@myself}
                >
                  <.icon name="x" />
                </button>
              </div>

              <form
                :if={@library.search?}
                class="video-picker-library-search"
                phx-submit="search_library"
                phx-target={@myself}
              >
                <input
                  id={"#{@id}-library-query"}
                  type="search"
                  name="query"
                  class="text"
                  value={@library.query}
                  aria-label={gettext("Search %{provider}", provider: @library.label)}
                  placeholder={gettext("Search by title")}
                />
                <button type="submit" class="video-picker-add-btn">{gettext("Search")}</button>
              </form>

              <p :if={@library.error} class="video-picker-library-error" role="alert">{@library.error}</p>

              <ul :if={@library.items != []} class="video-picker-library-items">
                <li :for={item <- @library.items} class="video-picker-library-item" data-remote-id={item.remote_id}>
                  <div class="video-picker-library-thumb">
                    <img :if={item.thumbnail_url} src={item.thumbnail_url} alt="" loading="lazy" />
                    <.icon :if={!item.thumbnail_url} name="film" />
                  </div>
                  <div class="video-picker-library-info">
                    <span class="video-picker-library-title">{item.title || gettext("Untitled video")}</span>
                    <span class="video-picker-library-meta">{library_item_meta(item)}</span>
                  </div>
                  <div class="video-picker-library-action">
                    <%= cond do %>
                      <% item.video_id -> %>
                        <span class="video-picker-library-status">{gettext("In library")}</span>
                        <button
                          type="button"
                          class="video-picker-add-btn"
                          phx-click="add_from_library"
                          phx-value-remote-id={item.remote_id}
                          phx-target={@myself}
                        >
                          {gettext("Select")}
                        </button>
                      <% item.playable? -> %>
                        <button
                          type="button"
                          class="video-picker-add-btn"
                          phx-click="add_from_library"
                          phx-value-remote-id={item.remote_id}
                          phx-target={@myself}
                          phx-disable-with={gettext("Adding…")}
                        >
                          {gettext("Add")}
                        </button>
                      <% true -> %>
                        <span class="video-picker-library-status">{library_status(item)}</span>
                    <% end %>
                  </div>
                </li>
              </ul>

              <p :if={@library.loading?} class="video-picker-library-note" role="status">
                {gettext("Loading videos…")}
              </p>
              <p
                :if={!@library.loading? && !@library.error && @library.items == []}
                class="video-picker-library-note"
              >
                <%= if @library.query != "" do %>
                  {gettext("No videos match “%{query}”.", query: @library.query)}
                <% else %>
                  {gettext("No videos in this %{provider} account.", provider: @library.label)}
                <% end %>
              </p>
              <button
                :if={@library.next && !@library.loading?}
                type="button"
                class="image-picker-more"
                phx-click="more_library"
                phx-target={@myself}
              >
                {gettext("Load more")}
              </button>
            </section>

            <div :if={@upload_progress} class="video-picker-upload-progress">
              <div class="progress-bar">
                <div class="progress-fill" style={"width: #{@upload_progress.percentage}%"}></div>
              </div>
              <span class="progress-text">
                {gettext("Uploading...")} {@upload_progress.percentage}%
                ({@upload_progress.uploaded_mb}/{@upload_progress.total_mb} MB)
              </span>
            </div>
          </:main_header>

          <div
            id={"video-picker-drawer-#{@id}"}
            class="video-picker list"
          >
            <%= if @video_count == 0 do %>
              <div class="image-picker-empty">
                <.icon name="film" />
                <h4>{gettext("No videos in this folder")}</h4>
                <p>{gettext("Create a video from URL or choose another folder")}</p>
              </div>
            <% end %>

            <div
              :if={@organize_selected != []}
              class="video-picker-organize-bar"
            >
              <.icon name="maximize-2" />
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
                selected={Enum.any?(@selected_videos, &same_item_id?(&1, video.id))}
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
    <%!-- Rendered as well as pushed, as in the image picker: rows streamed in
    on opening arrive after `video_picker_selection_changed` has run. --%>
    <div
      id={@id}
      class={["video-picker__video", @selected && "selected"]}
      role="button"
      tabindex="0"
      phx-key="Enter"
      phx-keydown={JS.exec("phx-click")}
      data-id={@video.id}
      phx-click={
        if @multi,
          do: JS.push("select_video", target: @event_target),
          else: JS.push("select_video", target: @event_target) |> toggle_drawer("#video-picker")
      }
      phx-value-id={@video.id}
    >
      <span class="video-picker__selected-indicator" aria-hidden="true">
        <.icon name="check" />
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
        <div class="video-picker__meta">{video_type_label(@video.type)}</div>
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
            <.icon name="circle-ellipsis" />
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
                <.icon name="square-pen" />
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
                <.icon name="play" />
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
                <.icon name="trash" />
                {gettext("Delete video")}
              </button>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp video_type_label(:upload), do: gettext("Uploaded file")
  defp video_type_label(:external_file), do: gettext("External file")
  defp video_type_label(:youtube), do: "YouTube"
  defp video_type_label(:vimeo), do: "Vimeo"
  defp video_type_label(:vimeo_account), do: "Vimeo"
  defp video_type_label(type), do: type |> to_string() |> String.capitalize()

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
      <.icon name="film" />
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
      <.icon name="square-play" />
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

  defp get_embed_url(%{type: :vimeo} = video) do
    Brando.Videos.VimeoURL.embed_url(video, autoplay: 1)
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

  defp url_video_type("vimeo"), do: :vimeo
  defp url_video_type("youtube"), do: :youtube
  defp url_video_type(_source), do: :external_file

  defp url_video_metadata(:youtube, url), do: fetch_oembed_metadata("youtube", url)
  defp url_video_metadata(:vimeo, url), do: fetch_oembed_metadata("vimeo", url)
  defp url_video_metadata(_video_type, url), do: {extract_title_from_url(url), nil, nil}

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

  @named_aspect_ratios [{16 / 9, "16:9"}, {4 / 3, "4:3"}, {21 / 9, "21:9"}, {1, "1:1"}, {9 / 16, "9:16"}]

  defp calculate_aspect_ratio(width, height)
       when is_integer(width) and is_integer(height) and width > 0 and height > 0 do
    ratio = width / height

    Enum.find_value(@named_aspect_ratios, "#{width}:#{height}", fn {named_ratio, label} ->
      if abs(ratio - named_ratio) < 0.01, do: label
    end)
  end

  defp calculate_aspect_ratio(_, _), do: "16:9"

  defp video_uploader_hook(:mux), do: "Brando.MuxUploader"
  defp video_uploader_hook(:bunny), do: "Brando.BunnyUploader"
  defp video_uploader_hook(:cloudflare), do: "Brando.CloudflareUploader"
  defp video_uploader_hook(:vimeo), do: "Brando.VimeoUploader"
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

  # Route tuples through the canonical constructor rather than restringifying
  # them here — a second, divergent stringifier is how a provider video ends up
  # with a target the originating picker can't match (see `ConfigTarget`).
  # An unresolvable schema keeps the existing "unknown target" contract below.
  defp normalize_video_config_target({"video", _schema, _field} = target) do
    Brando.Assets.ConfigTarget.serialize(target)
  rescue
    ArgumentError -> nil
  end

  defp normalize_video_config_target(_), do: nil
end
