defmodule Brando.MCP.ConsentPlug do
  @moduledoc """
  Around the consent screen (`/admin/mcp/authorize`). `:check`, before the
  admin pipeline, answers as a route that does not exist when the request's
  `resource` is not an endpoint that is on, so a site with the endpoint off
  sets no cookie or header here. `:guard`, after it, keeps the screen out of
  frames (clickjacking) and caches, and sends a visitor who is not signed in
  to log in (with two-factor authentication) and back.
  """
  @behaviour Plug

  import Plug.Conn

  alias Brando.MCP

  @impl Plug
  def init(step) when step in [:check, :guard], do: step

  # First, before the admin pipeline touches the session or sets a header:
  # with the endpoint off, nothing about this route shows. It answers as a
  # route that does not exist.
  @impl Plug
  def call(conn, :check) do
    conn = fetch_query_params(conn)

    with {:ok, tenant} <- MCP.tenant_for_resource(conn.query_params["resource"]),
         true <- MCP.enabled?(tenant) do
      conn
    else
      _ -> raise Phoenix.Router.NoRouteError, conn: conn, router: Brando.RuntimeConfig.router()
    end
  end

  # After the admin pipeline: no frames, nothing cached, and a visitor who is
  # not signed in goes to log in and comes back.
  def call(conn, :guard) do
    conn
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_header("content-security-policy", "frame-ancestors 'none'")
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> BrandoAdmin.UserAuth.require_authenticated_user([])
  end
end
