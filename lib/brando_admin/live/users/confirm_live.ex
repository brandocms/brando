defmodule BrandoAdmin.Users.ConfirmLive do
  @moduledoc false
  # Where a screen that asks to confirm first (`on_mount {BrandoAdmin.Reauth,
  # :screen}`) sends a session that has not confirmed lately, and where the
  # `require_recent_auth` plug sends a controller route. Back to `return_to`
  # once confirmed.
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Workspace

  on_mount({BrandoAdmin.Reauth, events: []})

  def render(assigns) do
    ~H"""
    <div class="admin-workspace security-workspace confirm-workspace">
      <Workspace.header title={gettext("Confirm it’s you")} subtitle={@current_user.email} icon="lock" />
      <section :if={@reauth} class="workspace-panel security-panel">
        <BrandoAdmin.Reauth.prompt reauth={@reauth} inline />
      </section>
    </div>
    """
  end

  def mount(params, _session, socket) do
    {:ok,
     assign(socket,
       socket_connected: connected?(socket),
       page_title: gettext("Confirm it’s you"),
       reauth: %{
         return_to: BrandoAdmin.Reauth.local_path(params["return_to"]),
         error: nil,
         passkeys?: Brando.Users.Passkeys.any?(socket.assigns.current_user),
         challenge: nil
       }
     )}
  end
end
