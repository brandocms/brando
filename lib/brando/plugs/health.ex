defmodule Brando.Plug.Health do
  @moduledoc """
  A plug that handles health check requests at the endpoint level.

  This plug responds to GET/HEAD requests to `/health` before the request
  reaches the router, bypassing all pipeline plugs (sessions, CSRF, etc.).

  Returns JSON with database connectivity, latency, and system metrics.
  Only requests from localhost are allowed.

  ## Usage

  Add to your endpoint before the router:

      plug Brando.Plug.Health
      plug MyAppWeb.Router
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{method: method, path_info: ["health"]} = conn, _opts)
      when method in ["GET", "HEAD"] do
    if Brando.Health.localhost?(conn) do
      health_data = Brando.Health.check()
      status_code = if health_data.status == "ok", do: 200, else: 503

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status_code, Jason.encode!(health_data))
      |> halt()
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(403, Jason.encode!(%{error: "forbidden"}))
      |> halt()
    end
  end

  def call(conn, _opts), do: conn
end
