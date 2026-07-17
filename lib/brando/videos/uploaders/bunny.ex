defmodule Brando.Videos.Uploaders.Bunny do
  @moduledoc """
  Bunny Stream video upload provider implementation.

  Handles direct uploads to Bunny Stream using their TUS resumable upload API.

  ## Configuration

  Add to config.exs:

      config :brando, Brando.Videos.Uploaders.Bunny,
        api_key: System.get_env("BUNNY_API_KEY"),
        library_id: System.get_env("BUNNY_LIBRARY_ID"),
        cdn_hostname: System.get_env("BUNNY_CDN_HOSTNAME"),
        delete_remote_on: :on_purge

  ## Configuration Options

  | Option | Values | Default | Description |
  |--------|--------|---------|-------------|
  | `delete_remote_on` | `:on_delete`, `:on_purge`, `false` | `:on_purge` | When to delete from Bunny |

  - `:on_delete` - Delete from Bunny immediately when soft-deleted in admin
  - `:on_purge` - Delete from Bunny when soft-delete expires after 30 days (default)
  - `false` - Never delete from Bunny

  ## Bunny Documentation
  - Create Video: https://docs.bunny.net/reference/video_createvideo
  - TUS Uploads: https://docs.bunny.net/docs/stream-tus-resumable-uploads
  - Webhooks: https://docs.bunny.net/docs/stream-webhook
  """

  @behaviour Brando.Videos.Uploader

  alias Brando.Videos

  require Logger

  @base_url "https://video.bunnycdn.com"
  @tus_endpoint "https://video.bunnycdn.com/tusupload"

  # Webhook status codes from Bunny
  @status_queued 0
  @status_processing 1
  @status_encoding 2
  @status_finished 3
  @status_resolution_finished 4
  @status_failed 5
  # 6-8 are presigned upload statuses (not used for video state)

  @impl true
  @doc """
  Initiates a Bunny Stream upload.

  Creates a video object in Bunny, then returns TUS upload credentials
  for the client to upload directly.

  ## Options

  - `:config` - VideoConfig struct (required)
  """
  def initiate_upload(filename, user, opts \\ []) do
    sanitized_filename = sanitize_filename(filename)
    title = Path.rootname(sanitized_filename) |> Brando.Utils.humanize()

    with {:ok, bunny_video} <- create_bunny_video(title),
         {:ok, tus_auth} <- generate_tus_auth(bunny_video["guid"]),
         {:ok, video} <- create_video_record(sanitized_filename, user, bunny_video, opts) do
      {:ok,
       %{
         upload_url: @tus_endpoint,
         video: video,
         expires_at: tus_auth.expires_at,
         # Additional data needed by the TUS client
         tus_auth: %{
           signature: tus_auth.signature,
           expire_time: tus_auth.expire_time,
           video_id: bunny_video["guid"],
           library_id: get_config(:library_id)
         }
       }}
    end
  end

  @impl true
  def complete_upload(video, %{"video_guid" => _video_guid} = _provider_data) do
    # For Bunny, the webhook handles completion
    # This is called when TUS upload finishes, but we need to wait for encoding
    {:ok, video}
  end

  def complete_upload(_video, _provider_data) do
    {:error, :missing_video_guid}
  end

  @impl true
  def handle_webhook(%{
        "VideoLibraryId" => library_id,
        "VideoGuid" => video_guid,
        "Status" => status
      }) do
    configured_library_id = get_config(:library_id)

    with true <- to_string(library_id) == to_string(configured_library_id),
         {:ok, video} <- find_video_by_guid(video_guid) do
      process_status_update(video, status)
    else
      false ->
        Logger.warning("Bunny webhook library_id mismatch: #{library_id}")
        {:error, :library_mismatch}

      {:error, :not_found} ->
        Logger.debug("Bunny webhook for unknown video: #{video_guid}")
        :ignore
    end
  end

  def handle_webhook(payload) do
    Logger.debug("Ignoring Bunny webhook: #{inspect(payload, pretty: true)}")
    :ignore
  end

  @impl true
  def delete_remote(%Videos.Video{meta: %{"bunny" => %{"video_guid" => video_guid}}})
      when is_binary(video_guid) do
    library_id = get_config(:library_id)

    if valid_bunny_id?(video_guid) do
      case api_request(:delete, "/library/#{library_id}/videos/#{video_guid}") do
        {:ok, _} ->
          :ok

        {:error, %{"Message" => "Not Found"}} ->
          # Video already deleted
          :ok

        {:error, reason} ->
          Logger.error("Failed to delete Bunny video #{video_guid}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.error("Invalid Bunny video_guid: #{inspect(video_guid)}")
      {:error, :invalid_video_guid}
    end
  end

  def delete_remote(_video) do
    # No video_guid in meta, nothing to delete
    :ok
  end

  @impl true
  @doc """
  Get the HLS playback URL for a Bunny video.

  Returns an HLS manifest URL (.m3u8) for adaptive bitrate streaming.

  ## Examples

      get_playback_url(video)
      # => {:ok, "https://vz-abc123.b-cdn.net/video-guid/playlist.m3u8"}
  """
  def get_playback_url(video, opts \\ [])

  def get_playback_url(
        %Videos.Video{
          meta: %{"bunny" => %{"video_guid" => video_guid}},
          status: :ready
        },
        _opts
      ) do
    cdn_hostname = get_config(:cdn_hostname)

    if cdn_hostname do
      {:ok, "https://#{cdn_hostname}/#{video_guid}/playlist.m3u8"}
    else
      {:error, :cdn_hostname_not_configured}
    end
  end

  def get_playback_url(%Videos.Video{status: status}, _opts) when status != :ready do
    {:error, :video_not_ready}
  end

  def get_playback_url(_video, _opts) do
    {:error, :missing_video_guid}
  end

  @doc """
  Get the embed iframe URL for a Bunny video.
  """
  def get_embed_url(%Videos.Video{meta: %{"bunny" => %{"video_guid" => video_guid}}}) do
    library_id = get_config(:library_id)
    {:ok, "https://iframe.mediadelivery.net/embed/#{library_id}/#{video_guid}"}
  end

  def get_embed_url(_video), do: {:error, :missing_video_guid}

  # Private helper functions

  defp create_bunny_video(title) do
    library_id = get_config(:library_id)

    body = %{
      "title" => title
    }

    api_request(:post, "/library/#{library_id}/videos", body)
  end

  defp generate_tus_auth(video_guid) do
    library_id = get_config(:library_id)
    api_key = get_config(:api_key)

    # Signature expires in 24 hours
    expire_time = System.system_time(:second) + 86_400

    # SHA256(library_id + api_key + expiration_time + video_id)
    data = "#{library_id}#{api_key}#{expire_time}#{video_guid}"

    signature =
      :crypto.hash(:sha256, data)
      |> Base.encode16(case: :lower)

    {:ok,
     %{
       signature: signature,
       expire_time: expire_time,
       expires_at: DateTime.from_unix!(expire_time)
     }}
  end

  defp create_video_record(filename, user, bunny_video, opts) do
    title =
      filename
      |> Path.rootname()
      |> Brando.Utils.humanize()

    params = %{
      type: :bunny,
      status: :uploading,
      title: title,
      meta: %{
        "provider" => "bunny",
        "bunny" => %{
          "video_guid" => bunny_video["guid"],
          "library_id" => bunny_video["videoLibraryId"]
        }
      },
      creator_id: user.id
    }

    # Add config_target if provided
    params =
      case Keyword.get(opts, :config_target) do
        nil -> params
        config_target -> Map.put(params, :config_target, config_target)
      end

    Videos.create_video(params)
  end

  defp process_status_update(video, status) when status in [@status_queued, @status_processing, @status_encoding] do
    update_video_status(video, :processing)
  end

  defp process_status_update(video, @status_finished) do
    # Fetch full video details from Bunny API
    case fetch_video_details(video) do
      {:ok, bunny_video} ->
        update_video_with_details(video, bunny_video)

      {:error, reason} ->
        Logger.error("Failed to fetch Bunny video details: #{inspect(reason)}")
        # Still mark as ready even if we can't get details
        update_video_status(video, :ready)
    end
  end

  defp process_status_update(video, @status_resolution_finished) do
    # A resolution is ready - video is now playable but may still be encoding
    # We could optionally update to :ready here for faster playback
    Logger.debug("Bunny resolution finished for video #{video.id}")
    {:ok, video}
  end

  defp process_status_update(video, @status_failed) do
    update_video_status(video, :errored)
  end

  defp process_status_update(video, status) when status in 6..10 do
    # Presigned upload statuses, captions generated, etc. - just log
    Logger.debug("Bunny status #{status} for video #{video.id}")
    {:ok, video}
  end

  defp process_status_update(video, status) do
    Logger.warning("Unknown Bunny status #{status} for video #{video.id}")
    {:ok, video}
  end

  defp fetch_video_details(%Videos.Video{meta: %{"bunny" => %{"video_guid" => video_guid}}}) do
    library_id = get_config(:library_id)
    api_request(:get, "/library/#{library_id}/videos/#{video_guid}")
  end

  defp update_video_with_details(video, bunny_video) do
    bunny_meta = %{
      "video_guid" => bunny_video["guid"],
      "library_id" => bunny_video["videoLibraryId"],
      "status" => bunny_video["status"],
      "length" => bunny_video["length"],
      "available_resolutions" => bunny_video["availableResolutions"],
      "thumbnail_url" => bunny_video["thumbnailFileName"],
      "width" => bunny_video["width"],
      "height" => bunny_video["height"]
    }

    meta =
      video.meta
      |> Map.put("provider", "bunny")
      |> Map.put("bunny", bunny_meta)

    params = %{
      meta: meta,
      status: :ready
    }

    # Add dimensions if available
    params =
      case {bunny_video["width"], bunny_video["height"]} do
        {width, height} when is_integer(width) and is_integer(height) and width > 0 and height > 0 ->
          params
          |> Map.put(:width, width)
          |> Map.put(:height, height)
          |> Map.put(:aspect_ratio, "#{width}/#{height}")

        _ ->
          params
      end

    # Add duration if available
    params =
      case bunny_video["length"] do
        length when is_number(length) and length > 0 ->
          Map.put(params, :duration, Videos.Helpers.format_duration(length))

        _ ->
          params
      end

    {:ok, creator} = Brando.Users.get_user(video.creator_id)

    with {:ok, updated_video} <- Videos.update_video(video, params, creator) do
      Videos.run_completed_callback_on_ready(video, updated_video, creator)
      broadcast_video_update(updated_video)
      {:ok, updated_video}
    end
  end

  defp update_video_status(video, status) do
    {:ok, creator} = Brando.Users.get_user(video.creator_id)

    with {:ok, updated_video} <- Videos.update_video(video, %{status: status}, creator) do
      Videos.run_completed_callback_on_ready(video, updated_video, creator)
      broadcast_video_update(updated_video)
      {:ok, updated_video}
    end
  end

  defp broadcast_video_update(video) do
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      "brando:video:#{video.id}",
      {video, [:video, :updated]}
    )
  end

  defp find_video_by_guid(video_guid) do
    case Videos.get_video_by_meta("bunny.video_guid", video_guid) do
      nil -> {:error, :not_found}
      video -> {:ok, video}
    end
  end

  defp api_request(method, path, body \\ nil) do
    url = @base_url <> path
    api_key = get_config(:api_key)

    unless api_key do
      raise """
      Bunny credentials not configured. Please add to your config:

          config :brando, Brando.Videos.Uploaders.Bunny,
            api_key: System.get_env("BUNNY_API_KEY"),
            library_id: System.get_env("BUNNY_LIBRARY_ID"),
            cdn_hostname: System.get_env("BUNNY_CDN_HOSTNAME")
      """
    end

    headers = [
      {"AccessKey", api_key},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]

    request_opts =
      case method do
        :get ->
          [method: :get, url: url, headers: headers]

        :post ->
          [method: :post, url: url, headers: headers, json: body]

        :delete ->
          [method: :delete, url: url, headers: headers]
      end

    case Req.request(request_opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Bunny API request failed: #{status} - #{inspect(body)}")
        {:error, body}

      {:error, reason} ->
        Logger.error("Bunny API request error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_config(key) do
    :brando
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key)
  end

  defp sanitize_filename(filename) when is_binary(filename) do
    filename
    |> String.trim()
    |> String.slice(0, 255)
    |> String.replace(~r/[\x00-\x1F\x7F]/, "")
  end

  defp sanitize_filename(_), do: "untitled"

  defp valid_bunny_id?(id) when is_binary(id) do
    # Bunny GUIDs are standard UUIDs
    String.match?(id, ~r/^[a-zA-Z0-9-]+$/) and byte_size(id) < 256
  end

  defp valid_bunny_id?(_), do: false
end
