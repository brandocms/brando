defmodule BrandoAdmin.EnvironmentController do
  @moduledoc "Stores the selected admin site/environment in the signed session."

  use BrandoAdmin, :controller

  import Plug.Conn, only: [put_session: 3]

  alias Brando.Tenant
  alias Brando.Tenant.Access
  alias Brando.Tenant.Cache

  def update(conn, params) do
    with true <- Tenant.enabled?(),
         site_key when is_binary(site_key) <- selected_site_key(params),
         site when not is_nil(site) <- Cache.get_site(site_key),
         true <- authorized?(conn.assigns[:current_user], site),
         environment when not is_nil(environment) <- selected_environment(site.key, params) do
      conn
      |> put_session("brando_site_key", site.key)
      |> put_session("brando_environment_key", environment.key)
      |> redirect(to: safe_return_to(params["return_to"]))
    else
      _ -> redirect(conn, to: "/admin")
    end
  end

  defp authorized?(current_user, site) do
    case Tenant.mode() do
      :single -> not Brando.Authorization.enabled?() or Access.can_access?(current_user, site)
      :multi -> Access.can_access?(current_user, site)
    end
  end

  defp selected_site_key(params) do
    case Tenant.mode() do
      :single -> Brando.config(:site_key)
      :multi -> params["site_key"]
    end
  end

  defp selected_environment(site_key, params) do
    case params["environment_key"] do
      key when is_binary(key) -> Cache.get_env(site_key, key) || Cache.get_live_env(site_key)
      _ -> Cache.get_live_env(site_key)
    end
  end

  defp safe_return_to(path) when is_binary(path) do
    if path == "/admin" or String.starts_with?(path, ["/admin/", "/admin?"]) do
      path
    else
      "/admin"
    end
  end

  defp safe_return_to(_path), do: "/admin"
end
