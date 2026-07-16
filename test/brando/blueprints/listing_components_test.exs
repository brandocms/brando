defmodule Brando.Blueprint.ListingComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Blueprint.Listings.Components
  alias Brando.Blueprint.Listings.Components.Children
  alias Brando.Blueprint.Listings.Components.Core
  alias Brando.Blueprint.Listings.Components.Cover
  alias Brando.Pages.Page
  alias BrandoAdmin.Components.ChildListingButton
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Content.List.Row
  alias BrandoAdmin.Components.Image

  test "keeps core compatibility wrappers byte-for-byte equivalent" do
    Gettext.put_locale("no")

    i18n_attrs = %{map: %{"en" => "Hello", "no" => "Hei"}}
    assert render_component(&Core.i18n/1, i18n_attrs) == render_component(&Components.i18n/1, i18n_attrs)

    url_attrs = %{entry: %Page{id: 1, status: :draft, language: "en", uri: "index"}}
    assert render_component(&Core.url/1, url_attrs) == render_component(&Components.url/1, url_attrs)
  end

  test "keeps cover and image compatibility wrappers byte-for-byte equivalent" do
    cover_attrs = %{image: nil, columns: 2, size: :thumb}
    assert render_component(&Cover.cover/1, cover_attrs) == render_component(&Components.cover/1, cover_attrs)

    image_attrs = %{image: nil, size: :thumb}
    assert render_component(&Image.image/1, image_attrs) == render_component(&Content.image/1, image_attrs)
  end

  test "keeps the children compatibility wrapper byte-for-byte equivalent" do
    attrs = %{entry: %{id: 42, children: [%{}, %{}]}, fields: [:children]}

    assert render_component(&Children.children_button/1, attrs) ==
             render_component(&Components.children_button/1, attrs)
  end

  test "renders a stateless child toggle with the aggregate child count" do
    html =
      render_component(&ChildListingButton.children_button/1, %{
        entry: %{id: 42, children: [%{}, %{}], fragments: [%{}]},
        fields: [:children, :fragments],
        target: "#list-row-42"
      })

    assert html =~ ~s(id="children-button-42")
    assert html =~ "+ 3"
    assert html =~ "toggle_children"
    assert html =~ ~s(aria-expanded="false")
  end

  test "listing rows toggle only child fields that exist on the entry" do
    socket =
      %Phoenix.LiveView.Socket{}
      |> Phoenix.Component.assign(:entry, %{children: [%{}], title: "Parent"})
      |> Phoenix.Component.assign(:show_children, false)
      |> Phoenix.Component.assign(:child_fields, [])

    assert {:noreply, toggled_socket} =
             Row.handle_event(
               "toggle_children",
               %{"fields" => ["children", "unknown", "children"]},
               socket
             )

    assert toggled_socket.assigns.show_children
    assert toggled_socket.assigns.child_fields == [:children]

    assert {:noreply, closed_socket} =
             Row.handle_event("toggle_children", %{"fields" => ["children"]}, toggled_socket)

    refute closed_socket.assigns.show_children
  end
end
