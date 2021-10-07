defmodule BrandoAdmin.Navigation.MenuListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Navigation.Menu
  import Brando.Gettext
  alias BrandoAdmin.Components.Content
  alias Surface.Components.LivePatch

  def render(assigns) do
    ~F"""
    <Content.Header
      title={gettext("Navigation")}
      subtitle={gettext("Overview")}>
      <LivePatch to="/admin/navigation/menu/create" class="primary">
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
