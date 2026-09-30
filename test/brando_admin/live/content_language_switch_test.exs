defmodule BrandoAdmin.ContentLanguageSwitchTest do
  # The content language row at the foot of the sidebar: it names the language
  # being edited and opens a list to switch.
  use Brando.LiveCase

  test "names the content language and lists the others on click", %{conn: conn} do
    {:ok, view, html} = live(conn, "/admin/pages")

    assert html =~ "content-language-selector"
    assert html =~ ~r/Content in <strong>[^<]+<\/strong>/
    refute has_element?(view, ".content-language-selector .languages")

    view |> element(".content-language-selector .current-language") |> render_click()
    assert has_element?(view, ".content-language-selector .languages button.current")
    assert view |> element(".content-language-selector .languages") |> render() =~ ~s(role="option")

    view |> element(".content-language-selector .current-language") |> render_click()
    refute has_element?(view, ".content-language-selector .languages")
  end
end
