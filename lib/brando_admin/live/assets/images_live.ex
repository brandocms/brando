defmodule BrandoAdmin.Assets.ImagesLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Images.Image

  alias Brando.Utils
  alias BrandoAdmin.Components.Content
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("Assets — Images")}
      subtitle={gettext("Overview")} />

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
