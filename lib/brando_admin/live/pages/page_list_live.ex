defmodule BrandoAdmin.Pages.PageListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Pages.Page

  alias BrandoAdmin.Components.Content
  alias Surface.Components.LivePatch
  import Brando.Gettext

  def render(assigns) do
    ~F"""
    <Content.Header
      title={gettext("Pages & sections")}
      subtitle={gettext("Overview")}>
      <LivePatch to="/admin/pages/create" class="primary">
        Create new
      </LivePatch>
    </Content.Header>

    <Content.List
      id={"content_listing_#{@schema}_default"}
      blueprint={@blueprint}
      uri={@uri}
      params={@params}
      listing={:default} />
    """
  end

  def handle_event("create_subpage", %{"id" => parent_id, "language" => language}, socket) do
    {:noreply,
     push_redirect(socket,
       to:
         Brando.routes().live_path(socket, BrandoAdmin.PageCreateLive,
           parent_id: parent_id,
           language: language
         )
     )}
  end

  def handle_event("create_fragment", %{"id" => page_id, "language" => language}, socket) do
    {:noreply,
     push_redirect(socket,
       to:
         Brando.routes().live_path(socket, BrandoAdmin.PageFragmentCreateLive,
           page_id: page_id,
           language: language
         )
     )}
  end
end
