defmodule BrandoAdmin.LivePreviewErrorsTest do
  # A form with errors can't open the live preview. The alert says so, not
  # that saving failed: nothing was saved.
  use Brando.LiveCase

  alias Brando.Factory

  setup %{current_user: user} do
    {:ok, page: Factory.insert(:page, creator: user, title: "Stored title")}
  end

  test "an invalid form says the preview could not open", c do
    {:ok, view, html} = live(c.conn, "/admin/pages/update/#{c.page.id}")

    params = html |> form_params("#page_form_form") |> put_in(["page", "title"], "")
    view |> element("#page_form_form") |> render_change(Map.put(params, "_target", ["page", "title"]))

    view |> with_target(cid_of(view, "#page_form_form")) |> render_hook("open_live_preview", %{})

    preview_notice =
      Gettext.gettext(
        Brando.Gettext,
        "Cannot open Live Preview with errors in form. Please correct marked fields and try again<br><br>Fields marked invalid:"
      )

    assert_push_event(view, "b:alert", %{message: message}, 3_000)
    assert message =~ preview_notice
    refute render(view) =~ "__livepreview"
  end
end
