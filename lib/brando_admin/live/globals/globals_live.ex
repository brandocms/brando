defmodule BrandoAdmin.Globals.GlobalsLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Sites.GlobalSet

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.GlobalTabs
  import Brando.Gettext

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :active_tab, nil)}
  end

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Globals")} subtitle={gettext("Overview")} />

    <.live_component
      module={GlobalTabs}
      id="global_tabs"
      active_tab={@active_tab}
      current_user={@current_user}
    >
    </.live_component>
    """
  end
end
