defmodule <%= admin_module %>.<%= domain %>.<%= camel_singular %>ListLive do
  use BrandoAdmin.LiveView.Listing, schema: <%= inspect schema_module %>
  use Gettext, backend: <%= admin_module %>.Gettext, warn: false
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Workspace

  def render(assigns) do
    ~H"""
    <div class="admin-workspace workspace-list content-workspace">
      <Workspace.header title={gettext("<%= String.capitalize(plural) %>")}>
        <.link
          :if={BrandoAdmin.Authorization.allowed?(:create, @schema)}
          navigate={@admin_create_url}
          class="workspace-button primary"
        >
          <%%= gettext("Create new") %>
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
      />
    </div>
    """
  end
end
