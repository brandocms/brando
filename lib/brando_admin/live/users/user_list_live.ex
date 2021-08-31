defmodule BrandoAdmin.Users.UserListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Users.User

  alias BrandoAdmin.Components.Content
  alias Surface.Components.LivePatch
  import Brando.Gettext

  def render(assigns) do
    ~F"""
    <Content.Header
      title={gettext("Users")}
      subtitle={gettext("Overview")}>
      <LivePatch to="/admin/users/create" class="primary">
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
