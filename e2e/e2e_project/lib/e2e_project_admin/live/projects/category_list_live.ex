defmodule E2eProjectAdmin.Projects.CategoryListLive do
  use BrandoAdmin.LiveView.Listing, schema: E2eProject.Projects.Category
  use Gettext, backend: E2eProjectAdmin.Gettext, warn: false
  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("Categories")}
      subtitle={gettext("Overview")}>
      <.link navigate={@admin_create_url} class="primary">
        <%= gettext("Create new") %>
      </.link>
    </Content.header>

    <.live_component module={Content.List}
      id={"content_listing_#{@schema}_default"}
      schema={@schema}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default} />
    """
  end
end
