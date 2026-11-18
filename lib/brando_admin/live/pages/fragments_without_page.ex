defmodule BrandoAdmin.Pages.FragmentsWithoutPage do
  @moduledoc """
  The pages listing's "Fragments without a page": the fragments it shows
  under no page, as their page is in the trash or gone, or they never had
  one (`Brando.Pages.list_fragments_without_page/1`), in the content
  language, as the listing shows pages. Each is a chip with its fragment
  menu, as under a page; the menu's events go to `PageListLive`.

  It loads again when the content language changes, and when the listing's
  entries do (`PageListLive.entries_updated/1` sends `action: :reload`).
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.Pages
  alias BrandoAdmin.Components.Content.List.Row

  def update(%{action: :reload}, socket), do: {:ok, load(socket)}

  def update(assigns, socket) do
    reload? = assigns.content_language != socket.assigns[:content_language]
    socket = assign(socket, assigns)

    socket =
      socket
      |> assign_new(:listings, fn -> listings() end)
      |> then(&if(reload? or not Map.has_key?(&1.assigns, :fragments), do: load(&1), else: &1))

    {:ok, socket}
  end

  # The fragment listing under a page, with ids of its own: a trashed page
  # under the Deleted filter still shows chips of fragments left on it
  defp listings do
    page_listing = Enum.find(Pages.Page.__listings__(), &(&1.name == :default))
    child_listing = Enum.find(page_listing.child_listings, &(&1.name == :fragment_children))
    listing = Enum.find(Pages.Page.__listings__(), &(&1.name == :fragment_children))

    %{
      page: page_listing,
      child: %{child_listing | add: nil},
      chips: %{listing | name: :fragments_without_page}
    }
  end

  defp load(socket) do
    fragments =
      if BrandoAdmin.Authorization.allowed?(:read, Pages.Fragment),
        do:
          socket.assigns.content_language
          |> Pages.list_fragments_without_page()
          |> Brando.Repo.preload(creator: :avatar, updated_by: :avatar),
        else: []

    assign(socket, :fragments, fragments)
  end

  def render(assigns) do
    ~H"""
    <%!-- A listing wrapper of its own, for the chips' listing styles --%>
    <section
      id={@id}
      class={[@fragments != [] && "content-list-wrapper", "fragments-without-page"]}
      aria-labelledby={@fragments != [] && "fragments-without-page-title"}
      hidden={@fragments == []}
    >
      <%= if @fragments != [] do %>
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
              entries={@fragments}
              child_listing={@listings.child}
              listing={@listings.chips}
              parent_listing={@listings.page}
              schema={@schema}
              content_language={@content_language}
              current_user={@current_user}
            />
          </div>
        </div>
      <% end %>
    </section>
    """
  end
end
