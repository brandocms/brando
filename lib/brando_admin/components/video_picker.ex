defmodule BrandoAdmin.Components.VideoPicker do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content

  def mount(socket) do
    {:ok,
     socket
     |> assign_new(:z_index, fn -> 1100 end)
     |> assign_new(:show_url_input, fn -> false end)
     |> assign_new(:url_input, fn -> "" end)
     |> assign_new(:creating_video, fn -> false end)
     |> assign_new(:playing_video, fn -> nil end)}
  end

  def update(
        %{config_target: config_target, event_target: event_target, multi: multi, selected_videos: selected_videos} =
          assigns,
        socket
      ) do
    {:ok,
     socket
     |> assign(:config_target, config_target)
     |> assign(:event_target, event_target)
     |> assign(:multi, multi)
     |> assign(:selected_videos, selected_videos)
     |> assign(:upload_strategy, assigns[:upload_strategy] || :local)
     |> assign_new(:current_user, fn -> assigns[:current_user] end)
     |> assign_new(:upload_progress, fn -> nil end)
     |> assign_videos()}
  end

  def update(%{selected_videos: selected_videos}, socket) do
    {:ok, assign(socket, :selected_videos, selected_videos)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:multi, fn -> false end)
     |> assign_new(:videos, fn -> [] end)
     |> assign_new(:config_target, fn -> nil end)
     |> assign_new(:event_target, fn -> nil end)
     |> assign_new(:current_user, fn -> nil end)
     |> assign_new(:deselect_video, fn -> nil end)
     |> assign_new(:selected_videos, fn -> [] end)
     |> assign_new(:upload_strategy, fn -> :local end)
     |> assign_new(:upload_progress, fn -> nil end)}
  end

  def assign_videos(socket) do
    {:ok, videos} =
      Brando.Videos.list_videos(%{
        filter: %{config_target: socket.assigns.config_target},
        order: "desc id",
        preload: [:thumbnail]
      })

    assign(socket, :videos, videos)
  end

  def render(assigns) do
    ~H"""
    <div>
      <Content.drawer id={@id} title={gettext("Select video")} close={toggle_drawer("##{@id}")} z={@z_index} dark>
        <:info>
          <%= if @config_target do %>
            <div class="mb-2">
              {gettext("Select similarly typed video from library")}
            </div>
          <% end %>

          <div class="mb-2">
            <button
              type="button"
              class="primary small"
              phx-click={JS.push("toggle_url_input", target: @myself)}
            >
              <%= if @show_url_input do %>
                {gettext("Hide URL input")}
              <% else %>
                {gettext("Create new video from URL")}
              <% end %>
            </button>
          </div>

          <div :if={@show_url_input} class="url-input-wrapper">
            <div
              class="video-url-parser"
              phx-hook="Brando.VideoURLParser"
              data-target={@myself}
              id={"video-url-parser-#{@id}"}
            >
              <div class="field-wrapper">
                <label>{gettext("Video URL")}</label>
                <input
                  type="text"
                  class="text"
                  placeholder={gettext("Paste YouTube, Vimeo or direct video URL")}
                />
                <button type="button" class="secondary small mt-1">
                  <%= if @creating_video do %>
                    {gettext("Creating...")}
                  <% else %>
                    {gettext("Create video")}
                  <% end %>
                </button>
                <div class="video-loading hidden">
                  <div class="spinner"></div>
                  {gettext("Analyzing video...")}
                </div>
              </div>
            </div>
          </div>

          <div :if={@upload_strategy != :local} class="file-upload-wrapper mt-2">
            <div class="mb-1">
              <strong>{gettext("Or upload a video file directly:")}</strong>
            </div>
            <div
              phx-hook={video_uploader_hook(@upload_strategy)}
              id={"video-uploader-#{@id}"}
              data-target={@myself}
            >
              <input type="file" accept="video/*" class="file-input" />
              <div :if={@upload_progress} class="upload-progress mt-1">
                <div class="progress-bar">
                  <div class="progress-fill" style={"width: #{@upload_progress.percentage}%"}></div>
                </div>
                <span class="progress-text">
                  {gettext("Uploading...")} {@upload_progress.percentage}%
                  ({@upload_progress.uploaded_mb}/{@upload_progress.total_mb} MB)
                </span>
              </div>
            </div>
          </div>
        </:info>

        <div class="video-picker list" id={"video-picker-drawer-#{@id}"}>
          <%= for video <- @videos do %>
            <.video_row
              video={video}
              selected_videos={@selected_videos}
              multi={@multi}
              event_target={@event_target}
              myself={@myself}
            />
          <% end %>
        </div>
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
                >
                </iframe>
              <% :vimeo -> %>
                <iframe
                  id={"vimeo-player-#{@playing_video.unique_id}"}
                  src={get_embed_url(@playing_video)}
                  frameborder="0"
                  allow="autoplay; fullscreen; picture-in-picture"
                  allowfullscreen
                  class="video-embed"
                >
                </iframe>
              <% :external_file -> %>
                <video id={"video-player-#{@playing_video.unique_id}"} controls autoplay class="video-embed">
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

  def handle_event("toggle_url_input", _, socket) do
    {:noreply, assign(socket, :show_url_input, !socket.assigns.show_url_input)}
  end

  def handle_event("play_video", %{"video-id" => video_id, "source-url" => source_url, "type" => type}, socket) do
    # Find the video in our list to get its dimensions
    video_data = Enum.find(socket.assigns.videos, &(&1.id == String.to_integer(video_id)))

    video = %{
      id: video_id,
      source_url: source_url,
      type: String.to_atom(type),
      unique_id: System.unique_integer([:positive]),
      width: video_data && video_data.width,
      height: video_data && video_data.height
    }

    {:noreply, assign(socket, :playing_video, video)}
  end

  def handle_event("close_video_player", _, socket) do
    {:noreply, assign(socket, :playing_video, nil)}
  end

  def handle_event("url", params, socket) do
    # This event comes from the JavaScript VideoURLParser hook
    %{
      "width" => width,
      "height" => height,
      "source" => source,
      "remoteId" => remote_id,
      "url" => url
    } = params

    # Map JS source types to our video types
    video_type =
      case source do
        "vimeo" -> :vimeo
        "youtube" -> :youtube
        "file" -> :external_file
        _ -> :external_file
      end

    # Fetch oEmbed metadata for YouTube/Vimeo
    {title, description, _thumbnail_url} =
      case video_type do
        :youtube -> fetch_oembed_metadata("youtube", url)
        :vimeo -> fetch_oembed_metadata("vimeo", url)
        _ -> {extract_title_from_url(url), nil, nil}
      end

    # Build video parameters from hook data + oEmbed
    video_params = %{
      type: video_type,
      source_url: url,
      remote_id: remote_id,
      width: width,
      height: height,
      title: title,
      caption: description,
      aspect_ratio: calculate_aspect_ratio(width, height)
    }

    # Create a changeset for the video (don't save yet - like gallery objects)
    video_changeset = Ecto.Changeset.change(%Brando.Videos.Video{}, video_params)

    case Ecto.Changeset.apply_action(video_changeset, :insert) do
      {:ok, video_struct} ->
        # Send the video data to the target component
        send_update(socket.assigns.event_target, %{
          event: "video_created_from_url",
          video_data: Map.from_struct(video_struct),
          video_changeset: video_changeset
        })

        {:noreply,
         socket
         |> assign(:creating_video, false)
         |> assign(:show_url_input, false)}

      {:error, changeset} ->
        error_msg =
          changeset.errors
          |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
          |> Enum.join(", ")

        IO.puts("Video changeset error: #{error_msg}")
        {:noreply, assign(socket, :creating_video, false)}
    end
  end

  # Video file upload handlers (for Mux, Cloudflare, etc.)

  def handle_event("get_video_upload_url", %{"filename" => filename}, socket) do
    strategy = socket.assigns.upload_strategy
    user = socket.assigns.current_user

    # Create a config struct with the upload strategy from global config
    video_config = %Brando.Type.VideoConfig{
      upload_strategy: strategy
    }

    case Brando.Videos.Uploader.initiate_upload(filename, user,
           config: video_config,
           config_target: "default"
         ) do
      {:ok, %{upload_url: upload_url, video: video} = result} ->
        # Build event payload - include tus_auth for Bunny uploads
        event_payload = %{
          upload_url: upload_url,
          video_id: video.id,
          filename: filename
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
           filename: filename
         })}
    end
  end

  def handle_event("video_upload_complete", %{"video_id" => video_id}, socket) do
    case Brando.Videos.get_video(%{matches: %{id: video_id}, preload: [:thumbnail]}) do
      {:ok, _video} ->
        # Send to parent component to select the uploaded video
        send_update(socket.assigns.event_target, %{
          event: "select_video",
          id: video_id
        })

        {:noreply,
         socket
         |> assign(:upload_progress, nil)
         |> assign_videos()}

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
    IO.puts("Video upload error for #{filename}: #{error}")
    {:noreply, assign(socket, :upload_progress, nil)}
  end

  # Helper functions

  defp get_embed_url(%{type: :youtube, source_url: source_url}) do
    # Convert YouTube URL to embed format with autoplay
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
    # Calculate aspect ratio as percentage for CSS padding-bottom
    ratio = height / width * 100
    "#{ratio}%"
  end

  # Default 16:9 aspect ratio
  defp get_aspect_ratio(_), do: "56.25%"

  # Function components

  attr :video, :map, required: true
  attr :selected_videos, :list, required: true
  attr :multi, :boolean, required: true
  attr :event_target, :any, required: true
  attr :myself, :any, required: true

  def video_row(assigns) do
    ~H"""
    <div class={["video-picker__video", @video.id in @selected_videos && "selected"]}>
      <.video_preview video={@video} myself={@myself} />
      <.video_info
        video={@video}
        selected_videos={@selected_videos}
        multi={@multi}
        event_target={@event_target}
      />
    </div>
    """
  end

  attr :video, :map, required: true
  attr :myself, :any, required: true

  def video_preview(assigns) do
    ~H"""
    <div
      class="video-preview"
      phx-click={JS.push("play_video", target: @myself) |> show_modal("#video-player-modal")}
      phx-value-video-id={@video.id}
      phx-value-source-url={@video.source_url}
      phx-value-type={@video.type}
    >
      <%= case @video.type do %>
        <% :upload -> %>
          <.video_placeholder />
        <% type when type in [:vimeo, :youtube, :external_file] -> %>
          <%= if @video.thumbnail do %>
            <Content.image image={@video.thumbnail} size={:smallest} />
          <% else %>
            <.video_placeholder />
          <% end %>
        <% _ -> %>
          <.video_placeholder />
      <% end %>
    </div>
    """
  end

  def video_placeholder(assigns) do
    ~H"""
    <div class="img-placeholder">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="100" height="100">
        <path fill="none" d="M0 0h24v24H0z" /><path d="M3 3.993C3 3.445 3.445 3 3.993 3h16.014c.548 0 .993.445.993.993v16.014a.994.994 0 0 1-.993.993H3.993A.994.994 0 0 1 3 20.007V3.993zM5 5v14h14V5H5zm5.622 3.415l4.879 3.252a.4.4 0 0 1 0 .666l-4.88 3.252a.4.4 0 0 1-.621-.332V8.747a.4.4 0 0 1 .622-.332z" />
      </svg>
    </div>
    """
  end

  attr :video, :map, required: true
  attr :selected_videos, :list, required: true
  attr :multi, :boolean, required: true
  attr :event_target, :any, required: true

  def video_info(assigns) do
    ~H"""
    <div
      class="video-info"
      phx-click={
        if @multi,
          do: JS.push("select_video", target: @event_target),
          else: JS.push("select_video", target: @event_target) |> toggle_drawer("#video-picker")
      }
      phx-value-id={@video.id}
      phx-value-selected={(@video.id in @selected_videos && "true") || "false"}
    >
      <div class="video-title">{@video.title || gettext("Untitled")}</div>
      <div class="video-meta">
        Type..........: {@video.type}
      </div>
      <%= if @video.width && @video.height do %>
        <div class="video-meta">
          Dimensions....: {@video.width}&times;{@video.height}
        </div>
      <% end %>
      <%= if @video.source_url do %>
        <div class="video-meta">
          Source........: {@video.source_url}
        </div>
      <% end %>
    </div>
    """
  end

  # Helper functions using existing Brando.OEmbed

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

  defp calculate_aspect_ratio(width, height) when is_integer(width) and is_integer(height) and width > 0 and height > 0 do
    # Calculate common aspect ratios
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

  defp video_uploader_hook(strategy) do
    "Brando.#{strategy |> to_string() |> String.capitalize()}Uploader"
  end
end
