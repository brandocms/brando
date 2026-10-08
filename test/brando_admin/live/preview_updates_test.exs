defmodule BrandoAdmin.PreviewUpdatesTest do
  use Brando.LiveCase

  alias Brando.LivePreview

  setup %{current_user: user} do
    page = Factory.insert(:page, creator: user, title: "Stored title")
    {:ok, page: page}
  end

  defp open_preview(view) do
    view |> element("button[phx-click=toggle_preview_targets]") |> render_click()
    view |> element("button.preview-choice", "Blocks") |> render_click()
    html = await_selector(view, "iframe[src*='__livepreview']")
    [key] = Regex.run(~r/__livepreview\?key=([A-Za-z0-9_-]+)/, html, capture: :all_but_first)
    Brando.endpoint().subscribe("live_preview:#{key}")
    key
  end

  test "entry edits render the current unsaved value through scheduled block collection", %{conn: conn, page: page} do
    {view, html} = live_form(conn, "/admin/pages/update/#{page.id}")
    key = open_preview(view)
    on_exit(fn -> LivePreview.cleanup_cache(key) end)

    params =
      html
      |> form_params("#page_form_form")
      |> put_in(["page", "title"], "Unsaved title")
      |> Map.put("_target", ["page", "title"])

    view |> element("#page_form_form") |> render_change(params)

    assert_receive %Phoenix.Socket.Broadcast{event: "update", payload: %{html: html}}, 2_000
    assert html =~ "Unsaved title"
    # Only `<main>` travels; the cache keeps the document it came from.
    assert html =~ ~r/\A<main[\s>]/
    assert String.ends_with?(html, "</main>")
    assert {:ok, document} = LivePreview.get_cache(key)
    assert document =~ "<head"
    assert document =~ html
    assert Repo.get!(Brando.Pages.Page, page.id).title == "Stored title"
    refute_receive %Phoenix.Socket.Broadcast{event: "update"}, 75
  end

  for order <- [:main_first, :preview_first] do
    test "preview recovery keeps unsaved input when #{order}", %{conn: conn, page: page} do
      {view, html} = live_form(conn, "/admin/pages/update/#{page.id}")
      key = open_preview(view)
      on_exit(fn -> LivePreview.cleanup_cache(key) end)
      captured = html |> recovery_params("#page_form_form") |> put_in(["page", "title"], "Recovered title")
      kill_live(view)
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")

      main = fn -> view |> element("#page_form_form") |> render_change(captured) end

      preview = fn ->
        [target] = view |> render() |> Floki.parse_document!() |> Floki.attribute("#live-preview-recovery", "phx-target")

        view
        |> with_target(String.to_integer(target))
        |> render_hook("recover_live_preview_state", %{"live_preview" => %{"cache_key" => key}})
      end

      if unquote(order) == :main_first do
        main.()
        preview.()
      else
        preview.()
        refute_receive %Phoenix.Socket.Broadcast{}, 50
        main.()
      end

      assert_receive %Phoenix.Socket.Broadcast{event: "rerender", payload: %{html: html}}, 2_000
      assert html =~ "Recovered title"
      assert LivePreview.get_cache(key) == {:ok, html}
    end
  end

  # An added row changes the entry without a round trip through the browser,
  # so the form refreshes the open preview itself.
  test "adding a page variable updates the open preview", %{conn: conn, page: page} do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    key = open_preview(view)
    on_exit(fn -> LivePreview.cleanup_cache(key) end)
    refute_receive %Phoenix.Socket.Broadcast{event: "update"}, 100

    view |> element("#page_vars-add-entry") |> render_click()
    settle(view)

    assert_receive %Phoenix.Socket.Broadcast{event: "update"}, 2_000
  end
end
