defmodule BrandoAdmin.Users.UserListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Users.User

  alias BrandoAdmin.Components.Content
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Users")} subtitle={gettext("Overview")}>
      <.link navigate="/admin/users/create" class="primary">
        <%= gettext("Create new") %>
      </.link>
    </Content.header>

    <.live_component
      module={Content.List}
      id={"content_listing_#{@schema}_default"}
      schema={@schema}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default}
    />
    """
  end
end
