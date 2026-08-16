defmodule Brando.Tenant.Frontend do
  @moduledoc false

  alias Brando.Tenant
  alias Brando.Tenant.Cache

  @spec resolve(String.t()) ::
          {Brando.Sites.Site.t(), Brando.Environments.Environment.t()} | nil
  def resolve(host) do
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
