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

  @timestamp_tolerance_seconds 300

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

  @doc false
  def verify_signature(signature_header, body, secret, now \\ System.system_time(:second))

  def verify_signature(nil, _body, _secret, _now) do
    Logger.warning("Mux webhook received without signature header")
    {:error, :invalid_signature}
  end

  def verify_signature(_signature_header, _body, nil, _now) do
    Logger.error("Mux webhook secret not configured - rejecting webhook for security")
    {:error, :invalid_signature}
  end

  def verify_signature(signature_header, body, secret, now) do
    with {:ok, timestamp, signature} <- parse_signature(signature_header),
         :ok <- validate_timestamp(timestamp, now) do
      :hmac
      |> :crypto.mac(:sha256, secret, "#{timestamp}.#{body}")
      |> Base.encode16(case: :lower)
      |> compare_signature(signature)
    end
  end

  # Mux-Signature is "t=<timestamp>,v1=<hex>".
  #
  # Deliberately total. This parses unauthenticated input, and the `Enum.into/3`
  # it replaces raised `FunctionClauseError` on any segment that was not exactly
  # `key=value` — so `t=1,v1` answered a request with a 500 rather than the 401
  # every other branch here is careful to return. `parts: 2` for the same
  # reason: a value containing `=` is data, not a parse failure.
  defp parse_signature(header) do
    parts =
      for segment <- String.split(header, ","),
          [key, value] <- [String.split(segment, "=", parts: 2)],
          into: %{},
          do: {key, value}

    with {:ok, timestamp} <- Map.fetch(parts, "t"),
         {:ok, signature} <- Map.fetch(parts, "v1"),
         {timestamp, ""} <- Integer.parse(timestamp) do
      {:ok, timestamp, signature}
    else
      _ ->
        Logger.warning("Invalid Mux-Signature header format")
        {:error, :invalid_signature}
    end
  end

  # Rejects replayed deliveries. `Integer.parse/1` is required to consume the
  # whole string — the `{timestamp, _}` match this replaces read "123abc" as
  # 123, which let a caller smuggle trailing bytes through the signed payload.
  defp validate_timestamp(timestamp, now) do
    drift = abs(now - timestamp)

    if drift <= @timestamp_tolerance_seconds do
      :ok
    else
      Logger.warning("Mux webhook timestamp outside tolerance: #{drift} seconds")
      {:error, :invalid_signature}
    end
  end

  defp compare_signature(expected, signature) do
    # Constant-time comparison to prevent timing attacks
    if Plug.Crypto.secure_compare(expected, signature) do
      :ok
    else
      Logger.warning("Mux webhook signature mismatch")
      {:error, :invalid_signature}
    end
  end

  defp get_webhook_secret do
    Application.get_env(:brando, Brando.Videos.Uploaders.Mux, [])
    |> Keyword.get(:webhook_secret)
  end
end
