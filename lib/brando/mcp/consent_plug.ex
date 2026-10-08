defmodule Brando.MCP.ConsentPlug do
  @moduledoc """
  In front of the consent screen (`/admin/mcp/authorize`), after the admin
  pipeline: the screen cannot be framed by another site (clickjacking), it
  answers 404 as a missing route when the request's `resource` is not an
  endpoint that is on, and it sends a visitor who is not signed in to log in
  (with two-factor authentication) and back.
  """
  @behaviour Plug

  import Plug.Conn

  alias Brando.MCP

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn =
      conn
      |> put_resp_header("x-frame-options", "DENY")
      |> put_resp_header("content-security-policy", "frame-ancestors 'none'")
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")

    conn = fetch_query_params(conn)

    with {:ok, tenant} <- MCP.tenant_for_resource(conn.query_params["resource"]),
         true <- MCP.enabled?(tenant) do
      BrandoAdmin.UserAuth.require_authenticated_user(conn, [])
    else
      _ -> raise Phoenix.Router.NoRouteError, conn: conn, router: Brando.RuntimeConfig.router()
    end
  end
end
