defmodule Brando.Videos.Uploaders.Cloudflare do
  @moduledoc """
  Cloudflare Stream direct-upload provider.

  Uploads use Cloudflare's `direct_user=true` tus endpoint. The API token is
  used only by the server while provisioning a one-time upload URL; the browser
  receives that URL and uploads with tus without learning the token.

      config :brando, Brando.Videos.Uploaders.Cloudflare,
        account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID"),
        api_token: System.get_env("CLOUDFLARE_STREAM_API_TOKEN"),
        webhook_secret: System.get_env("CLOUDFLARE_STREAM_WEBHOOK_SECRET"),
        delete_remote_on: :on_purge

  The webhook secret is returned by Cloudflare when the account's Stream
  webhook subscription is created. Signed playback is deliberately rejected
  until the host application provides a token-signing boundary.
  """

  @behaviour Brando.Videos.Uploader

  alias Brando.Videos
  alias Brando.Videos.Uploaders.ReqOptions
  alias Brando.Videos.Video

  require Logger

  @api_base "https://api.cloudflare.com/client/v4/accounts"
  @default_max_duration_seconds 3_600

  @impl true
  def initiate_upload(filename, user, opts \\ []) do
    file_meta = Keyword.fetch!(opts, :file_meta)
    sanitized_filename = sanitize_filename(filename)

    with {:ok, upload_data} <- provision_tus_upload(sanitized_filename, file_meta, opts),
         {:ok, video} <- create_video_record(sanitized_filename, user, upload_data, opts) do
      {:ok,
       %{
         upload_url: upload_data.upload_url,
         video: video,
         expires_at: nil,
         tus_upload: true
       }}
    end
  end

  @impl true
  def complete_upload(%Video{status: :uploading} = video, _provider_data) do
    update_video(video, %{status: :processing})
  end

  def complete_upload(%Video{} = video, _provider_data), do: {:ok, video}

  @impl true
  def handle_webhook(%{"uid" => uid} = payload) when is_binary(uid) do
    case find_video(uid) do
      {:ok, %Video{status: :errored} = video} ->
        {:ok, video}

      {:ok, %Video{status: :ready} = video} ->
        if ready_payload?(payload), do: update_video_from_payload(video, payload), else: {:ok, video}

      {:ok, video} ->
        update_video_from_payload(video, payload)

      {:error, :not_found} ->
        Logger.debug("Cloudflare webhook for unknown video: #{uid}")
        :ignore
    end
  end

  def handle_webhook(payload) do
    Logger.warning("Ignoring invalid Cloudflare Stream webhook: #{inspect(payload, pretty: true)}")
    {:error, :invalid_webhook_data}
  end

  @impl true
  def delete_remote(%Video{meta: %{"cloudflare" => %{"uid" => uid}}}) when is_binary(uid) do
    if valid_uid?(uid) do
      case api_request(:delete, "/stream/#{uid}") do
        {:ok, _response} -> :ok
        {:error, {:http_error, 404, _body}} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :invalid_uid}
    end
  end

  def delete_remote(_video), do: :ok

  @impl true
  def get_playback_url(video)

  def get_playback_url(%Video{meta: %{"cloudflare" => %{"require_signed_urls" => true}}}) do
    {:error, :signed_playback_not_supported}
  end

  def get_playback_url(%Video{status: :ready, meta: %{"cloudflare" => %{"playback_hls" => url}}})
      when is_binary(url) and url != "" do
    {:ok, url}
  end

  def get_playback_url(%Video{status: status}) when status != :ready,
    do: {:error, :video_not_ready}

  def get_playback_url(_video), do: {:error, :missing_playback_url}

  @doc false
  def build_upload_metadata(filename, opts \\ []) do
    max_duration_seconds = Keyword.get(opts, :max_duration_seconds, @default_max_duration_seconds)

    with true <- is_integer(max_duration_seconds) and max_duration_seconds > 0 do
      [
        metadata_pair("name", filename),
        metadata_pair("maxDurationSeconds", Integer.to_string(max_duration_seconds))
      ]
      |> Enum.join(",")
    else
      false -> raise ArgumentError, "Cloudflare max_duration_seconds must be a positive integer"
    end
  end

  defp provision_tus_upload(filename, %{size: size}, opts)
       when is_integer(size) and size >= 0 do
    max_duration_seconds = cloudflare_setting(opts, :max_duration_seconds, @default_max_duration_seconds)

    headers = [
      {"tus-resumable", "1.0.0"},
      {"upload-length", Integer.to_string(size)},
      {"upload-metadata", build_upload_metadata(filename, max_duration_seconds: max_duration_seconds)}
    ]

    case api_request(:post, "/stream?direct_user=true", nil, headers) do
      {:ok, %Req.Response{} = response} ->
        location = response |> Req.Response.get_header("location") |> List.first()
        uid = response |> Req.Response.get_header("stream-media-id") |> List.first()

        if valid_upload_url?(location) and valid_uid?(uid) do
          {:ok, %{upload_url: location, uid: uid}}
        else
          Logger.error("Cloudflare tus provisioning response omitted Location or stream-media-id")
          {:error, :invalid_tus_response}
        end

      error ->
        error
    end
  end

  defp provision_tus_upload(_filename, _file_meta, _opts), do: {:error, :invalid_file_size}

  defp create_video_record(filename, user, upload_data, opts) do
    params = %{
      type: :cloudflare,
      status: :uploading,
      title: filename |> Path.rootname() |> Brando.Utils.humanize(),
      remote_id: upload_data.uid,
      config_target: Keyword.get(opts, :config_target),
      meta: %{
        "provider" => "cloudflare",
        "cloudflare" => %{"uid" => upload_data.uid}
      },
      creator_id: user.id
    }

    Videos.create_video(params)
  end

  defp update_video_from_payload(video, payload) do
    signed? = payload["requireSignedURLs"] == true

    status =
      cond do
        signed? -> :errored
        ready_payload?(payload) -> :ready
        error_payload?(payload) -> :errored
        true -> :processing
      end

    cloudflare_meta =
      %{
        "uid" => payload["uid"],
        "state" => get_in(payload, ["status", "state"]),
        "pct_complete" => get_in(payload, ["status", "pctComplete"]),
        "error_reason_code" => get_in(payload, ["status", "errorReasonCode"]) || payload["errReasonCode"],
        "error_reason_text" => get_in(payload, ["status", "errorReasonText"]) || payload["errReasonText"],
        "playback_hls" => get_in(payload, ["playback", "hls"]),
        "playback_dash" => get_in(payload, ["playback", "dash"]),
        "thumbnail_url" => payload["thumbnail"],
        "require_signed_urls" => signed?
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    params =
      %{
        status: status,
        remote_id: payload["uid"],
        meta:
          video.meta
          |> Map.put("provider", "cloudflare")
          |> Map.put("cloudflare", cloudflare_meta)
      }
      |> put_dimensions(payload["input"])
      |> put_duration(payload["duration"])

    update_video(video, params)
  end

  defp update_video(video, params) do
    with {:ok, creator} <- Brando.Users.get_user(video.creator_id),
         {:ok, updated_video} <- Videos.update_video(video, params, creator) do
      Videos.run_completed_callback_on_ready(video, updated_video, creator)
      broadcast_video_update(updated_video)
      {:ok, updated_video}
    end
  end

  defp put_dimensions(params, %{"width" => width, "height" => height})
       when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    Map.merge(params, %{width: width, height: height, aspect_ratio: "#{width}/#{height}"})
  end

  defp put_dimensions(params, _input), do: params

  defp put_duration(params, duration) when is_number(duration) and duration >= 0 do
    Map.put(params, :duration, Videos.Helpers.format_duration(duration))
  end

  defp put_duration(params, _duration), do: params

  defp ready_payload?(payload) do
    payload["readyToStream"] == true and get_in(payload, ["status", "state"]) == "ready"
  end

  defp error_payload?(payload), do: get_in(payload, ["status", "state"]) == "error"

  defp find_video(uid) do
    case Videos.get_video_by_meta("cloudflare.uid", uid) do
      nil -> {:error, :not_found}
      video -> {:ok, video}
    end
  end

  defp broadcast_video_update(video) do
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      "brando:video:#{video.id}",
      {video, [:video, :updated]}
    )
  end

  defp cloudflare_setting(opts, key, default) do
    config_meta =
      case Keyword.get(opts, :config) do
        %{meta: %{cloudflare: settings}} when is_map(settings) -> settings
        %{meta: %{"cloudflare" => settings}} when is_map(settings) -> settings
        _ -> %{}
      end

    Map.get(config_meta, key) || Map.get(config_meta, Atom.to_string(key)) || default
  end

  defp metadata_pair(key, value), do: "#{key} #{Base.encode64(value)}"

  @doc """
  Whether this provider has usable credentials.

  Public so `Brando.Uploads.validate_provider_video_intake/2` can pre-flight the
  same condition `api_request/4` raises on. The raise below branches on this
  rather than re-testing, so the validator and the raise cannot answer
  differently — which is the whole reason it exists.
  """
  def configured?, do: present?(get_config(:account_id)) and present?(get_config(:api_token))

  defp api_request(method, path, body \\ nil, extra_headers \\ []) do
    # Missing credentials are a deploy-time configuration error, not a runtime
    # condition, so this raises rather than returning an error tuple — as Mux
    # and Bunny do, so one caller branch handles all three.
    #
    # Nothing on the admin upload path should reach it:
    # `Brando.Uploads.validate_provider_video_intake/2` checks `configured?/0`
    # during pre-flight validation, beside the other config-shaped failures. If
    # this raise ever fires from a LiveView, that validator has a gap — the
    # exception costs an editor their unsaved work, which is why the check
    # belongs there and this is only the last-resort invariant guard.
    unless configured?() do
      raise """
      Cloudflare credentials not configured. Please add to your config:

          config :brando, Brando.Videos.Uploaders.Cloudflare,
            account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID"),
            api_token: System.get_env("CLOUDFLARE_API_TOKEN")
      """
    end

    account_id = get_config(:account_id)
    api_token = get_config(:api_token)

    url = "#{@api_base}/#{account_id}#{path}"

    headers =
      [{"authorization", "Bearer #{api_token}"}, {"accept", "application/json"}] ++
        extra_headers

    request_opts =
      ReqOptions.merge(
        __MODULE__,
        [method: method, url: url, headers: headers] |> maybe_put_json(body)
      )

    case Req.request(request_opts) do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %Req.Response{status: status, body: response_body}} ->
        Logger.error("Cloudflare Stream API request failed: #{status} - #{inspect(response_body)}")
        {:error, {:http_error, status, response_body}}

      {:error, reason} ->
        Logger.error("Cloudflare Stream API request error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_put_json(opts, nil), do: opts
  defp maybe_put_json(opts, body), do: Keyword.put(opts, :json, body)

  defp get_config(key) do
    :brando
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key)
  end

  defp valid_upload_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) ->
        host == "upload.videodelivery.net" or String.ends_with?(host, ".videodelivery.net")

      _ ->
        false
    end
  end

  defp valid_upload_url?(_url), do: false

  defp valid_uid?(uid) when is_binary(uid) do
    byte_size(uid) in 1..255 and String.match?(uid, ~r/\A[a-zA-Z0-9_-]+\z/)
  end

  defp valid_uid?(_uid), do: false

  defp sanitize_filename(filename) when is_binary(filename) do
    filename
    |> String.trim()
    |> String.slice(0, 255)
    |> String.replace(~r/[\x00-\x1F\x7F]/, "")
  end

  defp sanitize_filename(_filename), do: "untitled"

  defp present?(value), do: is_binary(value) and value != ""
end
