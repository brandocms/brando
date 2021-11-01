defmodule BrandoAdmin.Users.UserListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Users.User

  alias BrandoAdmin.Components.Content
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("Users")}
      subtitle={gettext("Overview")}>
      <%= live_patch "Create new", class: "primary", to: "/admin/users/create" %>
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
