defmodule Brando.Plug.Tenant do
  @moduledoc """
  Resolves frontend tenant context without a database query.

  Multi-site requests resolve by normalized host through `Brando.Tenant.Cache`.
  Single-site mode falls back to the configured site's live environment when no
  domain is assigned. Unknown hosts clear process context instead of inheriting
  stale state. In multi-site mode they are rejected so an application cannot
  accidentally serve unscoped or another tenant's content.
  """

  import Plug.Conn, only: [assign: 3, halt: 1, send_resp: 3]

  alias Brando.SSG.Context
  alias Brando.Tenant
  alias Brando.Tenant.Frontend

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case resolve(conn) do
      {site, environment} ->
        prefix = Tenant.prefix(site, environment)
        Tenant.put_prefix(prefix)

        conn
        |> assign(:current_site, site)
        |> assign(:current_environment, environment)
        |> assign(:tenant_prefix, prefix)

      nil ->
        Tenant.put_prefix(nil)
        reject_missing_multi_site(conn)
    end
  end

  defp resolve(conn) do
    conn
    |> Plug.Conn.get_req_header(Context.header())
    |> List.first()
    |> Context.resolve()
    |> Kernel.||(Frontend.resolve(conn.host))
  end

  defp reject_missing_multi_site(conn) do
    if Tenant.mode() == :multi do
      conn
      |> send_resp(404, "Not found")
      |> halt()
    else
      conn
    end
  end
end
