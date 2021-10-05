defmodule BrandoAdmin.Content.PaletteListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Content.Palette

  alias BrandoAdmin.Components.Content
  alias Surface.Components.LivePatch
  import Brando.Gettext

  def render(assigns) do
    ~F"""
    <Content.Header
      title={gettext("Content Palettes")}
      subtitle={gettext("Overview")}>
      <LivePatch to="/admin/config/content/palettes/create" class="primary">
        Create new
      </LivePatch>
    </Content.Header>

    <Content.List
      id={"content_listing_#{@schema}_default"}
      blueprint={@blueprint}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default} />
    """
  end
end
