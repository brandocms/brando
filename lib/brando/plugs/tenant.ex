defmodule Brando.Plug.Tenant do
  @moduledoc """
  Resolves frontend tenant context, without a database query but for a shared
  preview's link.

  Multi-site requests resolve by normalized host through `Brando.Tenant.Cache`.
  Single-site mode falls back to the configured site's live environment when no
  domain is assigned. Unknown hosts clear process context instead of inheriting
  stale state. In multi-site mode they are rejected so an application cannot
  accidentally serve unscoped or another tenant's content, with one exception:
  a shared preview's link (`/__p__/:preview_key`) takes its context from the
  preview, which costs one query on that path only.
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
        put_tenant(conn, site, environment)

      nil ->
        Tenant.put_prefix(nil)

        case shared_preview_tenant(conn) do
          {site, environment} -> put_tenant(conn, site, environment)
          nil -> reject_missing_multi_site(conn)
        end
    end
  end

  defp put_tenant(conn, site, environment) do
    prefix = Tenant.prefix(site, environment)
    Tenant.put_prefix(prefix)

    conn
    |> assign(:current_site, site)
    |> assign(:current_environment, environment)
    |> assign(:tenant_prefix, prefix)
  end

  # A shared preview's link is on the endpoint's host, which belongs to no
  # site: it opens there under the site and environment it was shared from.
  # Only that path is looked up, and only an unexpired preview of an active
  # site lets the request through.
  defp shared_preview_tenant(%{path_info: ["__p__", key]}) do
    if Tenant.mode() == :multi do
      case Brando.Sites.get_shared_preview(key) do
        {:ok, preview} -> Frontend.shared_preview_tenant(preview)
        {:error, _not_found} -> nil
      end
    end
  end

  defp shared_preview_tenant(_conn), do: nil

  # Internal preview rendering has a server-resolved workspace but no frontend
  # host. This private connection metadata cannot be supplied by an HTTP client.
  defp resolve(%{
         private: %{
           brando_live_preview: true,
           brando_preview_context:
             {%Brando.Sites.Site{id: id} = site, %Brando.Environments.Environment{site_id: id} = environment}
         }
       }) do
    {site, environment}
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
