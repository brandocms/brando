defmodule BrandoAdmin.Sites.GlobalSetListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Sites.GlobalSet
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Global sets")} subtitle={gettext("Overview")}>
      <.link navigate="/admin/config/global_sets/create" class="primary">
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
