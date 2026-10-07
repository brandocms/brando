defmodule BrandoAdmin.ListingFiltersLiveTest do
  # A listing's text, boolean and select filters, alone and together, reset,
  # and read back from the URL. These were browser tests on the E2E project's
  # Projects listing (e2e/playwright/tests/projects/listing-filters.spec.js).
  # The test Article's `:filters` listing declares the same three filters
  # with the same kinds of query clauses, and the controls are all
  # server-rendered.
  use Brando.LiveCase

  alias Brando.SyncTest

  @path "/admin/articles/filters"

  # As the E2E data: three published entries, and one more that the boolean
  # filter picks out.
  setup %{current_user: user} do
    for title <- ~w(Alpha Beta Gamma) do
      article(user, title, featured: false)
    end

    article(user, "Featured Article", featured: true)
    :ok
  end

  defp article(user, title, opts) do
    {:ok, article} =
      SyncTest.create_article(
        %{
          title: title,
          slug: title |> String.downcase() |> String.replace(" ", "-"),
          language: "en",
          status: "published",
          featured: opts[:featured]
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

  defp rows(view) do
    view |> render() |> Floki.parse_document!() |> Floki.find(".content-list .list-row") |> Enum.map(&Floki.text/1)
  end

  defp row_count(view), do: length(rows(view))
  defp listed?(view, title), do: Enum.any?(rows(view), &String.contains?(&1, title))

  defp toggle_featured(view) do
    view |> element(".boolean-filter input[phx-value-filter='featured']") |> render_click()
    assert_patch(view)
  end

  defp select_status(view, value) do
    view |> element(".list-filter-select select") |> render_change(%{"filter" => %{"status_filter" => value}})
    assert_patch(view)
  end

  test "the advanced filters bar shows the boolean and the select filter", %{conn: conn} do
    view = open(conn)

    assert has_element?(view, ".advanced-filters-bar")
    assert has_element?(view, ".advanced-filters-bar .boolean-filter", "Featured only")
    assert has_element?(view, ".advanced-filters-bar .list-filter-select label", "Status")
  end

  test "the boolean filter narrows the list and toggles off again", %{conn: conn} do
    view = open(conn)
    assert row_count(view) == 4
    assert listed?(view, "Featured Article")

    assert toggle_featured(view) =~ "filter:featured=true"
    assert row_count(view) == 1
    assert listed?(view, "Featured Article")

    toggle_featured(view)
    assert row_count(view) == 4
  end

  test "the select filter filters by status", %{conn: conn} do
    view = open(conn)
    assert row_count(view) == 4

    assert select_status(view, "published") =~ "filter:status_filter=published"
    assert row_count(view) == 4

    select_status(view, "draft")
    assert row_count(view) == 0
    assert render(view) =~ "No matching entries found"

    select_status(view, "")
    assert row_count(view) == 4
  end

  test "the text filter in the header still filters", %{conn: conn} do
    view = open(conn)
    assert row_count(view) == 4

    view |> element(".list-tools .filters form") |> render_change(%{"q" => "Featured", "filter" => "title"})
    assert row_count(view) == 1
    assert listed?(view, "Featured Article")
  end

  test "filters combine with AND", %{conn: conn} do
    view = open(conn)

    toggle_featured(view)
    assert row_count(view) == 1
    assert listed?(view, "Featured Article")

    select_status(view, "published")
    assert row_count(view) == 1
    assert listed?(view, "Featured Article")

    select_status(view, "draft")
    assert row_count(view) == 0
    assert render(view) =~ "No matching entries found"
  end

  test "the reset button clears the advanced filters", %{conn: conn} do
    view = open(conn)
    assert row_count(view) == 4
    refute has_element?(view, ".reset-filters-btn")

    toggle_featured(view)
    assert row_count(view) == 1

    view |> element(".reset-filters-btn") |> render_click()
    assert_patch(view)
    assert row_count(view) == 4
  end

  test "filters are read back from the URL", %{conn: conn} do
    view = open(conn, "?filter:featured=true&filter:status_filter=published")

    assert has_element?(view, ".boolean-filter input[checked]")
    assert view |> element(".list-filter-select select option[selected]") |> render() =~ ~s(value="published")
    assert row_count(view) == 1
    assert listed?(view, "Featured Article")
  end
end
