defmodule E2eProjectAdmin.Prices.PriceCategoryListLive do
  use BrandoAdmin.LiveView.Listing, schema: E2eProject.Prices.PriceCategory
  use Gettext, backend: E2eProjectAdmin.Gettext, warn: false
  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("Price categories")}
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
