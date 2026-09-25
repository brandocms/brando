defmodule BrandoAdmin.FormEntryNotFoundTest do
  # A form for an entry that does not exist (a stale link, or one deleted in
  # another tab) used to raise from its async load. The LiveView died after it
  # had connected, the client rejoined, and the next mount raised again: a crash
  # loop that only ended when the tab was closed.
  use Brando.LiveCase

  test "a missing entry sends the form back to its listing", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/pages/update/0")

    assert_redirect(view, "/admin/pages", 5_000)
  end
end
