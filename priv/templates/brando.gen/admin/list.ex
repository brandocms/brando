defmodule <%= app_module %>Admin.<%= domain %>.<%= Recase.to_pascal(vue_singular) %>ListLive do
  use BrandoAdmin.LiveView.Listing, schema: <%= inspect schema_module %>
  alias BrandoAdmin.Components.Content
  import <%= admin_module %>.Gettext, warn: false

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("<%= String.capitalize(plural) %>")}
      subtitle={gettext("Overview")}>
      <.link navigate={@schema.__modules__().admin_create_view} class="primary">
        <%%= gettext("Create new") %>
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
