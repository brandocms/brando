defmodule <%= app_module %>Admin.<%= domain %>.<%= camel_singular %>ListLive do
  use BrandoAdmin.LiveView.Listing, schema: <%= inspect schema_module %>
  use Gettext, backend: <%= admin_module %>.Gettext, warn: false
  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("<%= String.capitalize(plural) %>")}
      subtitle={gettext("Overview")}>
      <.link navigate={@admin_create_url} class="primary">
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
