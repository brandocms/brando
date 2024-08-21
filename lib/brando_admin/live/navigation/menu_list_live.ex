defmodule BrandoAdmin.Navigation.MenuListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Navigation.Menu
  use Gettext, backend: Brando.Gettext
  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Navigation")} subtitle={gettext("Overview")}>
      <.link navigate="/admin/config/navigation/menus/create" class="primary">
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
