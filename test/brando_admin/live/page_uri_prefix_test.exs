defmodule BrandoAdmin.PageUriPrefixTest do
  # A page resolves by its whole path, so a child of `about` needs the URI
  # `about/team`. The URI input carries the parent's URI as a prefix for the
  # slug it generates from the title; the Slug hook puts it in front.
  use Brando.LiveCase

  alias Brando.Factory
  alias Brando.Pages.Page

  describe "uri_prefix/1" do
    test "is the parent's URI and a slash" do
      parent = Factory.insert(:page, uri: "about", language: "en")

      assert Page.uri_prefix(Ecto.Changeset.change(%Page{}, parent_id: parent.id)) == "about/"
    end

    test "is empty without a parent, or under the homepage" do
      home = Factory.insert(:page, uri: "index", language: "en")

      assert Page.uri_prefix(Ecto.Changeset.change(%Page{})) == ""
      assert Page.uri_prefix(Ecto.Changeset.change(%Page{}, parent_id: home.id)) == ""
    end
  end

  test "the URI input follows the chosen parent", %{conn: conn} do
    parent = Factory.insert(:page, uri: "about", title: "About", language: "en")

    {:ok, view, html} = live(conn, "/admin/pages/create")
    refute html =~ ~s(data-slug-prefix="about/")

    html =
      view
      |> form("#page_form_form")
      |> render_change(%{"page" => %{"parent_id" => to_string(parent.id), "language" => "en"}})

    assert html =~ ~s(data-slug-prefix="about/")
  end
end
