defmodule <%= app_module %>Admin.<%= domain %>.<%= Recase.to_pascal(vue_singular) %>ListLive do
  use BrandoAdmin.LiveView.Listing, schema: <%= schema_module %>
  alias BrandoAdmin.Components.Content
  alias Surface.Components.LivePatch
  import <%= web_module %>.Gettext

  def render(assigns) do
    ~F"""
    <Content.Header
      title={gettext("<%= String.capitalize(plural) %>")}
      subtitle={gettext("Overview")}>
      <LivePatch to="/admin/<%= snake_domain %>/<%= plural %>/create" class="primary">
        {gettext("Create new")}
      </LivePatch>
    </Content.Header>

    <Content.List
      id={"content_listing_#{@schema}_default"}
      blueprint={@blueprint}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default} />
    """
  end
end
