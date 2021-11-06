defmodule BrandoAdmin.Navigation.MenuListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Navigation.Menu
  import Brando.Gettext
  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("Navigation")}
      subtitle={gettext("Overview")}>
      <%= live_patch "Create new", to: "/admin/navigation/menu/create", class: "primary" %>
    </Content.header>

    <.live_component module={Content.List}
      id={"content_listing_#{@schema}_default"}
      blueprint={@blueprint}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default} />
    """
  end
end
