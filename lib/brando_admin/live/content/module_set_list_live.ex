defmodule BrandoAdmin.Content.ModuleSetListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Content.ModuleSet

  alias BrandoAdmin.Components.Content
  use Gettext, backend: Brando.Gettext

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Module Sets")} subtitle={gettext("Overview")}>
      <.link navigate={@admin_create_url} class="primary">
        {gettext("Create new")}
      </.link>
    </Content.header>

    <.live_component
      module={Content.List}
      id={"content_listing_#{@schema}_default"}
      schema={@schema}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default}
    />
    """
  end
end
