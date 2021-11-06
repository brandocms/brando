defmodule BrandoAdmin.Content.TemplateListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Content.Template

  alias BrandoAdmin.Components.Content
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("Content Templates")}
      subtitle={gettext("Overview")}>
      <%= live_patch "Create new", to: "/admin/config/content/templates/create", class: "primary" %>
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
