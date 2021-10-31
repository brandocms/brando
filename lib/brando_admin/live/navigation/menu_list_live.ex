defmodule BrandoAdmin.Navigation.MenuListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Navigation.Menu
  import Brando.Gettext
  alias BrandoAdmin.Components.Content
  alias Surface.Components.LivePatch

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("Navigation")}
      subtitle={gettext("Overview")}>
      <%= live_patch "Create new", to: "/admin/navigation/menu/create", class: "primary" %>
    </Content.header>

    <Content.List.live_component
      id={"content_listing_#{@schema}_default"}
      blueprint={@blueprint}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default} />
    """
  end
end
