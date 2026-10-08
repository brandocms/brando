defmodule BrandoAdmin.ListingSavedViewsLiveTest do
  # The listing toolbar's Views menu (`Content.List.SavedViews`) on the test
  # Article's `:filters` listing: a text, a boolean and a select filter.
  use Brando.LiveCase

  alias Brando.ListingViews
  alias Brando.SyncTest
  alias Brando.SyncTest.Article

  @path "/admin/articles/filters"
  @menu "#listing-filters-views-menu-items"

  setup %{current_user: user} do
    for title <- ~w(Alpha Beta Gamma), do: article(user, title, false)
    article(user, "Featured Article", true)
    :ok
  end

  defp article(user, title, featured) do
    {:ok, article} =
      SyncTest.create_article(
        %{
          title: title,
          slug: String.downcase(title) |> String.replace(" ", "-"),
          language: "en",
          status: "published",
          featured: featured
        },
        user
      )

    article
  end

  defp open(conn, query \\ "") do
    {:ok, view, _html} = live(conn, @path <> query)
    await_selector(view, "[data-testid='listing-footer']")
    view
  end

  defp rows(view), do: view |> render() |> Floki.parse_document!() |> Floki.find(".content-list .list-row") |> length()

  defp saved(user, name, params, attrs \\ %{}) do
    {:ok, view} =
      ListingViews.create_view(user, Article, :filters, Map.merge(%{"name" => name, "params" => params}, attrs))

    view
  end

  defp editor(conn_role \\ :editor) do
    user = Brando.Factory.insert(:random_user, role: conn_role, config: %Brando.Users.UserConfig{})
    {user, Brando.Test.log_in_user(Phoenix.ConnTest.build_conn(), user)}
  end

  defp option(view, saved_view), do: element(view, "#{@menu} [data-testid='saved-view'][phx-value-id='#{saved_view.id}']")
  defp action(view, event), do: element(view, "#{@menu} button[phx-click='#{event}']")

  defp trigger_text(view),
    do: view |> element("[data-testid='saved-views-trigger']") |> render() |> Floki.parse_fragment!() |> Floki.text()

  test "saves the listing's current filters under a name and selects the new view", %{conn: conn, current_user: user} do
    view = open(conn, "?filter:featured=true&page=1")
    assert rows(view) == 1

    view |> action("open_save") |> render_click()
    assert has_element?(view, "[data-testid='saved-view-dialog']")

    view
    |> form("#listing-filters-views-form", view: %{name: "Featured", shared: "false"})
    |> render_submit()

    assert [saved] = ListingViews.list_views(user, Article, :filters)
    assert %{name: "Featured", shared: false, params: %{"filter:featured" => "true"}} = saved

    assert_patch(view, @path <> "?filter:featured=true&view=#{saved.id}")
    refute has_element?(view, "[data-testid='saved-view-dialog']")
    assert trigger_text(view) =~ "Featured"
    assert has_element?(view, "#{@menu} [aria-current='true']", "Featured")
  end

  test "a name is required, and the dialog says so", %{conn: conn, current_user: user} do
    view = open(conn)
    view |> action("open_save") |> render_click()

    html = view |> form("#listing-filters-views-form", view: %{name: " "}) |> render_submit()

    assert html =~ "saved-views-error"
    assert has_element?(view, "[data-testid='saved-view-dialog']")
    assert ListingViews.list_views(user, Article, :filters) == []
  end

  test "applying a view navigates to its parameters", %{conn: conn, current_user: user} do
    saved = saved(user, "Featured", %{"filter:featured" => "true", "limit" => "50"})
    view = open(conn)
    assert rows(view) == 4

    view |> option(saved) |> render_click()

    assert_patch(view, @path <> "?filter:featured=true&limit=50&view=#{saved.id}")
    assert rows(view) == 1
    assert trigger_text(view) =~ "Featured"
  end

  test "a changed view can be updated with what the listing shows now", %{conn: conn, current_user: user} do
    saved = saved(user, "Drafts", %{"filter:status_filter" => "draft"})
    view = open(conn, "?filter:status_filter=draft&view=#{saved.id}")
    refute has_element?(view, "#{@menu} button[phx-click='update']")

    view |> element(".list-filter-select select") |> render_change(%{"filter" => %{"status_filter" => "published"}})
    assert_patch(view)
    assert trigger_text(view) =~ "changed"

    view |> action("update") |> render_click()

    assert {:ok, %{params: %{"filter:status_filter" => "published"}}} =
             ListingViews.get_view(user, Article, :filters, saved.id)

    refute has_element?(view, "#{@menu} button[phx-click='update']")
  end

  test "renames a view", %{conn: conn, current_user: user} do
    saved = saved(user, "Old", %{"filter:featured" => "true"})
    view = open(conn, "?filter:featured=true&view=#{saved.id}")

    view |> action("open_rename") |> render_click()
    view |> form("#listing-filters-views-form", view: %{name: "New"}) |> render_submit()

    assert {:ok, %{name: "New"}} = ListingViews.get_view(user, Article, :filters, saved.id)
    assert trigger_text(view) =~ "New"
  end

  test "shared views are seen by others, personal ones are not", %{conn: conn, current_user: user} do
    shared = saved(user, "Team", %{"filter:featured" => "true"}, %{"shared" => true})
    personal = saved(user, "Private", %{"limit" => "50"})
    {_colleague, colleague_conn} = editor()

    view = open(colleague_conn)
    assert has_element?(view, "#{@menu} [data-testid='saved-view']", "Team")
    refute has_element?(view, "#{@menu} [data-testid='saved-view']", "Private")

    # Selected, someone else's shared view can be used, but not changed
    view |> option(shared) |> render_click()
    assert_patch(view)

    for event <- ~w(open_rename delete share) do
      refute has_element?(view, "#{@menu} button[phx-click='#{event}']")
    end

    assert has_element?(view, "#{@menu} button[phx-click='set_default']")

    # The owner shares from the menu; the personal view becomes the team's
    owner = open(conn, "?limit=50&view=#{personal.id}")
    owner |> element("#{@menu} button[phx-click='share']") |> render_click()
    assert {:ok, %{shared: true}} = ListingViews.get_view(user, Article, :filters, personal.id)
  end

  test "deletes the view in use and leaves the listing as it is", %{conn: conn, current_user: user} do
    saved = saved(user, "Featured", %{"filter:featured" => "true"})
    view = open(conn, "?filter:featured=true&view=#{saved.id}")

    view |> action("delete") |> render_click()

    assert ListingViews.list_views(user, Article, :filters) == []
    assert_patch(view, @path <> "?filter:featured=true")
    assert rows(view) == 1
    refute has_element?(view, "#{@menu} [data-testid='saved-view']")
  end

  test "a stale view drops what the listing no longer has, without crashing", %{conn: conn, current_user: user} do
    stale =
      saved(user, "Stale", %{
        "filter:removed_filter" => "x",
        "filter:status_filter" => "archived",
        "filter:featured" => "true",
        "status" => "gone",
        "sort" => "vanished",
        "limit" => "many"
      })

    view = open(conn)
    view |> option(stale) |> render_click()

    assert_patch(view, @path <> "?filter:featured=true&view=#{stale.id}")
    assert rows(view) == 1

    # Opened from an old link too
    view = open(conn, "?filter:featured=true&view=#{stale.id}")
    assert trigger_text(view) =~ "Stale"
  end

  test "opens the listing with the person's default view, once", %{conn: conn, current_user: user} do
    saved = saved(user, "Featured", %{"filter:featured" => "true"})
    {:ok, _} = ListingViews.set_default(user, saved)

    view = open(conn)
    assert_patch(view, @path <> "?filter:featured=true&view=#{saved.id}")
    assert rows(view) == 1
    assert has_element?(view, "#{@menu} [data-testid='saved-view'] .badge", "Default")

    # Emptied by the person, the listing stays empty
    view |> element(".boolean-filter input[phx-value-filter='featured']") |> render_click()
    assert_patch(view)
    assert rows(view) == 4

    # A link with parameters opens as it says
    view = open(conn, "?limit=25")
    assert rows(view) == 4

    view = open(conn, "?filter:featured=true&view=#{saved.id}")
    view |> action("clear_default") |> render_click()
    assert ListingViews.default_view(user, Article, :filters) == nil
  end

  test "the menu's link, with the listing's own query, opens the default view too", %{conn: conn, current_user: user} do
    {:ok, saved} = ListingViews.create_view(user, Article, :default, %{"name" => "Big pages", "params" => %{"limit" => "50"}})
    {:ok, _} = ListingViews.set_default(user, saved)

    # As BrandoAdmin.Menu links to it: the default listing's `order`
    {:ok, view, _html} = live(conn, "/admin/articles?order=asc+id")
    assert_patch(view, "/admin/articles?limit=50&view=#{saved.id}")

    # Another order is a choice of its own
    {:ok, view, _html} = live(conn, "/admin/articles?order=desc+id")
    refute trigger_text(view) =~ "Big pages"
  end

  test "picks a view to open the listing with", %{conn: conn, current_user: user} do
    saved = saved(user, "Featured", %{"filter:featured" => "true"})
    view = open(conn, "?filter:featured=true&view=#{saved.id}")

    view |> action("set_default") |> render_click()

    assert %{id: id} = ListingViews.default_view(user, Article, :filters)
    assert id == saved.id
  end
end
