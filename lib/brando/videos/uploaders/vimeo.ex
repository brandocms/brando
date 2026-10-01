defmodule Brando.Videos.Uploaders.Vimeo do
  @moduledoc """
  Vimeo direct-upload provider.

  Uploads use the API's tus approach. The access token is used only by the
  server, to create the video and its one-time `upload_link`; the browser
  PATCHes that link with tus and never learns the token.

      config :brando, Brando.Videos.Uploaders.Vimeo,
        access_token: System.get_env("VIMEO_ACCESS_TOKEN"),
        folder_uri: System.get_env("VIMEO_FOLDER_URI"),
        delete_remote_on: :on_purge

  ## Requirements

  A Vimeo plan with access to video files — Standard, Advanced, Pro, Business,
  Premium or Enterprise — and a personal access token with the `public`,
  `private`, `upload`, `edit`, `delete` and `video_files` scopes. Without
  `video_files` the API returns no file links, and videos fall back to Vimeo's
  embedded player instead of rendering through Brando's `<video>` component.

  ## Playback

  Vimeo offers two kinds of HLS link. `play` links expire after 24 hours, which
  rules them out for anything rendered ahead of a request — a cached page, a
  static build, a published entry. `files` links do not expire, so the adaptive
  (`quality: "hls"`) entry from `files` is what is stored. Those links carry
  the access token's id; revoking the token stops them playing.

  ## No webhooks

  Vimeo has no webhook for transcode completion, so `Brando.Worker.VimeoStatus`
  polls `GET /videos/{id}` until the video is available or has failed. The
  `handle_webhook/1` callback is what it hands each response to.

  ## Field settings

  Per-field options go in the video config's `meta`:

      video_config: %{
        upload_strategy: :vimeo,
        meta: %{vimeo: %{"privacy_view" => "unlisted", "folder_uri" => "/users/1/projects/2"}}
      }

  `privacy_view` is one of `"anybody"`, `"unlisted"`, `"nobody"` or
  `"disable"` (default `"unlisted"`). Password-protected uploads are rejected: Brando has
  nowhere to keep the password.
  """

  @behaviour Brando.Videos.Uploader

  alias Brando.Videos
  alias Brando.Videos.Uploaders.ReqOptions
  alias Brando.Videos.Video
  alias Brando.Videos.VimeoURL

  require Logger

  @base_url "https://api.vimeo.com"
  @accept "application/vnd.vimeo.*+json;version=3.4"

  @default_privacy_view "unlisted"

  @video_fields ~w(
    uri name link player_embed_url status upload.status transcode.status
    width height duration pictures.base_link pictures.sizes files privacy.view
  ) |> Enum.join(",")

  @ready_states ["available"]
  @error_states ["uploading_error", "transcoding_error", "quota_exceeded", "total_cap_exceeded"]

  @impl true
  def initiate_upload(filename, user, opts \\ []) do
    file_meta = Keyword.fetch!(opts, :file_meta)
    sanitized_filename = sanitize_filename(filename)

    with {:ok, created} <- create_tus_video(sanitized_filename, file_meta, opts),
         {:ok, video} <- create_video_record(sanitized_filename, user, created, opts) do
      enqueue_status_check(video, schedule_in: 60)

      {:ok,
       %{
         upload_url: get_in(created, ["upload", "upload_link"]),
         video: video,
         expires_at: nil,
         tus_upload: true
       }}
    end
  end

  @impl true
  def complete_upload(%Video{status: :uploading} = video, _provider_data) do
    with {:ok, video} <- update_video(video, %{status: :processing}) do
      enqueue_status_check(video)
      {:ok, video}
    end
  end

  def complete_upload(%Video{} = video, _provider_data), do: {:ok, video}

  @doc """
  Applies a Vimeo video representation — a `GET /videos/{id}` response — to the
  record it belongs to.

  Vimeo has no webhooks, so the "webhook" is `Brando.Worker.VimeoStatus`
  handing over what it fetched.
  """
  @impl true
  def handle_webhook(%{"uri" => uri} = payload) when is_binary(uri) do
    case find_video(video_id_from_uri(uri)) do
      {:ok, video} -> apply_remote(video, payload)
      {:error, :not_found} -> :ignore
    end
  end

  def handle_webhook(_payload), do: {:error, :invalid_payload}

  @doc """
  Fetches the video's current state from Vimeo and applies it.

  Returns `{:error, :not_found}` when Vimeo no longer has the video.
  """
  @spec sync(Video.t()) :: {:ok, Video.t()} | {:error, term()}
  def sync(%Video{} = video) do
    with {:ok, video_id} <- remote_video_id(video),
         {:ok, payload} <- fetch_video(video_id) do
      apply_remote(video, payload)
    end
  end

  @doc """
  `GET /videos/{id}` with the fields Brando stores.
  """
  @spec fetch_video(String.t()) :: {:ok, map()} | {:error, term()}
  def fetch_video(video_id) do
    if valid_video_id?(video_id) do
      case api_request(:get, "/videos/#{video_id}", params: [fields: @video_fields]) do
        {:ok, %Req.Response{body: %{} = body}} -> {:ok, body}
        {:ok, _response} -> {:error, :invalid_response}
        {:error, {:http_error, 404, _body}} -> {:error, :not_found}
        error -> error
      end
    else
      {:error, :invalid_video_id}
    end
  end

  @impl true
  def delete_remote(%Video{} = video) do
    case remote_video_id(video) do
      {:ok, video_id} ->
        case api_request(:delete, "/videos/#{video_id}") do
          {:ok, _response} -> :ok
          {:error, {:http_error, 404, _body}} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, :missing_video_id} ->
        :ok

      error ->
        error
    end
  end

  @impl true
  def get_playback_url(%Video{status: :ready, meta: %{"vimeo" => %{"hls_url" => url}}})
      when is_binary(url) and url != "",
      do: {:ok, url}

  def get_playback_url(%Video{status: status}) when status != :ready, do: {:error, :video_not_ready}
  def get_playback_url(_video), do: {:error, :missing_playback_url}

  @doc """
  The Vimeo player URL, hash included. Used where there is no file link: an
  account without `video_files`, or a video Vimeo has not yet given one.
  """
  @spec embed_url(Video.t(), keyword()) :: String.t() | nil
  def embed_url(%Video{meta: %{"vimeo" => %{} = vimeo}} = video, params \\ []) do
    case vimeo do
      %{"video_id" => id} when is_binary(id) -> VimeoURL.player_url(id, vimeo["hash"], params)
      _ -> VimeoURL.embed_url(video, params)
    end
  end

  @doc """
  Whether this provider has usable credentials.

  Public so `Brando.Uploads.validate_provider_video_intake/2` can pre-flight the
  same condition `api_request/3` raises on.
  """
  def configured?, do: present?(get_config(:access_token))

  # The tus approach creates the video and its upload resource in one call.
  # `upload.size` is required up front, which is why intake insists on file
  # metadata before this is reached.
  defp create_tus_video(filename, %{size: size}, opts) when is_integer(size) and size > 0 do
    body =
      %{
        "upload" => %{"approach" => "tus", "size" => Integer.to_string(size)},
        "name" => filename |> Path.rootname() |> Brando.Utils.humanize(),
        "privacy" => %{"view" => vimeo_setting(opts, :privacy_view, @default_privacy_view)}
      }
      |> maybe_put("folder_uri", vimeo_setting(opts, :folder_uri, get_config(:folder_uri)))

    case api_request(:post, "/me/videos", json: body) do
      {:ok, %Req.Response{body: %{"uri" => uri} = created}} ->
        upload_link = get_in(created, ["upload", "upload_link"])

        cond do
          not valid_upload_url?(upload_link) ->
            Logger.error("Vimeo tus response had no usable upload_link: #{inspect(upload_link)}")
            {:error, :invalid_tus_response}

          not valid_video_id?(video_id_from_uri(uri)) ->
            Logger.error("Vimeo tus response had an unexpected uri: #{inspect(uri)}")
            {:error, :invalid_tus_response}

          true ->
            {:ok, created}
        end

      {:ok, _response} ->
        {:error, :invalid_tus_response}

      error ->
        error
    end
  end

  defp create_tus_video(_filename, _file_meta, _opts), do: {:error, :invalid_file_size}

  defp create_video_record(filename, user, created, opts) do
    video_id = video_id_from_uri(created["uri"])

    params = %{
      type: :vimeo_account,
      status: :uploading,
      title: filename |> Path.rootname() |> Brando.Utils.humanize(),
      remote_id: video_id,
      source_url: created["link"],
      config_target: Keyword.get(opts, :config_target),
      meta: %{
        "provider" => "vimeo",
        "vimeo" => vimeo_meta(created)
      },
      creator_id: user.id
    }

    Videos.create_video(params)
  end

  defp vimeo_meta(payload) do
    video_id = video_id_from_uri(payload["uri"])

    hash =
      case VimeoURL.parse(payload["player_embed_url"] || payload["link"]) do
        {:ok, %{hash: hash}} -> hash
        :error -> nil
      end

    %{
      "video_id" => video_id,
      "uri" => payload["uri"],
      "hash" => hash,
      "link" => payload["link"],
      "status" => payload["status"],
      "upload_status" => get_in(payload, ["upload", "status"]),
      "transcode_status" => get_in(payload, ["transcode", "status"]),
      "hls_url" => hls_url(payload["files"]),
      "thumbnail_url" => thumbnail_url(payload["pictures"]),
      "privacy_view" => get_in(payload, ["privacy", "view"])
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp remote_status(payload) do
    cond do
      payload["status"] in @error_states -> :errored
      get_in(payload, ["transcode", "status"]) == "error" -> :errored
      payload["status"] in @ready_states -> :ready
      get_in(payload, ["upload", "status"]) == "in_progress" -> :uploading
      true -> :processing
    end
  end

  defp apply_remote(%Video{status: :errored} = video, _payload), do: {:ok, video}

  defp apply_remote(video, payload) do
    status =
      case {video.status, remote_status(payload)} do
        # A ready video does not go back to processing because Vimeo is
        # re-transcoding it after a replace in its own UI.
        {:ready, remote} when remote in [:uploading, :processing] -> :ready
        # The browser has already reported the transfer finished.
        {:processing, :uploading} -> :processing
        {_current, remote} -> remote
      end

    previous_meta = Map.get(video.meta || %{}, "vimeo", %{})

    params =
      %{
        status: status,
        remote_id: video_id_from_uri(payload["uri"]),
        meta:
          (video.meta || %{})
          |> Map.put("provider", "vimeo")
          |> Map.put("vimeo", Map.merge(previous_meta, vimeo_meta(payload)))
      }
      |> maybe_put_source_url(video, payload["link"])
      |> put_dimensions(payload)
      |> put_duration(payload["duration"])

    update_video(video, params)
  end

  defp maybe_put_source_url(params, %Video{source_url: url}, _link) when is_binary(url) and url != "",
    do: params

  defp maybe_put_source_url(params, _video, link) when is_binary(link), do: Map.put(params, :source_url, link)
  defp maybe_put_source_url(params, _video, _link), do: params

  defp update_video(video, params) do
    with {:ok, creator} <- Brando.Users.get_user(video.creator_id),
         {:ok, updated_video} <- Videos.update_video(video, params, creator) do
      Videos.run_completed_callback_on_ready(video, updated_video, creator)
      broadcast_video_update(updated_video)
      {:ok, updated_video}
    end
  end

  # Vimeo reports 0×0 until it has probed the source.
  defp put_dimensions(params, %{"width" => width, "height" => height})
       when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    Map.merge(params, %{width: width, height: height, aspect_ratio: "#{width}/#{height}"})
  end

  defp put_dimensions(params, _payload), do: params

  defp put_duration(params, duration) when is_number(duration) and duration > 0,
    do: Map.put(params, :duration, Videos.Helpers.format_duration(duration))

  defp put_duration(params, _duration), do: params

  defp hls_url(files) when is_list(files) do
    Enum.find_value(files, fn
      %{"quality" => "hls", "link" => link} when is_binary(link) -> link
      %{"rendition" => "adaptive", "link" => link} when is_binary(link) -> link
      _ -> nil
    end)
  end

  defp hls_url(_files), do: nil

  defp thumbnail_url(%{"sizes" => [_ | _] = sizes}) do
    sizes
    |> Enum.filter(&is_binary(&1["link"]))
    |> Enum.max_by(&(&1["width"] || 0), fn -> nil end)
    |> case do
      %{"link" => link} -> link
      nil -> nil
    end
  end

  defp thumbnail_url(%{"base_link" => link}) when is_binary(link), do: link
  defp thumbnail_url(_pictures), do: nil

  defp enqueue_status_check(%Video{id: id}, opts \\ []) do
    %{"video_id" => id}
    |> Brando.Tenant.Job.attach()
    |> Brando.Worker.VimeoStatus.new(opts)
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        # The upload itself is unaffected; the reaper and the next completion
        # report are the fallback. Losing the poll is not worth an editor's
        # unsaved form.
        Logger.error("Could not schedule Vimeo status check for video #{id}: #{inspect(reason)}")
        :ok
    end
  end

  defp broadcast_video_update(video) do
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      "brando:video:#{video.id}",
      {video, [:video, :updated]}
    )
  end

  defp find_video(nil), do: {:error, :not_found}

  defp find_video(video_id) do
    case Videos.get_video_by_meta("vimeo.video_id", video_id) do
      nil -> {:error, :not_found}
      video -> {:ok, video}
    end
  end

  defp remote_video_id(%Video{meta: %{"vimeo" => %{"video_id" => id}}}) when is_binary(id) do
    if valid_video_id?(id), do: {:ok, id}, else: {:error, :invalid_video_id}
  end

  defp remote_video_id(_video), do: {:error, :missing_video_id}

  defp video_id_from_uri("/videos/" <> rest) do
    case String.split(rest, ["/", ":"], parts: 2) do
      [id | _] -> if valid_video_id?(id), do: id
    end
  end

  defp video_id_from_uri(_uri), do: nil

  defp vimeo_setting(opts, key, default) do
    config_meta =
      case Keyword.get(opts, :config) do
        %{meta: %{vimeo: settings}} when is_map(settings) -> settings
        %{meta: %{"vimeo" => settings}} when is_map(settings) -> settings
        _ -> %{}
      end

    Map.get(config_meta, key) || Map.get(config_meta, Atom.to_string(key)) || default
  end

  defp api_request(method, path, opts \\ []) do
    # Missing credentials are a deploy-time configuration error, not a runtime
    # condition, so this raises — as the other providers do. The admin upload
    # path pre-flights `configured?/0` in
    # `Brando.Uploads.validate_provider_video_intake/2`, so this is only the
    # last-resort invariant guard.
    unless configured?() do
      raise """
      Vimeo credentials not configured. Please add to your config:

          config :brando, Brando.Videos.Uploaders.Vimeo,
            access_token: System.get_env("VIMEO_ACCESS_TOKEN")
      """
    end

    headers = [
      {"authorization", "bearer #{get_config(:access_token)}"},
      {"accept", @accept}
    ]

    request_opts =
      ReqOptions.merge(
        __MODULE__,
        [method: method, url: @base_url <> path, headers: headers] ++ Keyword.take(opts, [:json, :params])
      )

    case Req.request(request_opts) do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Vimeo API request failed: #{status} - #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.error("Vimeo API request error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_config(key) do
    :brando
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key)
  end

  defp valid_upload_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) -> String.ends_with?(host, ".vimeo.com")
      _ -> false
    end
  end

  defp valid_upload_url?(_url), do: false

  defp valid_video_id?(id) when is_binary(id), do: id =~ ~r/\A\d{1,20}\z/
  defp valid_video_id?(_id), do: false

  defp maybe_put(map, _key, value) when value in [nil, ""], do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp sanitize_filename(filename) when is_binary(filename) do
    filename
    |> String.trim()
    |> String.slice(0, 255)
    |> String.replace(~r/[\x00-\x1F\x7F]/, "")
  end

  defp sanitize_filename(_filename), do: "untitled"

  defp present?(value), do: is_binary(value) and value != ""
end
