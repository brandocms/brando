defmodule Brando.Tenant.FrontendLiveView do
  @moduledoc """
  LiveView mount hook for a site's public pages: what `Brando.Plug.Tenant` is
  to a request.

  A LiveView's connected process never passes through the plug, so without
  this hook its queries read the `public` schema. The hook resolves the site
  and environment from the page's host, puts the tenant prefix in the process,
  assigns `:current_site`, `:current_environment` and `:tenant_prefix`, and
  restores the prefix before events and messages. With tenancy disabled it
  assigns `nil`s and does nothing else. In multi-site mode a host that resolves
  no site raises a 404, as the plug answers one.

      live_session :site, on_mount: [Brando.Tenant.FrontendLiveView] do
        live "/contact", MyAppWeb.ContactLive
      end

  The host is read from the socket's `:uri` connect info when the endpoint
  declares it, and otherwise from the URL the LiveView mounted at. The first,
  disconnected render keeps the site the plug resolved for the request, as for
  a static build's pages.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Frontend

  def on_mount(:default, _params, _session, socket) do
    if Tenant.enabled?() do
      mount_tenant(socket, resolve(socket))
    else
      {:cont, assign(socket, %{current_site: nil, current_environment: nil, tenant_prefix: nil})}
    end
  end

  # The dead render runs in the request's process, after `Brando.Plug.Tenant`,
  # which also honours a static build's signed context and live preview: keep
  # what it resolved.
  defp resolve(socket) do
    with false <- Phoenix.LiveView.connected?(socket),
         "tenant_" <> rest <- Tenant.current_prefix(),
         [site_key, environment_key] <- String.split(rest, "_", parts: 2),
         %{} = site <- Cache.get_site(site_key),
         %{} = environment <- Cache.get_env(site_key, environment_key) do
      {site, environment}
    else
      _ -> with host when is_binary(host) <- host(socket), do: Frontend.resolve(host)
    end
  end

  defp mount_tenant(socket, resolved) do
    case resolved do
      {site, environment} ->
        prefix = Tenant.prefix(site, environment)
        Tenant.put_prefix(prefix)

        {:cont,
         socket
         |> assign(%{current_site: site, current_environment: environment, tenant_prefix: prefix})
         |> attach_hook(:brando_frontend_tenant_event, :handle_event, &restore_prefix/3)
         |> attach_hook(:brando_frontend_tenant_info, :handle_info, &restore_prefix/2)}

      nil ->
        Tenant.put_prefix(nil)

        if Tenant.mode() == :multi,
          do: raise(Brando.Exception.EntryNotFoundError, message: "No site answers on this host"),
          else: {:cont, assign(socket, %{current_site: nil, current_environment: nil, tenant_prefix: nil})}
    end
  end

  defp host(socket) do
    case connect_uri(socket) || socket.host_uri do
      %URI{host: host} when is_binary(host) -> host
      _ -> nil
    end
  end

  defp connect_uri(socket) do
    Phoenix.LiveView.get_connect_info(socket, :uri)
  rescue
    _ -> nil
  end

  defp restore_prefix(_event, _params, socket), do: restore_prefix(nil, socket)

  defp restore_prefix(_message, socket) do
    Tenant.put_prefix(socket.assigns.tenant_prefix)
    {:cont, socket}
  end
end
