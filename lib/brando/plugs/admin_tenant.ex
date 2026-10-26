defmodule Brando.Plug.AdminTenant do
  @moduledoc "Restores the selected admin tenant for non-LiveView requests."

  import Plug.Conn, only: [assign: 3, get_session: 1, halt: 1, send_resp: 3]

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

        Brando.Authorization.Boundary.put_scope(
          Brando.Authorization.Scope.site(conn.assigns[:current_user], site, environment)
        )

        conn
        |> assign(:current_site, site)
        |> assign(:current_environment, environment)
        |> assign(:tenant_prefix, prefix)

      nil ->
        Tenant.put_prefix(nil)
        scope = if conn.assigns[:current_user], do: Brando.Authorization.Scope.current(conn.assigns.current_user)
        Brando.Authorization.Boundary.put_scope(scope)
        if Tenant.mode() == :multi, do: without_site(conn), else: conn
    end
  end

  # In multi-site mode a signed-in user with no site to enter reaches only
  # what is not a site's: signing in and out, choosing a site, and the
  # access-denied page. LiveView requests go on to `Brando.Tenant.LiveView`,
  # which lets superusers into the installation's screens.
  @open_controllers [
    BrandoAdmin.AccessDeniedController,
    BrandoAdmin.EnvironmentController,
    BrandoAdmin.UserSessionController
  ]

  defp without_site(%{assigns: %{current_user: %Brando.Users.User{}}} = conn) do
    if live_view?(conn) or controller(conn) in @open_controllers do
      conn
    else
      deny(conn)
    end
  end

  defp without_site(conn), do: conn

  defp live_view?(conn), do: Map.has_key?(conn.private, :phoenix_live_view)

  defp controller(%{private: %{phoenix_router: router}} = conn) do
    case Phoenix.Router.route_info(router, conn.method, conn.request_path, conn.host) do
      %{plug: plug} -> plug
      _ -> nil
    end
  end

  defp controller(_conn), do: nil

  defp deny(%{method: "GET"} = conn) do
    conn |> Phoenix.Controller.redirect(to: "/admin/access-denied") |> halt()
  end

  defp deny(conn), do: conn |> send_resp(403, "Forbidden") |> halt()
end
