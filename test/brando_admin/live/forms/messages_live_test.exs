defmodule BrandoAdmin.Forms.MessagesLiveTest do
  use Brando.LiveCase

  alias Brando.Forms
  alias Brando.Forms.Messages

  test "the site's messages are edited in each content language", %{conn: conn} do
    {view, html} = live_form(conn, "/admin/config/forms/messages", "messages_form")

    assert html =~ ~s(name="messages[required][no]")
    assert html =~ ~s(name="messages[required][en]")

    view
    |> form("#messages_form_form", %{"messages" => %{"required" => %{"no" => "Må fylles ut.", "en" => "Required."}}})
    |> render_submit()

    assert {"/admin/config/forms", _} = assert_redirect(view, 3_000)
    assert Forms.message(:required, "no") == "Må fylles ut."
    assert Forms.message(:required, "en") == "Required."
    assert Forms.message(:too_long, "no") == Messages.built_in(:too_long, "no")
  end

  test "the forms listing links to them", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/admin/config/forms")
    assert html =~ ~s(href="/admin/config/forms/messages")
  end
end
