defmodule BrandoAdmin.Content.PaletteListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Content.Palette

  alias BrandoAdmin.Components.Content
  alias Surface.Components.LivePatch
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("Content Palettes")}
      subtitle={gettext("Overview")}>
      <%= live_patch "Create new", to: "/admin/config/content/palettes/create", class: "primary" %>
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
