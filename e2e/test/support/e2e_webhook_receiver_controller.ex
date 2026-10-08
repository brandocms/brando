defmodule E2EWebhookReceiverController do
  @moduledoc false
  # A webhook receiver for the E2E tests: a delivery POSTed to
  # `/e2e/webhook-receiver/:inbox` is kept (headers and raw body) and read
  # back with a GET of the same path. Webhooks may call it only because the
  # E2E config allows localhost (`config :brando, Brando.Webhooks,
  # allow_localhost: true`). No database: the request comes from the server
  # itself, outside any test's sandbox.
  use E2eProjectWeb, :controller

  @store __MODULE__.Store

  def receive_delivery(conn, %{"inbox" => inbox}) do
    request = %{
      "headers" => Map.new(conn.req_headers),
      "body" => conn.assigns[:raw_body] || "",
      "received_at" => DateTime.to_iso8601(DateTime.utc_now())
    }

    Agent.update(store(), &Map.update(&1, inbox, [request], fn requests -> requests ++ [request] end))
    send_resp(conn, 200, "received")
  end

  def list(conn, %{"inbox" => inbox}) do
    json(conn, %{requests: Agent.get(store(), &Map.get(&1, inbox, []))})
  end

  defp store do
    case Agent.start(fn -> %{} end, name: @store) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end
end
