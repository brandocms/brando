defmodule BrandoAdmin.FormValidationA11yTest do
  # Issue #1996: a failed save marks the field invalid and fills its alert
  # region; correcting the field clears both. The attributes are rendered by
  # the server. Moving focus to the field after the save alert stays in
  # e2e/playwright/tests/accessibility/form-a11y.spec.js.
  use Brando.LiveCase

  defp title_field(view), do: view |> element("#page_title") |> render()

  defp error_text(view) do
    view |> render() |> Floki.parse_document!() |> Floki.find("#page_title-error") |> Floki.text() |> String.trim()
  end

  defp save(view, params) do
    view |> form("#page_form_form", params) |> render_submit()
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form("#page_form_form", params) |> render_submit()
  end

  test "correcting a field after a failed save clears its invalid state and message", %{conn: conn} do
    {view, _html} = live_form(conn, "/admin/pages/create")

    save(view, %{"page" => %{"status" => "published", "title" => ""}})
    assert title_field(view) =~ ~s(aria-invalid="true")
    assert error_text(view) != ""

    view |> form("#page_form_form", %{"page" => %{"title" => "An acceptable title"}}) |> render_change()
    refute title_field(view) =~ "aria-invalid"
    assert error_text(view) == ""
  end
end
