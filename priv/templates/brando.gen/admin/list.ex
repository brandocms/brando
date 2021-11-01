defmodule <%= app_module %>Admin.<%= domain %>.<%= Recase.to_pascal(vue_singular) %>ListLive do
  use BrandoAdmin.LiveView.Listing, schema: <%= schema_module %>
  alias BrandoAdmin.Components.Content
  import <%= web_module %>.Gettext

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("<%= String.capitalize(plural) %>")}
      subtitle={gettext("Overview")}>
      <%%= live_patch gettext("Create new"), class: "primary", to: "/admin/<%= snake_domain %>/<%= plural %>/create" %>
    </Content.header>

    <.live_component
      module={Content.List}
      id={"content_listing_#{@schema}_default"}
      blueprint={@blueprint}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default} />
    """
  end
end
