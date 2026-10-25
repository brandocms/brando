defmodule BrandoAdmin.CommandPaletteLiveTest do
  use Brando.LiveCase

  # Without motion the palette closes at once, so the search its input
  # debounced can arrive after `close`. It must not render results for a
  # closed palette: those rows, emptied and refilled around the next
  # opening's reply, broke LiveView's client patch and left Search loading.
  test "a search before opening or after closing renders nothing until the palette opens", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/pages")
    palette = find_live_child(view, "brando-command-palette")

    # Closed from the start: form recovery's search on a reconnect fills nothing
    palette |> element("#command-palette-form") |> render_change(%{"q" => "Pages"})
    refute has_element?(palette, "[id^='command-palette-group-']")

    render_hook(palette, "open", %{"recent" => [], "path" => "/admin/pages"})
    assert has_element?(palette, "#command-palette-results[data-query='']")
    assert has_element?(palette, "[id^='command-palette-group-']")

    render_hook(palette, "close", %{})
    refute has_element?(palette, "[id^='command-palette-group-']")

    palette |> element("#command-palette-form") |> render_change(%{"q" => "Pages"})
    refute has_element?(palette, "#command-palette-results[data-query='Pages']")
    refute has_element?(palette, "[id^='command-palette-group-']")

    # The next opening searches again
    render_hook(palette, "open", %{"recent" => [], "path" => "/admin/pages"})
    palette |> element("#command-palette-form") |> render_change(%{"q" => "Pages"})
    assert has_element?(palette, "#command-palette-results[data-query='Pages']")
  end
end
