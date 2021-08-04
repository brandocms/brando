defmodule <%= web_module %>.Admin.<%= Recase.to_pascal(vue_singular) %>ListLive do
  use BrandoAdmin.LiveView.Listing, schema: <%= schema_module %>
  alias BrandoAdmin.Components.Content
  import <%= web_module %>.Gettext

  def render(assigns) do
    ~F"""
    <Content.Header
      title={gettext("<%= String.upcase(plural) %>")}
      subtitle={gettext("Overview")}
      instructions="" />

    <Content.List
      id={"content_listing_#{@schema}_default"}
      blueprint={@blueprint}
      uri={@uri}
      params={@params}
      listing={:default} />
    """
  end
end
