defmodule BrandoAdmin.Globals.GlobalsLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Sites.GlobalSet
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Workspace
  alias BrandoAdmin.Components.GlobalTabs

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :active_tab, nil)}
  end

  def handle_event("focus", _, socket), do: {:noreply, socket}
  def handle_event("blur", _, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <div class="admin-workspace settings-workspace globals-workspace">
      <Workspace.header title={gettext("Globals")} />

      <.live_component module={GlobalTabs} id="global_tabs" active_tab={@active_tab} current_user={@current_user}>
      </.live_component>
    </div>
    """
  end
end
