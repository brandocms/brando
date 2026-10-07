defmodule BrandoAdmin.ListingCountsLiveTest do
  # #2984: the status filters count their entries under the listing's other
  # filters, and the footer counts, shows the range and picks the page size.
  # This was e2e/playwright/tests/pages/listing-counts.spec.js; all of it is
  # server-rendered, so it runs here against the Pages listing.
  use Brando.LiveCase

  @path "/admin/pages"

  defp pages(prefix, statuses) do
    for {status, i} <- Enum.with_index(statuses, 1) do
      Factory.insert(:page,
        title: "#{prefix} #{i}",
        uri: "#{String.downcase(prefix)}-#{i}",
        language: :en,
        status: status
      )
    end
  end

  defp open(conn, query) do
    {:ok, view, _html} = live(conn, @path <> query)
    await_selector(view, "[data-testid='listing-footer']")
    view
  end

  defp status_button(status), do: ".statuses button[phx-value-status='#{status}']"

  defp count(view, status) do
    view
    |> element(status_button(status) <> " .status-count")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
  end

  defp counts(view, statuses), do: Map.new(statuses, &{&1, count(view, &1)})

  defp rows(view) do
    view |> render() |> Floki.parse_document!() |> Floki.find(".content-list .list-row")
  end

  defp footer(view, test_id) do
    view |> render() |> Floki.parse_document!() |> Floki.find("[data-testid='#{test_id}']")
  end

  defp per_page(view) do
    view |> render() |> Floki.parse_document!() |> Floki.find("[data-testid='listing-footer'] select")
  end

  defp selected_page_size(view) do
    view
    |> per_page()
    |> Floki.find("option[selected]")
    |> Floki.attribute("value")
  end

  test "status filters count the filtered entries and follow a status change", %{conn: conn} do
    pages("Counted", [:draft, :draft, :pending])
    view = open(conn, "?filter:title=Counted")

    assert counts(view, ~w(draft pending published deleted)) ==
             %{"draft" => "2", "pending" => "1", "published" => "0", "deleted" => "0"}

    # A status without entries stays, muted
    assert has_element?(view, status_button("published") <> ".is-empty")
    refute has_element?(view, status_button("draft") <> ".is-empty")

    # The counts ignore the status filter itself
    view |> element(status_button("draft")) |> render_click()
    assert assert_patch(view) =~ "status=draft"
    assert length(rows(view)) == 2
    assert count(view, "pending") == "1"

    # Publishing one from the listing moves it to the other count
    [dropdown | _] = view |> render() |> Floki.parse_document!() |> Floki.find(".list-row .status-dropdown")
    [dropdown_id] = Floki.attribute(dropdown, "id")
    view |> element("##{dropdown_id} button", "Published") |> render_click()

    assert count(view, "draft") == "1"
    assert count(view, "published") == "1"
    refute has_element?(view, status_button("published") <> ".is-empty")
  end

  test "the footer shows the range and changes the page size", %{conn: conn} do
    pages("Paged", List.duplicate(:published, 30))
    view = open(conn, "?filter:title=Paged")

    assert view |> footer("listing-count") |> Floki.text() =~ "30"
    range = view |> footer("listing-range") |> Floki.text()
    assert range =~ "1–25"
    assert range =~ "30"
    assert length(rows(view)) == 25
    assert selected_page_size(view) == ["25"]

    view |> element("[data-testid='listing-footer'] form") |> render_change(%{"limit" => "50"})
    assert assert_patch(view) =~ "limit=50"
    assert length(rows(view)) == 30
    assert footer(view, "listing-range") == []
    assert selected_page_size(view) == ["50"]

    view |> element("[data-testid='listing-footer'] form") |> render_change(%{"limit" => "0"})
    assert assert_patch(view) =~ "limit=0"
    assert selected_page_size(view) == ["0"]
    assert length(rows(view)) == 30
  end

  test "an empty listing reads 0 entries without a range or page size", %{conn: conn} do
    view = open(conn, "?filter:title=no-such-page")

    assert view |> footer("listing-count") |> Floki.text() =~ "0"
    assert footer(view, "listing-range") == []
    assert per_page(view) == []

    assert view |> render() |> Floki.parse_document!() |> Floki.find(".statuses .status-count") |> Enum.map(&Floki.text/1) ==
             ["0", "0", "0", "0", "0"]
  end
end
