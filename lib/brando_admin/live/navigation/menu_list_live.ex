defmodule BrandoAdmin.Navigation.MenuListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Navigation.Menu
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Workspace

  def render(assigns) do
    ~H"""
    <div class="admin-workspace workspace-list content-workspace navigation-workspace">
      <Workspace.header title={gettext("Navigation")}>
        <.link
          :if={BrandoAdmin.Authorization.allowed?(:create, @schema)}
          navigate="/admin/config/navigation/menus/create"
          class="workspace-button primary"
        >
          {gettext("Create new")}
        </.link>
      </Workspace.header>

      <.live_component
        module={Content.List}
        id={"content_listing_#{@schema}_default"}
        schema={@schema}
        current_user={@current_user}
        uri={@uri}
        params={@params}
        listing={:default}
        hidden_filters={[]}
        empty_title={gettext("No menus in this view")}
        empty_description={gettext("Adjust your search or create a new entry.")}
      />
    </div>
    """
  end
end
