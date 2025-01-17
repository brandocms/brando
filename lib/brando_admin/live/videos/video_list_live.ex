defmodule BrandoAdmin.Videos.VideoListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Videos.Video
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Assets — Videos")} subtitle={gettext("Overview")} />

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
