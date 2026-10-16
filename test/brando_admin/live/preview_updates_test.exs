defmodule BrandoAdmin.PreviewUpdatesTest do
  use Brando.LiveCase

  alias Brando.LivePreview

  setup %{current_user: user} do
    page = Factory.insert(:page, creator: user, title: "Stored title")
    {:ok, page: page}
  end

  defp open_preview(view, choice \\ "Blocks") do
    view |> element("button[phx-click=toggle_preview_targets]") |> render_click()
    view |> element("button.preview-choice", choice) |> render_click()
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

  # The layout's header and footer sit outside <main>, which is all an
  # ordinary update carries, and read assigns cached for the session.
  test "a field in rerender_on_change refreshes its assigns and the layout around <main>", c do
    {view, html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}")
    key = open_preview(view, "Localized")
    on_exit(fn -> LivePreview.cleanup_cache(key) end)
    assert {:ok, document} = LivePreview.get_cache(key)
    assert document =~ "<header>greeting:en</header>"

    params =
      html
      |> form_params("#page_form_form")
      |> put_in(["page", "language"], "no")
      |> Map.put("_target", ["page", "language"])

    view |> element("#page_form_form") |> render_change(params)

    assert_receive %Phoenix.Socket.Broadcast{event: "rerender", payload: %{html: html}}, 3_000
    assert html =~ "<header>greeting:no</header>"
    assert html =~ "<footer>farewell:no</footer>"
    refute_receive %Phoenix.Socket.Broadcast{event: "update"}, 75
  end

  # The layout's footer reads the page variables' keys (test_helper.exs).
  test "a subform in rerender_on_change follows its rows and the fields in them", c do
    {view, _html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}")
    key = open_preview(view, "Localized")
    on_exit(fn -> LivePreview.cleanup_cache(key) end)

    view |> element("#page_vars-add-entry") |> render_click()
    settle(view)

    assert_receive %Phoenix.Socket.Broadcast{event: "rerender", payload: %{html: html}}, 3_000
    assert html =~ "<footer>farewell:en key</footer>"

    params =
      view
      |> render()
      |> form_params("#page_form_form")
      |> put_in(["page", "vars", "0", "key"], "renamed")
      |> Map.put("_target", ["page", "vars", "0", "key"])

    view |> element("#page_form_form") |> render_change(params)

    assert_receive %Phoenix.Socket.Broadcast{event: "rerender", payload: %{html: html}}, 3_000
    assert html =~ "<footer>farewell:en renamed</footer>"
  end

  # A change another editor makes reaches this editor's form without a
  # `validate`, and its open preview follows it as it follows typing.
  test "a co-editor's change to a field in rerender_on_change refreshes the open preview", c do
    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    {view, _html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}")
    {coeditor, html} = live_form(log_in_user(build_conn(), other), "/admin/pages/update/#{c.page.id}")
    key = open_preview(view, "Localized")
    on_exit(fn -> LivePreview.cleanup_cache(key) end)

    coeditor_form = with_target(coeditor, cid_of(coeditor, "#page_form-el"))
    render_hook(coeditor_form, "focus", %{"field" => "page[language]"})

    params =
      html
      |> form_params("#page_form_form")
      |> put_in(["page", "language"], "no")
      |> Map.put("_target", ["page", "language"])

    coeditor |> element("#page_form_form") |> render_change(params)
    render_hook(coeditor_form, "blur", %{"field" => "page[language]"})

    assert_receive %Phoenix.Socket.Broadcast{event: "rerender", payload: %{html: html}}, 3_000
    assert html =~ "<header>greeting:no</header>"
    assert html =~ "<footer>farewell:no</footer>"
  end

  describe "a schema without block fields" do
    # Brando.MetaDrawerTest.ActionsArticle: no Blocks trait, one preview
    # target whose layout reads the title (test_helper.exs)
    setup %{conn: conn, page: page} do
      {:ok, view, _html} = live(conn, "/admin/meta-articles/update/#{page.id}", on_error: [duplicate_id: :ignore])
      render_async(view, 5_000)
      html = await_selector(view, "#actions_article_form_form input")
      view |> element("#actions_article_form-preview-trigger") |> render_click()
      iframe = await_selector(view, "iframe[src*='__livepreview']")
      [key] = Regex.run(~r/__livepreview\?key=([A-Za-z0-9_-]+)/, iframe, capture: :all_but_first)
      Brando.endpoint().subscribe("live_preview:#{key}")
      on_exit(fn -> LivePreview.cleanup_cache(key) end)
      %{view: view, html: html}
    end

    defp change_field(view, html, target, value) do
      params =
        html
        |> form_params("#actions_article_form_form")
        |> put_in(target, value)
        |> Map.put("_target", target)

      view |> element("#actions_article_form_form") |> render_change(params)
    end

    test "a field in rerender_on_change renders the whole page once", %{view: view, html: html} do
      change_field(view, html, ["actions_article", "title"], "Retitled")

      assert_receive %Phoenix.Socket.Broadcast{event: "rerender", payload: %{html: document}}, 2_000
      assert document =~ "<header>heading:Retitled</header>"
      refute_receive %Phoenix.Socket.Broadcast{}, 200
    end

    test "a target segment no atom exists for updates the preview without raising", %{view: view, html: html} do
      segment = "unknown_#{System.unique_integer([:positive])}"
      change_field(view, html, ["actions_article", segment], "x")

      assert_receive %Phoenix.Socket.Broadcast{event: "update"}, 2_000
      assert render(view) =~ "actions_article_form_form"
    end

    # `[:title]` covers a field below it, not one whose name starts with it
    test "a field whose name begins with a declared one only updates", %{view: view, html: html} do
      change_field(view, html, ["actions_article", "title_#{System.unique_integer([:positive])}"], "x")

      assert_receive %Phoenix.Socket.Broadcast{event: "update"}, 2_000
      refute_receive %Phoenix.Socket.Broadcast{event: "rerender"}, 200
    end

    test "an accepted AI suggestion in a rerender_on_change field renders the whole page", %{view: view} do
      Phoenix.LiveView.send_update(view.pid, BrandoAdmin.Components.Form,
        id: "actions_article_form",
        event: "accept_field_action",
        field_name: "actions_article[meta_description]",
        field: :meta_description,
        text: "Written by AI",
        replace: true
      )

      assert_receive %Phoenix.Socket.Broadcast{event: "rerender"}, 2_000
      refute_receive %Phoenix.Socket.Broadcast{}, 200

      assert view
             |> render()
             |> form_params("#actions_article_form_form")
             |> get_in(["actions_article", "meta_description"]) == "Written by AI"
    end
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
