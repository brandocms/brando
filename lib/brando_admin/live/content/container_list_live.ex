defmodule BrandoAdmin.Content.ContainerListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Content.Container
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Containers")} subtitle={gettext("Overview")}>
      <.link navigate="/admin/config/content/containers/create" class="primary">
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
