defmodule BrandoWeb.Plugs.BunnyWebhook do
  @moduledoc """
  Plug for handling Bunny Stream webhooks.

  ## Usage

  In your endpoint.ex, add BEFORE Plug.Parsers:

      plug BrandoWeb.Plugs.BunnyWebhook,
        mount: ["api", "videos", "bunny", "webhook"]

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

    with {:ok, params} <- Jason.decode(body),
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
end
