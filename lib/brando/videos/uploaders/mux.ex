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

  ## Static renditions

  New assets ask Mux for MP4 static renditions at the resolutions in

      config :brando, Brando.Videos, mux_static_renditions: [720, 1080]

  which is the default. Mux makes 270, 360, 480, 540, 720, 1080, 1440 and
  2160, never above the source, and skips the ones that would need upscaling.
  `[]` asks for none, and a video config's `meta.mux["static_renditions"]`
  replaces the list for its uploads. Each rendition costs storage and delivery
  on Mux.

  Brando keeps what Mux reports of them in `meta.mux.static_renditions`, from
  the asset and from the `video.asset.static_rendition.*` webhooks, and
  `Brando.Videos.Playback` offers the ready ones as MP4 qualities. Assets made
  before get the configured renditions from `add_static_renditions/1`
  (`mix brando.videos.mux_renditions`), if they would play one.

  ## Mux Documentation
  - Direct Uploads: https://www.mux.com/docs/guides/upload-files-directly
  - Webhooks: https://www.mux.com/docs/core/listen-for-webhooks
  - Static renditions: https://www.mux.com/docs/guides/enable-static-mp4-renditions
  """

  @behaviour Brando.Videos.Uploader

  import Ecto.Query, only: [from: 2]

  alias Brando.Repo
  alias Brando.Videos
  alias Brando.Videos.Playback
  alias Brando.Videos.Uploaders.ProviderUpdate
  alias Brando.Videos.Uploaders.ReqOptions

  require Logger

  @base_url "https://api.mux.com/video/v1"
  @default_static_renditions [720, 1080]

  @impl true
  @doc """
  Initiates a Mux direct upload.

  ## Options

  - `:config` - VideoConfig struct containing provider metadata in `config.meta.mux`
  - `:cors_origin` - CORS origin for upload (default: "*")
  - `:playback_policies` - Override config default. Only `["public"]` is
    supported until Brando has a token-signing boundary.
  - `:static_renditions` - Mux static rendition settings, replacing the
    configured `mux_static_renditions` (see the moduledoc)
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
              "static_renditions" => [%{"resolution" => "720p"}]
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

  # A webhook names an upload or an asset, not where Brando holds it: each
  # environment of each active site holding it is updated, as the backfill
  # does (`Brando.Tenant.Job.each_active_environment/2`).
  @impl true
  def handle_webhook(%{"type" => "video.upload.asset_created", "data" => data})
      when is_map(data) do
    with upload_id when is_binary(upload_id) <- data["id"],
         asset_id when is_binary(asset_id) <- data["asset_id"] do
      in_each_holder("mux.upload_id", upload_id, &complete_upload(&1, %{"asset_id" => asset_id}))
    else
      nil ->
        Logger.warning("Missing required fields in video.upload.asset_created webhook")
        {:error, :invalid_webhook_data}
    end
  end

  def handle_webhook(%{"type" => "video.asset.ready", "data" => data}) when is_map(data) do
    case data["id"] do
      # Update video with complete asset data from the webhook
      asset_id when is_binary(asset_id) ->
        in_each_holder("mux.asset_id", asset_id, &update_video_with_asset(&1, data))

      nil ->
        Logger.warning("Missing asset_id in video.asset.ready webhook")
        {:error, :invalid_webhook_data}
    end
  end

  # A rendition's event carries the rendition, not the asset, so the asset is
  # read again: it is what Mux has now, whatever order the events arrive in.
  # An asset Brando doesn't hold, or Mux no longer has, is ignored, so Mux
  # doesn't retry the event.
  def handle_webhook(%{"type" => "video.asset.static_rendition." <> event} = payload)
      when event in ["ready", "skipped", "errored", "deleted"] do
    with asset_id when is_binary(asset_id) <- rendition_asset_id(payload),
         [_ | _] = holders <- holders("mux.asset_id", asset_id),
         {:ok, asset} <- get_asset(asset_id) do
      in_each(holders, &store_static_renditions(&1, asset))
    else
      nil ->
        Logger.warning("Missing asset id in video.asset.static_rendition.#{event} webhook")
        {:error, :invalid_webhook_data}

      [] ->
        :ignore

      {:error, %{"error" => %{"type" => "not_found"}}} ->
        :ignore

      {:error, _} = error ->
        error
    end
  end

  def handle_webhook(%{"type" => "video.asset.errored", "data" => data}) when is_map(data) do
    case data["id"] do
      asset_id when is_binary(asset_id) ->
        in_each_holder("mux.asset_id", asset_id, &update_video_status(&1, :errored))

      nil ->
        Logger.warning("Missing asset_id in video.asset.errored webhook")
        {:error, :invalid_webhook_data}
    end
  end

  def handle_webhook(%{"type" => type, "data" => data})
      when type in ["video.upload.cancelled", "video.upload.errored"] and is_map(data) do
    case data["id"] do
      upload_id when is_binary(upload_id) ->
        in_each_holder("mux.upload_id", upload_id, &update_video_status(&1, :errored))

      nil ->
        Logger.warning("Missing upload_id in #{type} webhook")
        {:error, :invalid_webhook_data}
    end
  end

  def handle_webhook(payload) do
    event_type = Map.get(payload, "type", "unknown")
    Logger.debug("Ignoring Mux webhook event: #{event_type}")
    Logger.debug("Full payload: #{inspect(payload, pretty: true)}")
    :ignore
  end

  defp rendition_asset_id(%{"object" => %{"type" => "asset", "id" => asset_id}}) when is_binary(asset_id),
    do: asset_id

  defp rendition_asset_id(%{"data" => %{"asset_id" => asset_id}}) when is_binary(asset_id), do: asset_id
  defp rendition_asset_id(_payload), do: nil

  @impl true
  def delete_remote(%Videos.Video{meta: %{"mux" => %{"asset_id" => asset_id}}})
      when is_binary(asset_id) do
    # Validate asset_id before making API call
    if valid_mux_id?(asset_id) do
      case request(:delete, "/assets/#{asset_id}", nil) do
        {:ok, _} ->
          :ok

        {:error, {:http_error, _status, %{"error" => %{"type" => "not_found"}}}} ->
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
    defaults =
      %{
        "playback_policies" => ["public"],
        "max_resolution_tier" => "1080p"
      }
      |> maybe_put("static_renditions", default_static_renditions())

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

  defp default_static_renditions do
    case static_rendition_resolutions() do
      [] -> nil
      resolutions -> Enum.map(resolutions, &%{"resolution" => "#{&1}p"})
    end
  end

  @doc """
  The static rendition resolutions new assets ask for, and
  `add_static_renditions/1` adds: `config :brando, Brando.Videos,
  mux_static_renditions: [720, 1080]`, the default. Values Mux doesn't make
  are left out.
  """
  @spec static_rendition_resolutions() :: [pos_integer()]
  def static_rendition_resolutions do
    :brando
    |> Application.get_env(Brando.Videos, [])
    |> Keyword.get(:mux_static_renditions, @default_static_renditions)
    |> List.wrap()
    |> Enum.flat_map(&parse_resolution/1)
    |> Enum.filter(&(&1 in Playback.mux_resolutions()))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp parse_resolution(resolution) when is_integer(resolution), do: [resolution]

  defp parse_resolution(resolution) when is_binary(resolution) do
    case Integer.parse(resolution) do
      {height, rest} when rest in ["", "p"] -> [height]
      _ -> []
    end
  end

  defp parse_resolution(_resolution), do: []

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
        # The configured resolutions: Brando plays no `highest`
        {"standard", false} ->
          maybe_put(settings, "static_renditions", default_static_renditions())

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
      creator_id: user.id,
      # The folder the upload was started in (the Videos library's)
      folder_id: Keyword.get(opts, :folder_id)
    }

    # Add config_target if provided
    params =
      case Keyword.get(opts, :config_target) do
        nil -> params
        config_target -> Map.put(params, :config_target, config_target)
      end

    Videos.create_video(params)
  end

  # The row is read again under a lock, as `store_static_renditions/2` does,
  # so a rendition another event stored ready while the asset was read stays
  # ready. A video deleted since is ignored.
  defp update_video_with_asset(video, asset) do
    fn ->
      with %Videos.Video{} = fresh <- lock_video(video.id), do: write_asset(fresh, asset)
    end
    |> Repo.transaction()
    |> case do
      {:ok, nil} -> :ignore
      {:ok, {fresh, updated}} -> {:ok, ProviderUpdate.updated(fresh, updated)}
      {:error, _} = error -> error
    end
  end

  # {the video as it was, the video}
  defp write_asset(video, asset) do
    {playback_id, playback_policy} = playback_info(asset)

    params =
      %{
        meta: mux_meta(video, asset, playback_id, playback_policy),
        status: video_status(asset["status"])
      }
      |> put_video_dimensions(asset["tracks"])
      |> put_aspect_ratio(asset["aspect_ratio"])
      |> put_duration(asset["duration"])

    case Videos.update_video(video, params, :system) do
      {:ok, updated} -> {video, updated}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_video(video_id), do: Repo.one(from(v in Videos.Video, where: v.id == ^video_id, lock: "FOR UPDATE"))

  # Stores what Mux has of the asset's static renditions, and nothing else:
  # the size, shape and duration are the editor's once the video is ready.
  # The row is read again under a lock, so a rendition another event stored
  # ready while the asset was read stays ready. Nothing changed writes
  # nothing, and only a change to what the video can play renders the
  # entries showing it again. A video deleted since is ignored.
  defp store_static_renditions(video, asset) do
    fn -> store_locked(video.id, asset) end
    |> Repo.transaction()
    |> case do
      {:ok, nil} ->
        :ignore

      {:ok, {true, updated}} ->
        Brando.Content.Blocks.render_entries_with_video_id(updated.id)
        ProviderUpdate.broadcast(updated)
        {:ok, updated}

      {:ok, {_playable_changed?, video}} ->
        {:ok, video}

      {:error, _} = error ->
        error
    end
  end

  # {whether what the video can play changed, the video}, or nil without the row
  defp store_locked(video_id, asset) do
    with %Videos.Video{} = fresh <- lock_video(video_id) do
      stored = get_in(fresh.meta, ["mux", "static_renditions"])

      case static_renditions(asset, stored) do
        renditions when renditions in [nil, stored] -> {false, fresh}
        renditions -> put_static_renditions(fresh, renditions)
      end
    end
  end

  defp put_static_renditions(video, renditions) do
    meta =
      Map.update(video.meta, "mux", %{"static_renditions" => renditions}, &Map.put(&1, "static_renditions", renditions))

    case video |> Ecto.Changeset.change(meta: meta) |> Brando.Query.update() do
      {:ok, updated} -> {Playback.mp4_resolutions(updated) != Playback.mp4_resolutions(video), updated}
      {:error, reason} -> Repo.rollback(reason)
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
      |> maybe_put("static_renditions", static_renditions(asset, get_in(video.meta, ["mux", "static_renditions"])))

    video.meta
    |> Map.put("provider", "mux")
    |> Map.put("mux", mux_meta)
  end

  # What Mux has of the asset's static renditions. An asset without any has no
  # `static_renditions`, or no files in it: a ready one has none (its last was
  # deleted), else it is unknown yet. A rendition stored as ready stays ready when an older
  # report still has it preparing: Mux's events don't arrive in order, and a
  # ready rendition never prepares again.
  defp static_renditions(%{"static_renditions" => %{"files" => files}}, stored) when is_list(files) do
    ready_ids =
      for %{"id" => id, "status" => "ready"} <- List.wrap(stored), into: MapSet.new(), do: id

    for %{"resolution" => resolution} = file <- files, is_binary(resolution) do
      status = if file["status"] == "preparing" and file["id"] in ready_ids, do: "ready", else: file["status"]

      %{"id" => file["id"], "resolution" => resolution, "status" => status, "name" => file["name"]}
    end
  end

  defp static_renditions(%{"status" => "ready"}, _stored), do: []
  defp static_renditions(_asset, _stored), do: nil

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

  defp update_video_status(video, status), do: ProviderUpdate.update_video(video, %{status: status})

  # `{prefix, video}` for each environment holding a video with `value` at
  # `meta_path`; the prefix is nil without tenancy
  defp holders(meta_path, value) do
    :all
    |> Brando.Tenant.Job.each_active_environment(fn ->
      case Videos.get_video_by_meta(meta_path, value) do
        nil -> []
        video -> [{Brando.Tenant.current_prefix(), video}]
      end
    end)
    |> List.flatten()
  end

  defp in_each_holder(meta_path, value, fun) do
    case holders(meta_path, value) do
      [] ->
        Logger.warning("Could not find video for #{meta_path} in webhook")
        {:error, :not_found}

      holders ->
        in_each(holders, fun)
    end
  end

  # Runs `fun` on each video in its environment: the last one updated, or
  # the first error
  defp in_each(holders, fun) do
    holders
    |> Enum.map(fn {prefix, video} -> in_environment(prefix, fn -> fun.(video) end) end)
    |> Enum.reduce(fn
      _result, {:error, _} = error -> error
      result, _previous -> result
    end)
  end

  defp in_environment(nil, fun), do: fun.()
  defp in_environment(prefix, fun), do: Brando.Tenant.with_prefix(prefix, fun)

  defp parse_timeout(timeout) when is_integer(timeout) do
    DateTime.utc_now()
    |> DateTime.add(timeout, :second)
  end

  defp parse_timeout(_), do: nil

  @impl true
  def library_meta_path, do: "mux.asset_id"

  # Mux's asset list has no search parameter.
  @impl true
  def library_searchable?, do: false

  @impl true
  def list_remote(opts) do
    page = Keyword.get(opts, :cursor) || 1
    per_page = Keyword.get(opts, :per_page, 24)

    case api_request(:get, "/assets?" <> URI.encode_query(limit: per_page, page: page)) do
      {:ok, %{"data" => assets}} when is_list(assets) ->
        {:ok,
         %{
           items: assets |> Enum.map(&library_item/1) |> Enum.reject(&is_nil/1),
           next: if(length(assets) >= per_page, do: page + 1)
         }}

      {:ok, _body} ->
        {:error, :invalid_response}

      error ->
        error
    end
  end

  @impl true
  def import_remote(asset_id, user, opts) do
    with {:ok, asset} <- get_asset(asset_id),
         :ok <- check_asset_id(asset, asset_id),
         :ok <- check_public_playback(asset),
         {:ok, video} <-
           Videos.create_video(%{
             type: :mux,
             status: :processing,
             title: asset_title(asset),
             config_target: Keyword.get(opts, :config_target),
             folder_id: Keyword.get(opts, :folder_id),
             meta: %{"provider" => "mux", "imported" => true, "mux" => %{"asset_id" => asset_id}},
             creator_id: user.id
           }) do
      update_video_with_asset(video, asset)
    end
  end

  @doc """
  Asks Mux for the configured static renditions
  (`static_rendition_resolutions/0`) on each ready Mux video that would play
  one and lacks them, in every environment of every active site, and stores
  what each asset has in `meta.mux.static_renditions`. Mux makes a rendition
  in the background and reports it ready through the
  `video.asset.static_rendition.ready` webhook, which stores it; until then
  the video streams. Running this again stores what is ready by then, which a
  site without the webhook needs, asks for nothing twice (a rendition Mux
  skipped because the source is smaller counts as there), and picks up videos
  that became loops since.

  A video would play an MP4 when it is shown somewhere as an autoplaying loop
  without controls or a play button under Automatic quality, or has a fixed
  MP4 quality on the video or a placement (`Brando.Videos.Mp4Use`). Videos
  that only stream are skipped, to save Mux storage.

  Mux won't make a resolution beside the `highest` rendition, nor any static
  rendition while an asset's legacy `mp4_support` is on. So before asking, it
  deletes `highest` (Brando never plays it) or turns `mp4_support` off. If
  that fails it asks for nothing on that asset; if a request fails after it,
  the asset has none of its MP4s until this runs again, which the result
  shows (`:clear` and `:failed`).

  Returns a result per video, and logs it, with its `:environment` (the tenant
  prefix, or `"public"`) and:

    * `:skipped` - `:streams` for a video that only streams, else nil
    * `:present` - the resolutions the asset has, ready, preparing or skipped
    * `:clear` - what had to go first, `:highest` or `:mp4_support`: removed,
      or that would be with `dry_run`
    * `:requested` - the resolutions asked for now, or that would be with `dry_run`
    * `:failed` - `{resolution, reason}` for each request Mux refused
    * `:error` - why the asset couldn't be read (or read again and stored
      after the changes above), or `{:clear, step, reason}` when Mux refused
      to remove what had to go, else nil

  ## Options

    * `:dry_run` - read the assets and report, but change nothing on Mux and
      store nothing
    * `:interval` - milliseconds between two changes on Mux, 1000 by
      default: Mux takes about one a second

  `mix brando.videos.mux_renditions` runs it and prints the results. From a
  release, on the running node, see what it would do first:

      bin/my_app rpc 'Brando.Videos.Uploaders.Mux.add_static_renditions(dry_run: true) |> IO.inspect()'
      bin/my_app rpc 'Brando.Videos.Uploaders.Mux.add_static_renditions() |> IO.inspect()'
  """
  @spec add_static_renditions(keyword()) :: [map()]
  def add_static_renditions(opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)
    interval = Keyword.get(opts, :interval, 1_000)
    resolutions = static_rendition_resolutions()

    :all
    |> Brando.Tenant.Job.each_active_environment(fn ->
      environment = Brando.Tenant.current_prefix() || "public"

      resolutions
      |> environment_renditions(dry_run?, interval)
      |> Enum.map(&(&1 |> Map.put(:environment, environment) |> log_result(not dry_run?)))
    end)
    |> List.flatten()
  end

  defp environment_renditions(resolutions, dry_run?, interval) do
    videos =
      from(v in Videos.Video,
        where: v.type == :mux and v.status == :ready and is_nil(v.deleted_at),
        order_by: v.id
      )
      |> Repo.all()
      |> Enum.filter(&(valid_mux_id?(get_in(&1.meta, ["mux", "asset_id"])) and not signed?(&1)))

    plays_mp4 = Brando.Videos.Mp4Use.video_ids(videos)

    Enum.map(videos, fn video ->
      if MapSet.member?(plays_mp4, video.id),
        do: add_missing_renditions(video, resolutions, dry_run?, interval),
        else: %{result(video) | skipped: :streams}
    end)
  end

  defp signed?(video), do: get_in(video.meta, ["mux", "playback_policy"]) == "signed"

  defp result(video) do
    %{
      video_id: video.id,
      title: video.title,
      asset_id: get_in(video.meta, ["mux", "asset_id"]),
      skipped: nil,
      present: [],
      clear: [],
      requested: [],
      failed: [],
      error: nil
    }
  end

  defp add_missing_renditions(video, resolutions, dry_run?, interval) do
    result = result(video)

    case get_asset(result.asset_id) do
      {:ok, asset} ->
        present = present_resolutions(asset)
        missing = resolutions -- present
        clear = if missing == [], do: [], else: in_the_way(asset)
        result = %{result | present: present, clear: clear, requested: missing}
        if dry_run?, do: result, else: request_and_store(video, asset, result, interval)

      {:error, reason} ->
        %{result | error: reason}
    end
  end

  # What Mux won't make a resolution beside: legacy `mp4_support`, or the
  # `highest` rendition
  defp in_the_way(asset) do
    cond do
      asset["mp4_support"] not in [nil, "none"] -> [:mp4_support]
      highest_ids(asset) != [] -> [:highest]
      true -> []
    end
  end

  defp highest_ids(asset) do
    for %{"resolution" => "highest", "id" => id} <- List.wrap(get_in(asset, ["static_renditions", "files"])),
        valid_mux_id?(id),
        do: id
  end

  # Removes what is in the way, asks for the missing renditions, then stores
  # what the asset has: read again when Mux changed it, so the new ones are
  # stored preparing
  defp request_and_store(video, asset, %{asset_id: asset_id, clear: clear, requested: missing} = result, interval) do
    case clear_the_way(asset, clear, interval) do
      :ok ->
        failed = request_renditions(asset_id, missing, interval)
        requested = missing -- Enum.map(failed, &elem(&1, 0))
        asset = if clear == [] and requested == [], do: {:ok, asset}, else: get_asset(asset_id)
        store_result(video, asset, %{result | requested: requested, failed: failed})

      {:error, step, reason} ->
        %{result | clear: [], requested: [], error: {:clear, step, reason}}
    end
  end

  defp store_result(video, asset, result) do
    case with({:ok, asset} <- asset, do: store_static_renditions(video, asset)) do
      {:ok, _video} -> result
      :ignore -> result
      {:error, reason} -> %{result | error: reason}
    end
  end

  defp clear_the_way(_asset, [], _interval), do: :ok

  defp clear_the_way(asset, [:mp4_support], interval) do
    asset["id"]
    |> then(&api_request(:put, "/assets/#{&1}/mp4-support", %{"mp4_support" => "none"}))
    |> paced(interval)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, :mp4_support, reason}
    end
  end

  defp clear_the_way(asset, [:highest], interval) do
    asset
    |> highest_ids()
    |> Enum.reduce_while(:ok, fn id, :ok ->
      case paced(request(:delete, "/assets/#{asset["id"]}/static-renditions/#{id}", nil), interval) do
        {:ok, _} -> {:cont, :ok}
        {:error, {:http_error, _status, body}} -> {:halt, {:error, :highest, body}}
        {:error, reason} -> {:halt, {:error, :highest, reason}}
      end
    end)
  end

  defp paced(result, interval) do
    if interval > 0, do: Process.sleep(interval)
    result
  end

  # A rendition that errored is asked for again
  defp present_resolutions(asset) do
    asset
    |> get_in(["static_renditions", "files"])
    |> List.wrap()
    |> Enum.flat_map(fn
      %{"status" => status, "resolution" => resolution} when status != "errored" -> parse_resolution(resolution)
      _ -> []
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # The resolutions Mux refused, with why. Each request waits `interval`
  # after it, so the next one, for this asset or the next, keeps to Mux's
  # rate.
  defp request_renditions(asset_id, resolutions, interval) do
    Enum.flat_map(resolutions, fn resolution ->
      case paced(
             api_request(:post, "/assets/#{asset_id}/static-renditions", %{"resolution" => "#{resolution}p"}),
             interval
           ) do
        {:ok, _rendition} -> []
        {:error, reason} -> [{resolution, reason}]
      end
    end)
  end

  defp log_result(result, applied?) do
    Logger.info(
      "Mux static renditions, #{result.environment} video ##{result.video_id} (asset #{result.asset_id}): " <>
        describe_result(result, applied?)
    )

    result
  end

  @doc """
  What `add_static_renditions/1` did, or would do unless `applied?`, for one
  video, as a line of text.
  """
  @spec describe_result(map(), boolean()) :: String.t()
  def describe_result(%{skipped: :streams}, _applied?), do: "skipped: only streams"

  def describe_result(%{error: {:clear, step, reason}}, _applied?),
    do: "FAILED to remove #{clear_name(step)}, asked for nothing: #{inspect(reason)}"

  def describe_result(%{error: error, clear: [], requested: [], failed: []}, _applied?) when not is_nil(error),
    do: "FAILED to read the asset: #{inspect(error)}"

  def describe_result(%{error: error} = result, applied?) when not is_nil(error),
    do:
      describe_result(%{result | error: nil}, applied?) <> "  then FAILED to store what the asset has: #{inspect(error)}"

  def describe_result(%{clear: [], requested: [], failed: []}, _applied?), do: "has every rendition"

  def describe_result(result, applied?) do
    cleared =
      Enum.map(result.clear, &if(applied?, do: "removed #{clear_name(&1)}", else: "would remove #{clear_name(&1)}"))

    asked =
      if result.requested == [],
        do: [],
        else: [if(applied?, do: "asked for ", else: "would ask for ") <> format_resolutions(result.requested)]

    failed = Enum.map(result.failed, fn {resolution, reason} -> "FAILED #{resolution}p: #{inspect(reason)}" end)

    half_done =
      if result.clear != [] and result.failed != [],
        do: ["the asset lacks those MP4s until this runs again"],
        else: []

    Enum.join(cleared ++ asked ++ failed ++ half_done, "  ")
  end

  defp clear_name(:highest), do: "the highest rendition"
  defp clear_name(:mp4_support), do: "legacy mp4_support"

  defp format_resolutions(resolutions), do: Enum.map_join(resolutions, ", ", &"#{&1}p")

  # An upload's row has only its upload id until Mux reports the asset.
  @impl true
  def library_holding_keys(asset_id) do
    with {:ok, asset} <- get_asset(asset_id), do: {:ok, upload_holding_keys(asset)}
  end

  defp upload_holding_keys(%{"upload_id" => upload_id}) when is_binary(upload_id) and upload_id != "",
    do: [{"mux.upload_id", upload_id}]

  defp upload_holding_keys(_asset), do: []

  # The holdings were checked for the id asked for, so the asset must be that
  # one, not one Mux matched to it otherwise.
  defp check_asset_id(%{"id" => asset_id}, asset_id), do: :ok
  defp check_asset_id(_asset, _asset_id), do: {:error, :not_found}

  # Signed playback needs a token signer Brando does not have.
  defp check_public_playback(asset) do
    if public_playback_id(asset), do: :ok, else: {:error, :signed_playback_not_supported}
  end

  defp library_item(%{"id" => asset_id} = asset) when is_binary(asset_id) do
    playback_id = public_playback_id(asset)
    status = video_status(asset["status"])
    track = Enum.find(asset["tracks"] || [], &(&1["type"] == "video")) || %{}

    %{
      remote_id: asset_id,
      title: asset_title(asset),
      thumbnail_url: playback_id && "https://image.mux.com/#{playback_id}/thumbnail.jpg?width=320",
      duration: asset["duration"],
      width: track["max_width"],
      height: track["max_height"],
      status: status,
      created_at: unix_to_iso8601(asset["created_at"]),
      # Signed playback needs a token signer Brando does not have.
      playable?: status == :ready and not is_nil(playback_id),
      holding_keys: upload_holding_keys(asset)
    }
  end

  defp library_item(_asset), do: nil

  defp public_playback_id(asset) do
    Enum.find_value(asset["playback_ids"] || [], fn
      %{"id" => id, "policy" => "public"} -> id
      _ -> nil
    end)
  end

  defp asset_title(asset) do
    case get_in(asset, ["meta", "title"]) || asset["passthrough"] do
      title when is_binary(title) and title != "" -> title
      _ -> nil
    end
  end

  defp unix_to_iso8601(value) when is_binary(value) do
    with {seconds, ""} <- Integer.parse(value),
         {:ok, datetime} <- DateTime.from_unix(seconds) do
      DateTime.to_iso8601(datetime)
    else
      _ -> nil
    end
  end

  defp unix_to_iso8601(_value), do: nil

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

  defp request(method, path, body) do
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

        :put ->
          [method: :put, url: url, headers: headers, json: body]

        :delete ->
          [method: :delete, url: url, headers: headers]
      end

    request_opts = ReqOptions.merge(__MODULE__, request_opts)

    case Req.request(request_opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Mux API request failed: #{status} - #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.error("Mux API request error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # The error body alone, as the calls other than the delete take it; the
  # delete keeps the status, which tells an outage from a refusal
  # (`Brando.Videos.Uploader.transient_error?/1`).
  defp api_request(method, path, body \\ nil) do
    case request(method, path, body) do
      {:error, {:http_error, _status, error_body}} -> {:error, error_body}
      result -> result
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
