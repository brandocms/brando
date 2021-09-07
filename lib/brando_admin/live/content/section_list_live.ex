defmodule BrandoAdmin.Villain.SectionListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Content.Section

  alias BrandoAdmin.Components.Content
  alias Surface.Components.LivePatch
  import Brando.Gettext

  def render(assigns) do
    ~F"""
    <Content.Header
      title={gettext("Content Sections")}
      subtitle={gettext("Overview")}>
      <LivePatch to="/admin/config/content/sections/create" class="primary">
        Create new
      </LivePatch>
    </Content.Header>

    <Content.List
      id={"content_listing_#{@schema}_default"}
      blueprint={@blueprint}
      uri={@uri}
      params={@params}
      listing={:default} />
    """
  end
end
