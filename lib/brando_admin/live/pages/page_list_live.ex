defmodule BrandoAdmin.Pages.PageListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Pages.Page

  alias Brando.Pages
  alias BrandoAdmin.Components.Content
  use Gettext, backend: Brando.Gettext

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Pages & Sections")} subtitle={gettext("Overview")}>
      <.link navigate="/admin/pages/create" class="primary">
        <%= gettext("Create page") %>
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

  def handle_event(
        "duplicate_fragment",
        %{"id" => entry_id},
        %{assigns: %{current_user: user}} = socket
      ) do
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

  def handle_event(
        "delete_fragment",
        %{"id" => entry_id},
        %{assigns: %{current_user: user}} = socket
      ) do
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
