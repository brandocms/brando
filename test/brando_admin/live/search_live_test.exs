defmodule BrandoAdmin.SearchLiveTest do
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.{Catalog, Groups, Migration, Scope}
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Search
  alias Brando.SyncTest.Article

  setup do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
  end

  defp page(user, title, attrs \\ []) do
    page = Factory.insert(:page, Keyword.merge([title: title, creator: user, status: :published, language: :en], attrs))
    :ok = Search.index_entry(Page, page.id)
    page
  end

  defp article(user, title, subtitle) do
    article =
      Repo.insert!(%Article{
        title: title,
        slug: "article-#{System.unique_integer([:positive])}",
        subtitle: subtitle,
        language: :en,
        status: :published,
        creator_id: user.id
      })

    :ok = Search.index_entry(Article, article.id)
    article
  end

  test "searches titles and content, and marks what matched", %{conn: conn, current_user: user} do
    page = page(user, "Sommerro", meta_description: "A hotel by the fjord in Oslo")
    page(user, "Villa Tide", meta_description: "Nothing to see")

    {:ok, view, _} = live(conn, "/admin/search?q=fjord")

    assert has_element?(view, "h1", "Search")
    assert has_element?(view, "#search-input[value=fjord]")
    assert has_element?(view, ".search-row a[href='/admin/pages/update/#{page.id}'] .search-title", "Sommerro")
    assert has_element?(view, ".search-row .search-snippet mark", "fjord")
    assert has_element?(view, ".search-row .search-status[data-status=published]", "Published")
    refute has_element?(view, ".search-title", "Villa Tide")
    assert has_element?(view, "#search-results-count", "1 result")
  end

  test "a title or text that looks like markup is shown as text", %{conn: conn, current_user: user} do
    page(user, "<script>alert('x')</script> Sommerro", meta_description: "<img src=x onerror=alert(1)> fjord")

    {:ok, view, html} = live(conn, "/admin/search?q=sommerro")

    refute html =~ "<script>alert"
    refute render(view) =~ "<img src=x"
    assert has_element?(view, ".search-title", "<script>alert('x')</script> Sommerro")

    {:ok, view, _} = live(conn, "/admin/search?q=fjord")
    refute render(view) =~ "<img src=x"
    assert has_element?(view, ".search-snippet mark", "fjord")
  end

  test "filters live in the URL, and only known values count", %{conn: conn, current_user: user} do
    page(user, "Sommerro published")
    page(user, "Sommerro draft", status: :draft)
    page(user, "Sommerro norsk", language: :no)

    {:ok, view, _} = live(conn, "/admin/search?q=sommerro")
    assert has_element?(view, "#search-results-count", "3 results")
    assert has_element?(view, "#search-type option[value='pages.page']", "(3)")

    view |> form("#search-form", %{q: "sommerro", status: "draft"}) |> render_change()
    assert_patch(view, "/admin/search?q=sommerro&status=draft")
    assert has_element?(view, ".search-title", "Sommerro draft")
    refute has_element?(view, ".search-title", "Sommerro published")

    view |> form("#search-form", %{q: "sommerro", status: "", language: "no"}) |> render_change()
    assert_patch(view, "/admin/search?q=sommerro&language=no")
    assert has_element?(view, ".search-title", "Sommerro norsk")
    assert has_element?(view, "#search-results-count", "1 result")

    # Anything else is left out
    {:ok, view, _} = live(conn, "/admin/search?q=sommerro&status=gone&language=xx&type=evil&sort=drop&page=-3")
    assert has_element?(view, "#search-results-count", "3 results")
    assert has_element?(view, "#search-sort option[value=relevance][selected]")
  end

  test "pages of twenty", %{conn: conn, current_user: user} do
    for n <- 1..23, do: page(user, "Sommerro #{n}")

    {:ok, view, _} = live(conn, "/admin/search?q=sommerro")
    assert view |> element("#search-list") |> render() |> String.split("search-row-body") |> length() == 21
    assert has_element?(view, ".search-pages a[aria-current=page]", "1")

    view |> element(".search-pages a[rel=next]") |> render_click()
    assert_patch(view, "/admin/search?q=sommerro&page=2")
    assert view |> element("#search-list") |> render() |> String.split("search-row-body") |> length() == 4
  end

  test "before a search and when nothing matches", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/search")
    assert has_element?(view, "#search-start")

    {:ok, view, _} = live(conn, "/admin/search?q=zzqx")
    assert has_element?(view, "#search-none", "zzqx")
  end

  describe "with groups" do
    setup %{current_user: owner} do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Migration.run()
      editor = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
      %{scope: Scope.standalone(owner), editor: editor}
    end

    defp grant(c, keys) do
      {:ok, group} = Groups.create(c.scope, %{name: "Search #{System.unique_integer([:positive])}"}, keys)
      {:ok, :ok} = Groups.add_member(c.scope, group.id, c.editor.id)
      group
    end

    test "a type the user may not read gives no results or counts, even when filtered for", c do
      page = page(c.current_user, "Lighthouse page")
      article(c.current_user, "Lighthouse article", "By the lighthouse")

      grant(c, [Catalog.get(:access, :backend).key, Catalog.get(:read, Page).key, Catalog.get(:update, Page).key])
      conn = log_in_user(build_conn(), c.editor)

      {:ok, view, _} = live(conn, "/admin/search?q=lighthouse")
      assert has_element?(view, "#search-results-count", "1 result")
      assert has_element?(view, ".search-row a[href='/admin/pages/update/#{page.id}']")
      refute has_element?(view, ".search-title", "Lighthouse article")
      refute has_element?(view, "#search-type option[value='synctest.article']")
      assert has_element?(view, "#search-type option", "(1)")

      {:ok, view, _} = live(conn, "/admin/search?q=lighthouse&type=synctest.article")
      refute has_element?(view, ".search-title", "Lighthouse article")
      assert has_element?(view, "#search-results-count", "1 result")

      # Text only in the article's content finds nothing either
      {:ok, view, _} = live(conn, "/admin/search?q=by+the+lighthouse")
      refute has_element?(view, ".search-title", "Lighthouse article")
    end

    test "an entry the user may read but not edit is listed without a link", c do
      page(c.current_user, "Lighthouse page")
      grant(c, [Catalog.get(:access, :backend).key, Catalog.get(:read, Page).key])

      {:ok, view, _} = live(log_in_user(build_conn(), c.editor), "/admin/search?q=lighthouse")
      assert has_element?(view, ".search-row div.search-row-body .search-title", "Lighthouse page")
      refute has_element?(view, ".search-row a.search-row-body")
    end
  end

  describe "Utilities" do
    test "rebuilds the index and says how many entries it holds", %{conn: conn, current_user: user} do
      Factory.insert(:page, title: "Never indexed", creator: user)
      {:ok, view, _} = live(conn, "/admin/config/utils")
      assert has_element?(view, "#utils-search-index-state", "0 entries in the index")

      view |> element("#utils-search-index button", "Rebuild search index") |> render_click()
      assert has_element?(view, "#utils-search-index-state", "1 entry in the index")
      assert Repo.aggregate(from(d in Brando.Search.Document, where: d.title == "Never indexed"), :count) == 1
    end
  end
end
