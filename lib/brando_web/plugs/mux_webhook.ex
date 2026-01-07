defmodule BrandoWeb.Plugs.MuxWebhook do
  @moduledoc """
  Plug for interfacing with Mux webhooks

  ## Usage

  In your endpoint.ex, add BEFORE Plug.Parsers:

      plug BrandoWeb.Plugs.MuxWebhook,
        mount: ["api", "videos", "mux", "webhook"]
  """
  import Plug.Conn

  require Logger

  def init(options) do
    options
  end

  def call(conn, options) do
    mount = Keyword.get(options, :mount)

    case conn.path_info do
      ^mount -> handle_mux_webhook(conn, options)
      _ -> conn
    end
  end

  @doc """
  Check and verify incoming Mux webhook requests
  """
  def handle_mux_webhook(conn, _options) do
    {:ok, body, conn} = read_body(conn)
    signature_header = get_req_header(conn, "mux-signature") |> List.first()
    webhook_secret = get_webhook_secret()

    with :ok <- verify_signature(signature_header, body, webhook_secret),
         {:ok, params} <- Jason.decode(body),
         {:ok, video} <- Brando.Videos.Uploaders.Mux.handle_webhook(params) do
      Logger.info("Mux webhook processed successfully for video #{video.id}")

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{status: "ok"}))
      |> halt
    else
      :ignore ->
        Logger.debug("Mux webhook event ignored")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "ignored"}))
        |> halt

      {:error, :invalid_signature} ->
        Logger.warning("Mux webhook signature verification failed")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Invalid signature"}))
        |> halt

      {:error, reason} ->
        Logger.error("Mux webhook processing failed: #{inspect(reason)}")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(422, Jason.encode!(%{error: "Processing failed"}))
        |> halt
    end
  end

  defp verify_signature(nil, _body, _secret) do
    Logger.warning("Mux webhook received without signature header")
    {:error, :invalid_signature}
  end

  defp verify_signature(_signature_header, _body, nil) do
    Logger.error("Mux webhook secret not configured - rejecting webhook for security")
    {:error, :invalid_signature}
  end

  defp verify_signature(signature_header, body, webhook_secret) do
    # Mux-Signature header format: "t=timestamp,v1=signature"
    signature_parts =
      signature_header
      |> String.split(",")
      |> Enum.map(&String.split(&1, "="))
      |> Enum.into(%{}, fn [k, v] -> {k, v} end)

    timestamp = Map.get(signature_parts, "t")
    expected_signature = Map.get(signature_parts, "v1")

    cond do
      is_nil(timestamp) || is_nil(expected_signature) ->
        Logger.warning("Invalid Mux-Signature header format")
        {:error, :invalid_signature}

      !valid_timestamp?(timestamp) ->
        {:error, :invalid_signature}

      true ->
        # Compute signature: HMAC-SHA256(webhook_secret, timestamp + "." + raw_body)
        payload = "#{timestamp}.#{body}"

        computed_signature =
          :crypto.mac(:hmac, :sha256, webhook_secret, payload)
          |> Base.encode16(case: :lower)

        # Constant-time comparison to prevent timing attacks
        if Plug.Crypto.secure_compare(computed_signature, expected_signature) do
          :ok
        else
          Logger.warning("Mux webhook signature mismatch")
          {:error, :invalid_signature}
        end
    end
  end

  defp valid_timestamp?(timestamp_str) do
    case Integer.parse(timestamp_str) do
      {timestamp, _} ->
        current_time = System.system_time(:second)
        time_diff = abs(current_time - timestamp)

        # Reject if timestamp is more than 5 minutes old (prevent replay attacks)
        if time_diff > 300 do
          Logger.warning("Mux webhook timestamp too old: #{time_diff} seconds")
          false
        else
          true
        end

      :error ->
        Logger.warning("Invalid timestamp in Mux-Signature header")
        false
    end
  end

  defp get_webhook_secret do
    Application.get_env(:brando, Brando.Videos.Uploaders.Mux, [])
    |> Keyword.get(:webhook_secret)
  end
end
