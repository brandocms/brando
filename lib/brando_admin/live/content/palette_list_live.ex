defmodule BrandoAdmin.Content.PaletteListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Content.Palette
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Content Palettes")} subtitle={gettext("Overview")}>
      <.link navigate="/admin/config/content/palettes/create" class="primary">
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
