defmodule Brando.Plug.AdminTenant do
  @moduledoc "Restores the selected admin tenant for non-LiveView requests."

  import Plug.Conn, only: [assign: 3, get_session: 1]

  alias Brando.Tenant
  alias Brando.Tenant.AdminContext

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case AdminContext.resolve(%{}, get_session(conn), conn.assigns[:current_user]) do
      {site, environment} ->
        prefix = Tenant.prefix(site, environment)
        Tenant.put_prefix(prefix)

        conn
        |> assign(:current_site, site)
        |> assign(:current_environment, environment)
        |> assign(:tenant_prefix, prefix)

      nil ->
        Tenant.put_prefix(nil)
        conn
    end
  end
end
