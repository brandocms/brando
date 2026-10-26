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
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]

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
          |> attach_context_hooks()

        {:cont, socket}

      nil ->
        Tenant.put_prefix(nil)
        socket = assign(socket, %{current_site: nil, current_environment: nil, tenant_prefix: nil})
        if Tenant.mode() == :multi, do: without_site(socket, params), else: {:cont, socket}
    end
  end

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
