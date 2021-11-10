defmodule BrandoAdmin.Pages.PageListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Pages.Page

  alias BrandoAdmin.Components.Content
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("Pages & sections")}
      subtitle={gettext("Overview")}>
      <%= live_patch "Create new", to: "/admin/pages/create", class: "primary" %>
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

  def handle_event("create_subpage", %{"id" => parent_id, "language" => language}, socket) do
    {:noreply,
     push_redirect(socket,
       to:
         Brando.routes().admin_live_path(socket, BrandoAdmin.Pages.PageCreateLive,
           parent_id: parent_id,
           language: language
         )
     )}
  end

  def handle_event("create_fragment", %{"id" => page_id, "language" => language}, socket) do
    {:noreply,
     push_redirect(socket,
       to:
         Brando.routes().admin_live_path(socket, BrandoAdmin.Pages.PageFragmentCreateLive,
           page_id: page_id,
           language: language
         )
     )}
  end
end
