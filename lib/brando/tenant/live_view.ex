defmodule Brando.Tenant.LiveView do
  @moduledoc """
  LiveView mount hook for restoring selected admin tenant context.

  The selected site/environment is stored in the signed Plug session. The hook
  resolves both through `Brando.Tenant.Cache`, assigns them to the socket, and
  restores process context before events and messages.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias Brando.Tenant
  alias Brando.Tenant.AdminContext

  def on_mount(:default, params, session, socket) do
    case resolve_context(params, session) do
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

        {:cont,
         assign(socket, %{
           current_site: nil,
           current_environment: nil,
           tenant_prefix: nil
         })}
    end
  end

  @doc false
  defdelegate resolve_context(params, session), to: AdminContext, as: :resolve

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
