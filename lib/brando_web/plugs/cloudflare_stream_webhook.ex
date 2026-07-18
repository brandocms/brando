defmodule BrandoWeb.Plugs.CloudflareStreamWebhook do
  @moduledoc """
  Handles signed Cloudflare Stream processing webhooks.

  Mount this plug before `Plug.Parsers` so signature verification receives the
  exact raw request body:

      plug BrandoWeb.Plugs.CloudflareStreamWebhook,
        mount: ["api", "videos", "cloudflare", "webhook"]

  Cloudflare allows one Stream webhook subscription per account. Configure the
  signing secret returned when that subscription is created as
  `:webhook_secret` on `Brando.Videos.Uploaders.Cloudflare`.
  """

  import Plug.Conn

  require Logger

  @timestamp_tolerance_seconds 300

  def init(options), do: options

  def call(conn, options) do
    mount = Keyword.fetch!(options, :mount)

    case conn.path_info do
      ^mount -> handle_webhook(conn)
      _path -> conn
    end
  end

  @doc false
  def handle_webhook(conn) do
    with {:ok, body, conn} <- read_full_body(conn),
         :ok <- verify_signature(conn, body, webhook_secret()),
         {:ok, payload} <- Jason.decode(body),
         :ok <- validate_payload(payload),
         result <- Brando.Videos.Uploaders.Cloudflare.handle_webhook(payload) do
      respond_to_result(conn, result)
    else
      {:error, :invalid_signature} ->
        json_response(conn, 401, %{error: "Invalid signature"})

      {:error, :invalid_payload} ->
        json_response(conn, 400, %{error: "Invalid payload"})

      {:error, %Jason.DecodeError{}} ->
        json_response(conn, 400, %{error: "Invalid JSON"})

      {:error, reason} ->
        Logger.error("Cloudflare Stream webhook failed: #{inspect(reason)}")
        json_response(conn, 422, %{error: "Processing failed"})
    end
  end

  @doc false
  def verify_signature(conn, body, secret, now \\ System.system_time(:second)) do
    signature_header = conn |> get_req_header("webhook-signature") |> List.first()

    with secret when is_binary(secret) and secret != "" <- secret,
         signature_header when is_binary(signature_header) <- signature_header,
         {:ok, timestamp, signature} <- parse_signature(signature_header),
         true <- abs(now - timestamp) <= @timestamp_tolerance_seconds,
         true <- byte_size(signature) == 64 and String.match?(signature, ~r/\A[0-9a-fA-F]{64}\z/) do
      expected =
        :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{body}")
        |> Base.encode16(case: :lower)

      if Plug.Crypto.secure_compare(expected, String.downcase(signature)) do
        :ok
      else
        {:error, :invalid_signature}
      end
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp parse_signature(header) do
    parts =
      header
      |> String.split(",")
      |> Enum.reduce(%{}, fn part, acc ->
        case String.split(part, "=", parts: 2) do
          [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
          _ -> acc
        end
      end)

    with time when is_binary(time) <- parts["time"],
         {timestamp, ""} <- Integer.parse(time),
         signature when is_binary(signature) <- parts["sig1"] do
      {:ok, timestamp, signature}
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp validate_payload(%{"uid" => uid, "status" => %{"state" => state}})
       when is_binary(uid) and uid != "" and is_binary(state),
       do: :ok

  defp validate_payload(_payload), do: {:error, :invalid_payload}

  defp respond_to_result(conn, {:ok, video}) do
    Logger.info("Cloudflare Stream webhook processed successfully for video #{video.id}")
    json_response(conn, 200, %{status: "ok"})
  end

  defp respond_to_result(conn, :ignore), do: json_response(conn, 200, %{status: "ignored"})
  defp respond_to_result(conn, {:error, reason}), do: json_response(conn, 422, %{error: inspect(reason)})

  defp json_response(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end

  defp read_full_body(conn, acc \\ []) do
    case read_body(conn) do
      {:ok, body, conn} -> {:ok, IO.iodata_to_binary(Enum.reverse([body | acc])), conn}
      {:more, body, conn} -> read_full_body(conn, [body | acc])
      {:error, reason} -> {:error, reason}
    end
  end

  defp webhook_secret do
    :brando
    |> Application.get_env(Brando.Videos.Uploaders.Cloudflare, [])
    |> Keyword.get(:webhook_secret)
  end
end
