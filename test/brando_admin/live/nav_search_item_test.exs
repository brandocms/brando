defmodule BrandoAdmin.NavSearchItemTest do
  # Search is a row of the sidebar's first section: a button that opens the
  # command palette, after Dashboard, never marked as the current page.
  use Brando.LiveCase

  alias BrandoAdmin.Nav

  test "the sidebar's first section has Search right after Dashboard", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/pages")
    nav = find_live_child(view, "brando-nav")

    assert has_element?(
             nav,
             ".navigation-section:first-child dl:nth-of-type(1) a[href='/admin']"
           )

    assert has_element?(
             nav,
             ".navigation-section:first-child dl:nth-of-type(2) button#nav-search[type='button'][aria-haspopup='dialog'][aria-controls='command-palette-dialog']"
           )

    assert nav |> element("#nav-search") |> render() =~ "brando:command-palette:open"
    refute has_element?(nav, "#nav-search.active")
    assert has_element?(nav, "#nav-search .shortcut-mac")
    assert has_element?(nav, "#nav-search .shortcut-other")
  end

  describe "with_search_item/1" do
    test "follows Dashboard when the first section starts with it" do
      dashboard = %{name: "Dashboard", url: "/admin"}
      users = %{name: "Users", url: "/admin/users"}

      assert [%{items: [^dashboard, %{search: true}, ^users]}, %{items: [^users]}] =
               Nav.with_search_item([%{name: "System", items: [dashboard, users]}, %{name: "Content", items: [users]}])
    end

    test "leads the first section otherwise" do
      users = %{name: "Users", url: "/admin/users"}

      assert [%{items: [%{search: true}, ^users]}] = Nav.with_search_item([%{name: "System", items: [users]}])
      assert [%{items: [%{search: true}]}] = Nav.with_search_item([%{name: "System", items: []}])
    end

    test "gets a section of its own when there is no menu" do
      assert [%{name: nil, items: [%{search: true}]}] = Nav.with_search_item([])
    end
  end
end
