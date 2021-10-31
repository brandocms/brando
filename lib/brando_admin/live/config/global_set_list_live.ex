defmodule BrandoAdmin.Sites.GlobalSetListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Sites.GlobalSet

  alias BrandoAdmin.Components.Content
  alias Surface.Components.LivePatch
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("Global sets")}
      subtitle={gettext("Overview")}>
      <%= live_patch "Create new set", to: "/admin/config/global_sets/create", class: "primary" %>
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
