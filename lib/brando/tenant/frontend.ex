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

  @doc """
  The site and environment a shared preview opens under on a host with no
  site: the ones it was shared from, or its site's live environment for a
  preview stored before previews recorded their environment. Nil for a
  preview with no site, or one whose site is not active.
  """
  @spec shared_preview_tenant(Brando.Sites.Preview.t()) ::
          {Brando.Sites.Site.t(), Brando.Environments.Environment.t()} | nil
  def shared_preview_tenant(%Brando.Sites.Preview{site_id: site_id, environment_id: environment_id})
      when is_integer(site_id) do
    with %{status: :active} = site <- Enum.find(Cache.list_sites(), &(&1.id == site_id)),
         %{} = environment <-
           Enum.find(site.environments, &(&1.id == environment_id)) || Cache.get_live_env(site.key) do
      {site, environment}
    else
      _ -> nil
    end
  end

  def shared_preview_tenant(_preview), do: nil

  @doc """
  Whether `host` is an environment's domain of a site that is not active.

  Such a host resolves to no site, as the endpoint's does, but it is a site's
  own: it opens no other site's shared preview.
  """
  @spec inactive_site_host?(String.t()) :: boolean()
  def inactive_site_host?(host) when is_binary(host) do
    host = normalize_host(host)

    Enum.any?(Cache.list_sites(), fn site ->
      site.status != :active and Enum.any?(site.environments, &(normalize_host(&1.domain) == host))
    end)
  end

  defp normalize_host(host) when is_binary(host), do: host |> String.trim() |> String.downcase()
  defp normalize_host(_host), do: nil

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
