defmodule Brando.Tenant.AdminContext do
  @moduledoc false

  alias Brando.Tenant
  alias Brando.Tenant.Access
  alias Brando.Tenant.Cache
  alias Brando.Users.User

  @site_session_key "brando_site_key"
  @environment_session_key "brando_environment_key"

  @spec resolve(map() | :not_mounted_at_router, map(), User.t() | nil) ::
          {Brando.Sites.Site.t(), Brando.Environments.Environment.t()} | nil
  def resolve(params, session, current_user \\ nil) do
    if Tenant.enabled?() do
      params = if is_map(params), do: params, else: %{}
      site = selected_site(params, session, current_user)
      environment_key = params[@environment_session_key] || session[@environment_session_key]

      with site when not is_nil(site) <- site,
           environment when not is_nil(environment) <-
             selected_environment(site.key, environment_key) do
        {site, environment}
      else
        _ -> nil
      end
    end
  end

  defp selected_site(params, session, current_user) do
    case Tenant.mode() do
      :single ->
        site = Cache.get_site(Brando.config(:site_key))
        if not Brando.Authorization.enabled?() or (site && Access.can_access?(current_user, site)), do: site

      :multi ->
        selected_multi_site(params, session, current_user)
    end
  end

  defp selected_multi_site(params, session, %User{} = current_user) do
    requested_site =
      case params[@site_session_key] || session[@site_session_key] do
        nil -> nil
        site_key -> Cache.get_site(site_key)
      end

    case requested_site do
      site when not is_nil(site) ->
        if Access.can_access?(current_user, site), do: site, else: default_multi_site(current_user)

      nil ->
        default_multi_site(current_user)
    end
  end

  defp selected_multi_site(_params, _session, nil), do: nil

  defp default_multi_site(current_user) do
    current_user
    |> Access.list_sites()
    |> List.first()
    |> case do
      nil -> nil
      site -> Cache.get_site(site.key)
    end
  end

  defp selected_environment(site_key, nil), do: Cache.get_live_env(site_key)

  defp selected_environment(site_key, environment_key) do
    Cache.get_env(site_key, environment_key) || Cache.get_live_env(site_key)
  end
end
