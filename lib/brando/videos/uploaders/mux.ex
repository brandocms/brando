defmodule Brando.Videos.Uploaders.Mux do
  @moduledoc """
  Mux video upload provider implementation.

  Handles direct uploads to Mux using their Direct Upload API.

  ## Configuration

  Add to config.exs:

      config :brando, Brando.Videos.Uploaders.Mux,
        access_token_id: System.get_env("MUX_TOKEN_ID"),
        access_token_secret: System.get_env("MUX_TOKEN_SECRET"),
        webhook_secret: System.get_env("MUX_WEBHOOK_SECRET"),
        delete_remote_on: :on_purge

  ## Configuration Options

  | Option | Values | Default | Description |
  |--------|--------|---------|-------------|
  | `delete_remote_on` | `:on_delete`, `:on_purge`, `false` | `:on_purge` | When to delete from Mux |

  - `:on_delete` - Delete from Mux immediately when soft-deleted in admin
  - `:on_purge` - Delete from Mux when soft-delete expires after 30 days (default)
  - `false` - Never delete from Mux

  ## Mux Documentation
  - Direct Uploads: https://www.mux.com/docs/guides/upload-files-directly
  - Webhooks: https://www.mux.com/docs/core/listen-for-webhooks
  """

  @behaviour Brando.Videos.Uploader

  alias Brando.Videos
  alias Brando.Videos.Uploaders.ReqOptions

  require Logger

  @base_url "https://api.mux.com/video/v1"

  @impl true
  @doc """
  Initiates a Mux direct upload.

  ## Options

  - `:config` - VideoConfig struct containing provider metadata in `config.meta.mux`
  - `:cors_origin` - CORS origin for upload (default: "*")
  - `:playback_policies` - Override config default. Only `["public"]` is
    supported until Brando has a token-signing boundary.
  - `:static_renditions` - Optional current Mux static rendition settings
  - `:max_resolution_tier` - Override config default. Mux accepts `"1080p"`,
    `"1440p"` or `"2160p"` only
  - `:video_quality` - `"basic"`, `"plus"` or `"premium"`. No Brando default;
    Mux falls back to the organization default when unset

  ## Configuration via meta

  Provider-specific settings can be configured via `config.meta.mux`:

      asset :video, :video,
        cfg: %{
          meta: %{
            mux: %{
              "max_resolution_tier" => "1080p",
              "video_quality" => "basic",
              "playback_policies" => ["public"],
              "static_renditions" => [%{"resolution" => "highest"}]
            }
          }
        }

  The `meta.mux` map is merged into Mux's `new_asset_settings` verbatim, so any
  setting the Mux asset API accepts can be passed there, not just the keys with
  a matching option above. Only `"playback_policies"` is validated by Brando;
  everything else fails at upload time with a Mux API error.

  See `Brando.Type.VideoConfig` for the full list of settings.

  Settings priority: direct opts > config.meta.mux > uploader defaults
  """
  def initiate_upload(filename, user, opts \\ []) do
    # Validate and sanitize filename
    sanitized_filename = sanitize_filename(filename)

    with {:ok, upload_data} <- create_direct_upload(opts),
         {:ok, video} <- create_video_record(sanitized_filename, user, upload_data, opts) do
      {:ok,
       %{
         upload_url: upload_data["url"],
         video: video,
         expires_at: parse_timeout(upload_data["timeout"])
       }}
    end
  end

  @impl true
  def complete_upload(video, %{"asset_id" => asset_id} = _provider_data) do
    with {:ok, asset} <- get_asset(asset_id) do
      update_video_with_asset(video, asset)
    end
  end

  def complete_upload(_video, _provider_data) do
    {:error, :missing_asset_id}
  end

  @impl true
  def handle_webhook(%{"type" => "video.upload.asset_created", "data" => data})
      when is_map(data) do
    with upload_id when is_binary(upload_id) <- data["id"],
         asset_id when is_binary(asset_id) <- data["asset_id"],
         {:ok, video} <- find_video_by_upload_id(upload_id) do
      complete_upload(video, %{"asset_id" => asset_id})
    else
      nil ->
        Logger.warning("Missing required fields in video.upload.asset_created webhook")
        {:error, :invalid_webhook_data}

      {:error, _} = error ->
        Logger.warning("Could not find video for upload_id in webhook")
        error
    end
  end

  def handle_webhook(%{"type" => "video.asset.ready", "data" => data}) when is_map(data) do
    with asset_id when is_binary(asset_id) <- data["id"],
         {:ok, video} <- find_video_by_asset_id(asset_id) do
      # Update video with complete asset data from the webhook
      update_video_with_asset(video, data)
    else
      nil ->
        Logger.warning("Missing asset_id in video.asset.ready webhook")
        {:error, :invalid_webhook_data}

      {:error, _} = error ->
        Logger.warning("Could not find video for asset_id in webhook")
        error
    end
  end

  def handle_webhook(%{"type" => "video.asset.errored", "data" => data}) when is_map(data) do
    with asset_id when is_binary(asset_id) <- data["id"],
         {:ok, video} <- find_video_by_asset_id(asset_id) do
      update_video_status(video, :errored)
    else
      nil ->
        Logger.warning("Missing asset_id in video.asset.errored webhook")
        {:error, :invalid_webhook_data}

      {:error, _} = error ->
        Logger.warning("Could not find video for asset_id in webhook")
        error
    end
  end

  def handle_webhook(%{"type" => "video.upload.cancelled", "data" => data}) when is_map(data) do
    with upload_id when is_binary(upload_id) <- data["id"],
         {:ok, video} <- find_video_by_upload_id(upload_id) do
      update_video_status(video, :errored)
    else
      nil ->
        Logger.warning("Missing upload_id in video.upload.cancelled webhook")
        {:error, :invalid_webhook_data}

      {:error, _} = error ->
        Logger.warning("Could not find video for upload_id in webhook")
        error
    end
  end

  def handle_webhook(%{"type" => "video.upload.errored", "data" => data}) when is_map(data) do
    with upload_id when is_binary(upload_id) <- data["id"],
         {:ok, video} <- find_video_by_upload_id(upload_id) do
      update_video_status(video, :errored)
    else
      nil ->
        Logger.warning("Missing upload_id in video.upload.errored webhook")
        {:error, :invalid_webhook_data}

      {:error, _} = error ->
        Logger.warning("Could not find video for upload_id in webhook")
        error
    end
  end

  def handle_webhook(payload) do
    event_type = Map.get(payload, "type", "unknown")
    Logger.debug("Ignoring Mux webhook event: #{event_type}")
    Logger.debug("Full payload: #{inspect(payload, pretty: true)}")
    :ignore
  end

  @impl true
  def delete_remote(%Videos.Video{meta: %{"mux" => %{"asset_id" => asset_id}}})
      when is_binary(asset_id) do
    # Validate asset_id before making API call
    if valid_mux_id?(asset_id) do
      case api_request(:delete, "/assets/#{asset_id}") do
        {:ok, _} ->
          :ok

        {:error, %{"error" => %{"type" => "not_found"}}} ->
          # Asset already deleted or doesn't exist
          :ok

        {:error, reason} ->
          Logger.error("Failed to delete Mux asset #{asset_id}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.error("Invalid Mux asset_id in video meta: #{inspect(asset_id)}")
      {:error, :invalid_asset_id}
    end
  end

  def delete_remote(_video) do
    # No asset_id in meta, nothing to delete
    :ok
  end

  @impl true
  @doc """
  Get the HLS playback URL for a Mux video.

  Returns an HLS manifest URL (.m3u8) that contains all available quality renditions.
  The video player will automatically handle adaptive bitrate streaming.

  ## Options

  - `:max_resolution` - Limit maximum quality ("480p", "720p", "1080p", "1440p", "2160p")
  - `:min_resolution` - Set minimum quality (same values as max_resolution)
  - `:rendition_order` - "desc" (higher quality first, default) or "asc" (lower quality first)

  ## Examples

      # Default - all qualities available
      get_playback_url(video)
      # => {:ok, "https://stream.mux.com/abc123.m3u8"}

      # Limit to 720p max (saves bandwidth)
      get_playback_url(video, max_resolution: "720p")
      # => {:ok, "https://stream.mux.com/abc123.m3u8?max_resolution=720p"}

      # Start with lower quality and cap at 720p
      get_playback_url(video, max_resolution: "720p", rendition_order: "asc")
      # => {:ok, "https://stream.mux.com/abc123.m3u8?max_resolution=720p&rendition_order=asc"}

  Note: Quality restrictions are applied at playback time without re-encoding.
  The video is already transcoded to multiple qualities by Mux.
  """
  def get_playback_url(video, opts \\ [])

  def get_playback_url(
        %Videos.Video{meta: %{"mux" => %{"playback_policy" => "signed"}}},
        _opts
      ) do
    {:error, :signed_playback_not_supported}
  end

  def get_playback_url(
        %Videos.Video{
          meta: %{"mux" => %{"playback_id" => playback_id}},
          status: :ready
        },
        opts
      ) do
    base_url = "https://stream.mux.com/#{playback_id}.m3u8"
    url = build_playback_url(base_url, opts)
    {:ok, url}
  end

  def get_playback_url(%Videos.Video{status: status}, _opts) when status != :ready do
    {:error, :video_not_ready}
  end

  def get_playback_url(_video, _opts) do
    {:error, :missing_playback_id}
  end

  defp build_playback_url(base_url, []), do: base_url

  defp build_playback_url(base_url, opts) do
    params =
      opts
      |> Enum.filter(fn {key, _} -> key in [:max_resolution, :min_resolution, :rendition_order] end)
      |> Enum.map_join("&", fn {key, value} -> "#{key}=#{value}" end)

    if params == "" do
      base_url
    else
      "#{base_url}?#{params}"
    end
  end

  # Private helper functions

  defp create_direct_upload(opts) do
    with {:ok, new_asset_settings} <- build_asset_settings(opts) do
      body = %{
        "cors_origin" => Keyword.get(opts, :cors_origin, "*"),
        "new_asset_settings" => new_asset_settings
      }

      case api_request(:post, "/uploads", body) do
        {:ok, %{"data" => data}} -> {:ok, data}
        error -> error
      end
    end
  end

  @doc false
  def build_asset_settings(opts) do
    defaults = %{
      "playback_policies" => ["public"],
      "max_resolution_tier" => "1080p"
    }

    config_meta =
      case Keyword.get(opts, :config) do
        %{meta: %{mux: mux_settings}} when is_map(mux_settings) -> mux_settings
        %{meta: %{"mux" => mux_settings}} when is_map(mux_settings) -> mux_settings
        _ -> %{}
      end

    direct_opts =
      opts
      |> Keyword.take([
        :playback_policies,
        :static_renditions,
        :max_resolution_tier,
        :video_quality,
        :playback_policy,
        :mp4_support
      ])
      |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)

    settings =
      defaults
      |> Map.merge(config_meta |> stringify_keys() |> normalize_deprecated_settings())
      |> Map.merge(normalize_deprecated_settings(direct_opts))
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    case Map.get(settings, "playback_policies") do
      ["public"] -> {:ok, settings}
      ["signed"] -> {:error, :signed_playback_not_supported}
      policies -> {:error, {:invalid_playback_policies, policies}}
    end
  end

  defp stringify_keys(settings) do
    Map.new(settings, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      entry -> entry
    end)
  end

  defp normalize_deprecated_settings(settings) do
    settings =
      case {Map.get(settings, "playback_policy"), Map.has_key?(settings, "playback_policies")} do
        {legacy_policy, false} when is_list(legacy_policy) ->
          Map.put(settings, "playback_policies", legacy_policy)

        _ ->
          settings
      end

    settings =
      case {Map.get(settings, "mp4_support"), Map.has_key?(settings, "static_renditions")} do
        {"standard", false} ->
          Map.put(settings, "static_renditions", [%{"resolution" => "highest"}])

        _ ->
          settings
      end

    Map.drop(settings, ["playback_policy", "mp4_support"])
  end

  defp get_asset(asset_id) do
    # Validate asset_id to prevent path injection
    if valid_mux_id?(asset_id) do
      case api_request(:get, "/assets/#{asset_id}") do
        {:ok, %{"data" => data}} -> {:ok, data}
        error -> error
      end
    else
      Logger.error("Invalid Mux asset_id format: #{inspect(asset_id)}")
      {:error, :invalid_asset_id}
    end
  end

  defp create_video_record(filename, user, upload_data, opts) do
    # Humanize filename for title (e.g., "my_video_file.mp4" -> "My video file")
    title =
      filename
      |> Path.rootname()
      |> Brando.Utils.humanize()

    params = %{
      type: :mux,
      status: :uploading,
      title: title,
      meta: %{
        "provider" => "mux",
        "mux" => %{
          "upload_id" => upload_data["id"]
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

  defp update_video_with_asset(video, asset) do
    {playback_id, playback_policy} = playback_info(asset)

    params =
      %{
        meta: mux_meta(video, asset, playback_id, playback_policy),
        status: video_status(asset["status"])
      }
      |> put_video_dimensions(asset["tracks"])
      |> put_aspect_ratio(asset["aspect_ratio"])
      |> put_duration(asset["duration"])

    {:ok, creator} = Brando.Users.get_user(video.creator_id)

    with {:ok, updated_video} <- Videos.update_video(video, params, creator) do
      Videos.run_completed_callback_on_ready(video, updated_video, creator)
      broadcast_video_update(updated_video)
      {:ok, updated_video}
    end
  end

  defp playback_info(%{"playback_ids" => playback_ids}) when is_list(playback_ids) do
    playback =
      Enum.find(playback_ids, &(&1["policy"] in [nil, "public"])) ||
        List.first(playback_ids)

    case playback do
      %{"id" => id} when is_binary(id) -> {id, Map.get(playback, "policy", "public")}
      _ -> {nil, nil}
    end
  end

  defp playback_info(asset) do
    Logger.warning("Mux asset #{asset["id"]} has no playback_id")
    {nil, nil}
  end

  defp mux_meta(video, asset, playback_id, playback_policy) do
    mux_meta =
      %{
        "upload_id" => get_in(video.meta, ["mux", "upload_id"]),
        "asset_id" => asset["id"]
      }
      |> maybe_put("playback_id", playback_id)
      |> maybe_put("playback_policy", playback_policy)
      |> maybe_put("duration", asset["duration"])
      |> maybe_put("max_resolution", asset["max_resolution_tier"])
      |> maybe_put("aspect_ratio", asset["aspect_ratio"])
      |> maybe_put("status", asset["status"])

    video.meta
    |> Map.put("provider", "mux")
    |> Map.put("mux", mux_meta)
  end

  defp video_status("ready"), do: :ready
  defp video_status("errored"), do: :errored
  defp video_status(_), do: :processing

  defp put_video_dimensions(params, tracks) when is_list(tracks) do
    case Enum.find(tracks, &(&1["type"] == "video")) do
      %{"max_width" => width, "max_height" => height}
      when is_integer(width) and is_integer(height) ->
        Map.merge(params, %{height: height, width: width})

      _ ->
        params
    end
  end

  defp put_video_dimensions(params, _tracks), do: params

  defp put_aspect_ratio(params, aspect_ratio) when is_binary(aspect_ratio) do
    Map.put(params, :aspect_ratio, String.replace(aspect_ratio, ":", "/"))
  end

  defp put_aspect_ratio(params, _aspect_ratio), do: params

  defp put_duration(params, duration) when is_number(duration) do
    Map.put(params, :duration, Videos.Helpers.format_duration(duration))
  end

  defp put_duration(params, _duration), do: params

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp update_video_status(video, status) do
    {:ok, creator} = Brando.Users.get_user(video.creator_id)

    with {:ok, updated_video} <- Videos.update_video(video, %{status: status}, creator) do
      Videos.run_completed_callback_on_ready(video, updated_video, creator)
      broadcast_video_update(updated_video)
      {:ok, updated_video}
    end
  end

  defp broadcast_video_update(video) do
    # Broadcast video update event
    # The media_item_id will be provided by the subscriber context
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      "brando:video:#{video.id}",
      {video, [:video, :updated]}
    )
  end

  defp find_video_by_upload_id(upload_id) do
    case Videos.get_video_by_meta("mux.upload_id", upload_id) do
      nil -> {:error, :not_found}
      video -> {:ok, video}
    end
  end

  defp find_video_by_asset_id(asset_id) do
    case Videos.get_video_by_meta("mux.asset_id", asset_id) do
      nil -> {:error, :not_found}
      video -> {:ok, video}
    end
  end

  defp parse_timeout(timeout) when is_integer(timeout) do
    DateTime.utc_now()
    |> DateTime.add(timeout, :second)
  end

  defp parse_timeout(_), do: nil

  @doc """
  Whether this provider has usable credentials.

  Public so `Brando.Uploads.validate_provider_video_intake/2` can pre-flight the
  same condition `api_request/3` raises on. The raise below branches on this
  rather than re-testing, so the validator and the raise cannot answer
  differently — which is the whole reason it exists.
  """
  def configured?,
    do: present?(get_config(:access_token_id)) and present?(get_config(:access_token_secret))

  # An empty string is not a credential, and all three providers agree on that.
  # A truthiness check does not: it lets `access_token_id: ""` through, and the
  # request goes out to the live API with an empty Basic auth header instead of
  # the site being told its config is wrong.
  defp present?(value), do: is_binary(value) and value != ""

  defp api_request(method, path, body \\ nil) do
    url = @base_url <> path

    # Missing credentials are a deploy-time configuration error, not a runtime
    # condition, so this raises rather than returning an error tuple — as Bunny
    # and Cloudflare do, so one caller branch handles all three.
    #
    # Nothing on the admin upload path should reach it:
    # `Brando.Uploads.validate_provider_video_intake/2` checks `configured?/0`
    # during pre-flight validation. If this raise ever fires from a LiveView,
    # that validator has a gap — the exception costs an editor their unsaved
    # work, which is why the check belongs there and this is only the
    # last-resort invariant guard.
    unless configured?() do
      raise """
      Mux credentials not configured. Please add to your config:

          config :brando, Brando.Videos.Uploaders.Mux,
            access_token_id: System.get_env("MUX_TOKEN_ID"),
            access_token_secret: System.get_env("MUX_TOKEN_SECRET")
      """
    end

    token_id = get_config(:access_token_id)
    token_secret = get_config(:access_token_secret)

    auth = Base.encode64("#{token_id}:#{token_secret}")

    headers = [
      {"authorization", "Basic #{auth}"},
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

    request_opts = ReqOptions.merge(__MODULE__, request_opts)

    case Req.request(request_opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Mux API request failed: #{status} - #{inspect(body)}")
        {:error, body}

      {:error, reason} ->
        Logger.error("Mux API request error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_config(key) do
    :brando
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key)
  end

  # Sanitize filename to prevent injection and ensure safe storage
  defp sanitize_filename(filename) when is_binary(filename) do
    filename
    |> String.trim()
    |> String.slice(0, 255)
    # Remove any null bytes or control characters
    |> String.replace(~r/[\x00-\x1F\x7F]/, "")
  end

  defp sanitize_filename(_), do: "untitled"

  # Validate Mux IDs to prevent path traversal/injection
  # Mux IDs are alphanumeric with underscores and hyphens
  defp valid_mux_id?(id) when is_binary(id) do
    String.match?(id, ~r/^[a-zA-Z0-9_-]+$/) and byte_size(id) < 256
  end

  defp valid_mux_id?(_), do: false
end
