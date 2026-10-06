defmodule BrandoAdmin.ListingUserContextTest do
  # A listing that depends on who is looking: user-aware filters, decorate and
  # row components, function sorts, and selection actions with a confirmation
  # or a visibility rule. The listing is `:user_context` on Brando.SyncTest.Article.
  use Brando.LiveCase

  alias Brando.SyncTest

  @path "/admin/articles/user-context"

  setup %{current_user: user} do
    other = Factory.insert(:random_user)

    {:ok, short} = SyncTest.create_article(%{title: "Short", slug: "short", language: "en", status: "draft"}, user)

    {:ok, long} =
      SyncTest.create_article(%{title: "A much longer title", slug: "long", language: "en", status: "draft"}, other)

    %{short: short, long: long}
  end

  defp rows(html) do
    html |> Floki.parse_document!() |> Floki.find(".user-context-row") |> Enum.map(&Floki.text/1)
  end

  test "the row component and decorate get the signed-in user", %{conn: conn, current_user: user} do
    {:ok, view, _html} = live(conn, @path)
    html = await_selector(view, ".user-context-row")

    assert [_ | _] = rows = html |> Floki.parse_document!() |> Floki.find(".user-context-row")

    for row <- rows do
      assert Floki.attribute(row, "data-viewer") == [user.name]
      assert Floki.attribute(row, "data-user") == [user.name]
    end
  end

  test "a filter clause gets the signed-in user", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path <> "?filter:mine=true")
    assert rows(await_selector(view, ".user-context-row")) == ["Short"]
  end

  test "a sort can order by a function of the query", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)
    # The first sort is the default
    assert rows(await_selector(view, ".user-context-row")) == ["A much longer title", "Short"]

    {:ok, view, _html} = live(conn, @path <> "?sort=oldest")
    assert rows(await_selector(view, ".user-context-row")) == ["Short", "A much longer title"]

    {:ok, view, _html} = live(conn, @path <> "?sort=longest")
    assert rows(await_selector(view, ".user-context-row")) == ["A much longer title", "Short"]
  end

  test "choosing a function sort puts its key in the URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path <> "?sort=oldest")
    await_selector(view, ".user-context-row")

    view |> element("#sorts-dropdown [phx-value-sort_key='longest']") |> render_click()
    assert_patch(view, @path <> "?sort=longest")
  end

  test "selection actions confirm, and show only to users they are meant for", %{conn: conn} = c do
    {:ok, view, _html} = live(conn, @path)
    await_selector(view, ".user-context-row")

    view |> element("#list-row-#{c.short.id}") |> render_click(%{"shift" => true})
    html = await_selector(view, ".selected-rows:not(.hidden)")

    refute html =~ "Never"
    assert html =~ "Named"

    [button] =
      html |> Floki.parse_document!() |> Floki.find(".selection-actions button[phx-hook='Brando.ConfirmClick']")

    assert Floki.attribute(button, "phx-confirm-click-message") == ["Feature the selected articles?"]
    assert Floki.text(button) =~ "Feature"

    # The dialog runs the event with the selected ids
    [js] = Floki.attribute(button, "phx-confirm-click")
    assert js =~ "feature_selected"
    assert js =~ ~s("ids":"[#{c.short.id}]")
  end

  test "an action without a confirmation is a plain button", %{conn: conn} = c do
    {:ok, view, _html} = live(conn, @path)
    await_selector(view, ".user-context-row")
    view |> element("#list-row-#{c.short.id}") |> render_click(%{"shift" => true})

    assert has_element?(view, ".selection-actions button[phx-click='named_selected']")
  end

  test "outside a listing, the filter context's user is whoever list_* is given" do
    all = fn args -> args |> SyncTest.list_articles() |> elem(1) |> Enum.map(& &1.title) |> Enum.sort() end

    assert all.(%{filter: %{mine: "true"}}) == ["A much longer title", "Short"]
  end

  test "a listing's sort may be a function of the query" do
    assert {:ok, [first | _]} = SyncTest.list_articles(%{order: &Brando.SyncTest.ArticleListing.longest_title_first/1})
    assert first.title == "A much longer title"
  end

  test "parameters the listing does not know are ignored", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path <> "?hide_incomplete=0&page=1")
    assert rows(await_selector(view, ".user-context-row")) == ["A much longer title", "Short"]
  end
end
