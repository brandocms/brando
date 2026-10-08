defmodule BrandoAdmin.HistoryButtonTest do
  # An entry that was never saved has no revisions. History says so and
  # leaves the drawer shut: it used to open it anyway, so closing it asked
  # the server again and repeated the notice.
  use Brando.LiveCase

  alias Brando.Factory

  defp history_click(html) do
    html |> Floki.parse_document!() |> Floki.find(".form-tool-revisions") |> Floki.attribute("phx-click") |> hd()
  end

  test "on a new entry, History gives the notice and doesn't open the drawer", %{conn: conn} do
    {view, html} = live_form(conn, "/admin/pages/create")

    click = history_click(html)
    assert click =~ "toggle_revisions_drawer_status"
    refute click =~ "revisions-drawer"

    view |> element(".form-tool-revisions") |> render_click()
    assert_push_event(view, "b:alert", %{type: "error"})
  end

  test "on a saved entry, History opens the drawer", %{conn: conn} do
    page = Factory.insert(:page, language: "en")
    {_view, html} = live_form(conn, "/admin/pages/update/#{page.id}")

    click = history_click(html)
    assert click =~ "toggle_revisions_drawer_status"
    assert click =~ "revisions-drawer"
  end
end
