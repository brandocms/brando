defmodule Brando.Tenant.AdminContext do
  @moduledoc false

  alias Brando.Tenant
  alias Brando.Tenant.Cache

  @site_session_key "brando_site_key"
  @environment_session_key "brando_environment_key"

  @spec resolve(map() | :not_mounted_at_router, map()) ::
          {Brando.Sites.Site.t(), Brando.Environments.Environment.t()} | nil
  def resolve(params, session) do
    if Tenant.enabled?() do
      params = if is_map(params), do: params, else: %{}
      site_key = selected_site_key(params, session)
      environment_key = params[@environment_session_key] || session[@environment_session_key]

      with site when not is_nil(site) <- Cache.get_site(site_key),
           environment when not is_nil(environment) <-
             selected_environment(site.key, environment_key) do
        {site, environment}
      else
        _ -> nil
      end
    end
  end

  defp selected_site_key(params, session) do
    case Tenant.mode() do
      :single -> Brando.config(:site_key)
      :multi -> params[@site_session_key] || session[@site_session_key] || default_multi_site_key()
    end
  end

  defp default_multi_site_key do
    Cache.list_sites()
    |> Enum.find(&(&1.status == :active))
    |> case do
      nil -> nil
      site -> site.key
    end
  end

  defp selected_environment(site_key, nil), do: Cache.get_live_env(site_key)

  defp selected_environment(site_key, environment_key) do
    Cache.get_env(site_key, environment_key) || Cache.get_live_env(site_key)
  end
end
