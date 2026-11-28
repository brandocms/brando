defmodule Brando.Tenant.LiveView do
  @moduledoc """
  LiveView mount hook for restoring selected admin tenant context.

  The selected site/environment is stored in the signed Plug session. The hook
  resolves both through `Brando.Tenant.Cache`, assigns them to the socket, and
  restores process context before events and messages.

  In multi-site mode a user with no site to enter is not let in: there is no
  site whose content they could see. A superuser, or with group authorization
  a user granted the screen's installation-wide permission, still reaches the
  installation's own screens (sites, users, groups, frontend assets, the
  shared library), and everyone their own password. From any other screen
  whoever may read the sites screen is sent there, and everyone else to the
  access-denied page.

  The Chrome, the navigation and the upload manager are sticky LiveViews:
  they keep the site and environment of the page load across live
  navigation. The page load names it in the root layout's `brando_context`
  meta, which the browser sends back when it joins a page it navigated to,
  and a live navigation into another site or environment loads the page, so
  that they follow it.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, get_connect_params: 1, redirect: 2]

  alias Brando.Authorization.{Engine, Scope}
  alias Brando.Tenant
  alias Brando.Tenant.AdminContext

  def on_mount(:default, params, session, socket) do
    case resolve_context(params, session, socket.assigns[:current_user]) do
      {site, environment} ->
        prefix = Tenant.prefix(site, environment)
        Tenant.put_prefix(prefix)

        socket =
          socket
          |> assign(%{
            current_site: site,
            current_environment: environment,
            tenant_prefix: prefix
          })
          |> ensure_content_language()
          |> attach_context_hooks()
          |> follow_page_context(params, context(site, environment))

        {:cont, socket}

      nil ->
        Tenant.put_prefix(nil)

        socket =
          socket
          |> assign(%{current_site: nil, current_environment: nil, tenant_prefix: nil})
          |> follow_page_context(params, context(nil, nil))

        if Tenant.mode() == :multi, do: without_site(socket, params), else: {:cont, socket}
    end
  end

  @doc "The site and environment a page was loaded in, as its `brando_context` meta names them."
  def context(%{key: site_key}, %{key: environment_key}), do: "#{site_key}/#{environment_key}"
  def context(_site, _environment), do: ""

  @doc """
  The context of the page `conn` loads, for the root layout's
  `brando_context` meta: resolved from the page's query and the session, as
  the page's LiveView and its sticky views resolve it, and not from the
  session alone, as `Brando.Plug.AdminTenant` does.
  """
  def page_context(%Plug.Conn{} = conn) do
    case AdminContext.resolve(conn.params, Plug.Conn.get_session(conn), conn.assigns[:current_user]) do
      {site, environment} -> context(site, environment)
      nil -> context(nil, nil)
    end
  end

  defp follow_page_context(socket, :not_mounted_at_router, _context), do: socket

  # The browser sends `_live_referer` only when it joins a page it navigated to
  defp follow_page_context(socket, _params, context) do
    case connected?(socket) && get_connect_params(socket) do
      %{"_live_referer" => referer, "brando_context" => loaded}
      when is_binary(referer) and is_binary(loaded) and loaded != context ->
        attach_hook(socket, :brando_tenant_page_load, :handle_params, fn _params, uri, socket ->
          %URI{path: path, query: query} = URI.parse(uri)
          {:halt, redirect(socket, to: URI.to_string(%URI{path: path, query: query}))}
        end)

      _ ->
        socket
    end
  end

  # As `Brando.Plug.AdminTenant` does for a page load: a live navigation or a
  # reconnect into a site whose languages lack the editor's content language
  # works in the site's default language
  defp ensure_content_language(%{assigns: %{current_user: %Brando.Users.User{} = user}} = socket),
    do: assign(socket, :current_user, Brando.Users.ensure_content_language(user))

  defp ensure_content_language(socket), do: socket

  defp without_site(socket, params) do
    user = socket.assigns[:current_user]

    requirement = BrandoAdmin.Authorization.requirement(socket.view, params, socket.assigns[:live_action])

    cond do
      # A child LiveView (navigation, chrome) mounts only inside a screen let in already
      params == :not_mounted_at_router -> {:cont, socket}
      # Their own password, which the first sign-in asks for: an account's, not a site's
      requirement == {:update, :profile} -> {:cont, socket}
      installation_view?(requirement, params, user) -> {:cont, socket}
      installation?(user, {:read, :sites}) -> {:halt, redirect(socket, to: "/admin/sites")}
      true -> {:halt, redirect(socket, to: "/admin/access-denied")}
    end
  end

  defp installation_view?(requirement, params, user),
    do: BrandoAdmin.Authorization.installation?(requirement, params) and installation?(user, requirement)

  # A superuser, or with group authorization one granted the installation-wide
  # permission (sites, frontend assets, accounts)
  defp installation?(%Brando.Users.User{} = user, {action, resource}) do
    if Engine.enabled?(),
      do: Engine.can?(Scope.installation(user), action, resource),
      else: user.role == :superuser
  end

  defp installation?(_user, _requirement), do: false

  @doc false
  def resolve_context(params, session, current_user \\ nil) do
    AdminContext.resolve(params, session, current_user)
  end

  defp attach_context_hooks(socket) do
    socket
    |> attach_hook(:brando_tenant_handle_event, :handle_event, fn _event, _params, socket ->
      restore_prefix(socket)
      {:cont, socket}
    end)
    |> attach_hook(:brando_tenant_handle_info, :handle_info, fn _message, socket ->
      restore_prefix(socket)
      {:cont, socket}
    end)
  end

  defp restore_prefix(socket) do
    Tenant.put_prefix(socket.assigns.tenant_prefix)
  end
end
