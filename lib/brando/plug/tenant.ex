defmodule Brando.Plug.Tenant do
  @moduledoc """
  Resolves frontend tenant context without a database query.

  Multi-site requests resolve by normalized host through `Brando.Tenant.Cache`.
  Single-site mode falls back to the configured site's live environment when no
  domain is assigned. Unknown hosts clear process context instead of inheriting
  stale state.
  """

  import Plug.Conn, only: [assign: 3]

  alias Brando.Tenant
  alias Brando.Tenant.Cache

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case resolve(conn.host) do
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

  defp resolve(host) do
    if Tenant.enabled?() do
      Cache.get_env_by_domain(host) || resolve_single_site()
    end
  end

  defp resolve_single_site do
    if Tenant.mode() == :single do
      site_key = Brando.config(:site_key)

      with site when not is_nil(site) <- Cache.get_site(site_key),
           environment when not is_nil(environment) <- Cache.get_live_env(site_key) do
        {site, environment}
      else
        _ -> nil
      end
    end
  end
end
