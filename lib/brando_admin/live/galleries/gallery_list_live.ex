defmodule BrandoAdmin.Galleries.GalleryListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Galleries.Gallery
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.{Content, Workspace}

  def render(assigns) do
    ~H"""
    <div class="admin-workspace content-workspace workspace-list media-workspace galleries-workspace">
      <Workspace.header title={gettext("Galleries")} subtitle={gettext("Image and video collections used in your content.")} />

      <.live_component
        module={Content.List}
        id={"content_listing_#{@schema}_default"}
        schema={@schema}
        current_user={@current_user}
        uri={@uri}
        params={@params}
        listing={:default}
        empty_title={gettext("No galleries yet")}
        empty_description={gettext("Create a gallery in an entry to see it here.")}
      />
    </div>
    """
  end
end
