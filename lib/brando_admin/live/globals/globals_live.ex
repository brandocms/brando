defmodule BrandoAdmin.Globals.GlobalsLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Sites.GlobalSet
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.GlobalTabs

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :active_tab, nil)}
  end

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Globals")} subtitle={gettext("Overview")} />

    <.live_component module={GlobalTabs} id="global_tabs" active_tab={@active_tab} current_user={@current_user}>
    </.live_component>
    """
  end
end
