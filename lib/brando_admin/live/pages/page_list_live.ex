defmodule BrandoAdmin.Pages.PageListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Pages.Page

  alias Brando.Pages
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Content.List.Row
  alias BrandoAdmin.Components.Workspace
  use Gettext, backend: Brando.Gettext

  def render(assigns) do
    ~H"""
    <div class="admin-workspace workspace-list content-workspace pages-workspace">
      <Workspace.header icon={@page_icon} title={gettext("Pages & Sections")}>
        <.link
          :if={BrandoAdmin.Authorization.allowed?(:create, @schema)}
          navigate="/admin/pages/create"
          class="btn btn--primary"
        >
          {gettext("Create page")}
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
        hidden_filters={[:parents]}
        empty_title={gettext("No pages in this view")}
        empty_description={gettext("Adjust your search or create a new entry.")}
      />

      <%!-- A listing wrapper of its own, for the chips' listing styles --%>
      <section
        :if={@fragments_without_page != []}
        id="fragments-without-page"
        class="content-list-wrapper fragments-without-page"
        aria-labelledby="fragments-without-page-title"
      >
        <header class="fragments-without-page-header">
          <h2 id="fragments-without-page-title">{gettext("Fragments without a page")}</h2>
          <p>
            {gettext(
              "Their page is in the trash or gone, or they never had one. They still show on the site. Edit one to choose its page."
            )}
          </p>
        </header>
        <div class="content-list">
          <div class="list-row">
            <Row.child_chips
              id="fragments-without-page-chips"
              parent={%Pages.Page{}}
              entries={@fragments_without_page}
              child_listing={@fragment_listing}
              parent_listing={@page_listing}
              schema={@schema}
              content_language={@current_user.config.content_language}
              current_user={@current_user}
            />
          </div>
        </div>
      </section>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    page_listing = Enum.find(Pages.Page.__listings__(), &(&1.name == :default))
    fragment_listing = Enum.find(page_listing.child_listings, &(&1.name == :fragment_children))

    {:ok,
     socket
     |> assign(:page_listing, page_listing)
     |> assign(:fragment_listing, %{fragment_listing | add: nil})
     |> assign_fragments_without_page()}
  end

  # Called by the listing when its entries change (a page or a fragment
  # deleted, restored or duplicated, here or by another editor)
  def entries_updated(socket), do: assign_fragments_without_page(socket)

  # Fragments the listing shows under no page: their page is trashed or gone,
  # or they never had one (`Brando.Pages.list_fragments_without_page/1`), in
  # the content language, as the listing shows pages
  defp assign_fragments_without_page(socket) do
    fragments =
      if BrandoAdmin.Authorization.allowed?(:read, Pages.Fragment),
        do:
          socket.assigns.current_user.config.content_language
          |> Pages.list_fragments_without_page()
          |> Brando.Repo.preload(creator: :avatar, updated_by: :avatar),
        else: []

    assign(socket, :fragments_without_page, fragments)
  end

  def handle_event("create_subpage", %{"id" => parent_id, "language" => language}, socket) do
    create_url =
      Brando.Pages.Page.__admin_route__(:create, [
        parent_id,
        parent_id: parent_id,
        language: language
      ])

    {:noreply, push_navigate(socket, to: create_url)}
  end

  def handle_event("create_fragment", %{"id" => page_id, "language" => language}, socket) do
    create_url =
      Brando.Pages.Fragment.__admin_route__(:create, [[page_id: page_id, language: language]])

    {:noreply, push_navigate(socket, to: create_url)}
  end

  def handle_event("edit_subpage", %{"id" => entry_id}, socket) do
    update_url = Brando.Pages.Page.__admin_route__(:update, [entry_id])
    {:noreply, push_navigate(socket, to: update_url)}
  end

  def handle_event("edit_fragment", %{"id" => entry_id}, socket) do
    update_url = Brando.Pages.Fragment.__admin_route__(:update, [entry_id])
    {:noreply, push_navigate(socket, to: update_url)}
  end

  def handle_event("duplicate_fragment", %{"id" => entry_id}, %{assigns: %{current_user: user}} = socket) do
    case Pages.duplicate_fragment(entry_id, user) do
      {:ok, _} ->
        send(self(), {:toast, gettext("Fragment duplicated")})
        BrandoAdmin.LiveView.Listing.update_list_entries(Pages.Page)

      {:error, error} ->
        require Logger

        Logger.error("""
        ==> error duplicating fragment

        #{inspect(error, pretty: true, limit: :infinity)}

        """)

        send(self(), {:toast, gettext("Error duplicating fragment")})
    end

    {:noreply, socket}
  end

  def handle_event("delete_fragment", %{"id" => entry_id}, %{assigns: %{current_user: user}} = socket) do
    schema = socket.assigns.schema

    case Pages.delete_fragment(entry_id, user) do
      {:ok, _} ->
        send(self(), {:toast, gettext("Fragment deleted")})
        BrandoAdmin.LiveView.Listing.update_list_entries(schema)

      {:error, _error} ->
        send(self(), {:toast, gettext("Error deleting fragment")})
    end

    {:noreply, socket}
  end
end
