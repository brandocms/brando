defmodule BrandoWeb.Plugs.BunnyWebhook do
  @moduledoc """
  Plug for handling Bunny Stream webhooks.

  ## Usage

  In your endpoint.ex, add BEFORE Plug.Parsers:

      plug BrandoWeb.Plugs.BunnyWebhook,
        mount: ["api", "videos", "bunny", "webhook"]

  Configure `:webhook_secret` with the Bunny library's Read-Only API key.
  Requests without Bunny's valid `v1` HMAC signature are rejected.

  ## No replay protection

  `BrandoWeb.Plugs.MuxWebhook` and `BrandoWeb.Plugs.CloudflareStreamWebhook`
  both sign a timestamp alongside the body and reject deliveries outside a
  5-minute tolerance. Bunny signs the body alone, so there is nothing here to
  check freshness against and a captured delivery verifies forever.

  That is Bunny's scheme rather than a gap in this plug, and the exposure is
  bounded — the body is signed, so a replay can only re-apply a status Bunny
  itself sent for a video the site already owns. See the "Videos" guide.

  ## Webhook Payload

  Bunny sends webhooks with the following structure:

      {
        "VideoLibraryId": 133,
        "VideoGuid": "657bb740-a71b-4529-a012-528021c31a92",
        "Status": 3
      }

  ## Status Codes

  - 0: Queued
  - 1: Processing
  - 2: Encoding
  - 3: Finished
  - 4: Resolution finished
  - 5: Failed
  - 6-8: Presigned upload statuses
  - 9: Captions generated
  - 10: Title/description generated
  """

  import Plug.Conn

  require Logger

  def init(options), do: options

  def call(conn, options) do
    mount = Keyword.get(options, :mount)

    case conn.path_info do
      ^mount -> handle_bunny_webhook(conn, options)
      _ -> conn
    end
  end

  def handle_bunny_webhook(conn, _options) do
    {:ok, body, conn} = read_body(conn)

    with :ok <- verify_signature(conn, body, get_webhook_secret()),
         {:ok, params} <- Jason.decode(body),
         :ok <- validate_payload(params),
         {:ok, video} <- Brando.Videos.Uploaders.Bunny.handle_webhook(params) do
      Logger.info("Bunny webhook processed successfully for video #{video.id}")

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{status: "ok"}))
      |> halt
    else
      :ignore ->
        Logger.debug("Bunny webhook event ignored")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "ignored"}))
        |> halt

      {:error, :invalid_signature} ->
        Logger.warning("Bunny webhook signature verification failed")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Invalid signature"}))
        |> halt

      {:error, :invalid_payload} ->
        Logger.warning("Bunny webhook invalid payload")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Invalid payload"}))
        |> halt

      {:error, :library_mismatch} ->
        Logger.warning("Bunny webhook library ID mismatch")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, Jason.encode!(%{error: "Library mismatch"}))
        |> halt

      {:error, reason} ->
        Logger.error("Bunny webhook processing failed: #{inspect(reason)}")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(422, Jason.encode!(%{error: "Processing failed"}))
        |> halt
    end
  end

  defp validate_payload(%{
         "VideoLibraryId" => library_id,
         "VideoGuid" => video_guid,
         "Status" => status
       })
       when is_integer(library_id) and is_binary(video_guid) and is_integer(status) do
    :ok
  end

  defp validate_payload(_), do: {:error, :invalid_payload}

  @doc false
  def verify_signature(conn, body, webhook_secret) do
    signature = conn |> get_req_header("x-bunnystream-signature") |> List.first()
    version = conn |> get_req_header("x-bunnystream-signature-version") |> List.first()
    algorithm = conn |> get_req_header("x-bunnystream-signature-algorithm") |> List.first()

    with "v1" <- version,
         "hmac-sha256" <- algorithm,
         secret when is_binary(secret) and secret != "" <- webhook_secret,
         signature when is_binary(signature) <- signature,
         true <- byte_size(signature) == 64 and String.match?(signature, ~r/\A[0-9a-f]{64}\z/) do
      expected_signature =
        :crypto.mac(:hmac, :sha256, secret, body)
        |> Base.encode16(case: :lower)

      if Plug.Crypto.secure_compare(expected_signature, signature) do
        :ok
      else
        {:error, :invalid_signature}
      end
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp get_webhook_secret do
    config = Application.get_env(:brando, Brando.Videos.Uploaders.Bunny, [])
    Keyword.get(config, :webhook_secret) || Keyword.get(config, :read_only_api_key)
  end
end
