defmodule BrandoAdmin.ListingFilterEnterTest do
  # Enter in a listing's text filter (`submit_filter` in `Content.List`) on the
  # test Article's `:filters` listing, whose "Title" filter is a text filter.
  use Brando.LiveCase

  alias Brando.SyncTest

  @path "/admin/articles/filters"
  @form "#listing-filter-form-Elixir\\.Brando\\.SyncTest\\.Article-title"

  setup %{current_user: user} do
    articles = Map.new(~w(Alpha Alpine Gamma), &{&1, article(user, &1)})
    {:ok, articles: articles}
  end

  defp article(user, title) do
    {:ok, article} =
      SyncTest.create_article(
        %{title: title, slug: String.downcase(title), language: "en", status: "published"},
        user
      )

    article
  end

  defp open(conn) do
    {:ok, view, _html} = live(conn, @path)
    await_selector(view, "[data-testid='listing-footer']")
    view
  end

  defp enter(view, query), do: view |> form(@form, %{q: query}) |> render_submit()

  test "Enter on a filter that leaves one entry opens it", %{conn: conn, articles: articles} do
    view = open(conn)

    html = enter(view, "gamma")

    # The render that carries the event shows the row it opens from
    assert html |> Floki.parse_document!() |> Floki.find(".content-list .list-row") |> length() == 1
    url = "/admin/articles/update/#{articles["Gamma"].id}"
    assert_push_event(view, "brando:open_entry", %{listing: "listing-filters", url: ^url})
  end

  test "Enter on a filter that leaves several entries applies it and opens nothing", %{conn: conn} do
    view = open(conn)

    enter(view, "alp")

    assert_patch(view, @path <> "?filter:title=alp")
    refute_push_event(view, "brando:open_entry", %{})
  end

  test "Enter on a filter that leaves none, or on an empty filter, opens nothing", %{conn: conn} do
    view = open(conn)

    enter(view, "zeta")
    assert_patch(view, @path <> "?filter:title=zeta")

    enter(view, "")
    assert_patch(view, @path)

    refute_push_event(view, "brando:open_entry", %{})
  end

  test "Enter does not open an entry the user may not edit" do
    user = Brando.Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
    conn = Brando.Test.log_in_user(Phoenix.ConnTest.build_conn(), user)
    view = open(conn)

    enter(view, "gamma")

    assert_patch(view, @path <> "?filter:title=gamma")
    refute_push_event(view, "brando:open_entry", %{})
  end
end
