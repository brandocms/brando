defmodule BrandoAdmin.PreviewUpdatesTest do
  use Brando.LiveCase

  import Brando.EditSessionEditors, only: [await: 1]

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

  # An image arrives from another editor as its key, `meta_image_id`; the
  # target names the field, `[:meta_image]`, as this editor's own pick does.
  test "a co-editor's image pick fires the trigger declared on the image field", c do
    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    image = Factory.insert(:image, creator: other, focal: %Brando.Images.Focal{x: 50, y: 50}, status: :processed)
    {view, _html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}")
    {coeditor, _html} = live_form(log_in_user(build_conn(), other), "/admin/pages/update/#{c.page.id}")
    key = open_preview(view, "Localized")
    on_exit(fn -> LivePreview.cleanup_cache(key) end)
    refute_receive %Phoenix.Socket.Broadcast{}, 100

    Phoenix.LiveView.send_update(coeditor.pid, BrandoAdmin.Components.Form,
      id: "page_form",
      event: "entry_field_upload_complete",
      asset_type: :image,
      field: :meta_image,
      path: [],
      asset: image
    )

    assert_receive %Phoenix.Socket.Broadcast{event: "rerender"}, 3_000
  end

  # An upload the UploadManager delivers commits the image's key without the
  # image input reporting the relation.
  test "an image uploaded into a field fires the trigger declared on it", c do
    image = Factory.insert(:image, creator: c.current_user, focal: %Brando.Images.Focal{x: 50, y: 50}, status: :processed)
    {view, _html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}")
    key = open_preview(view, "Localized")
    on_exit(fn -> LivePreview.cleanup_cache(key) end)
    refute_receive %Phoenix.Socket.Broadcast{}, 100

    Phoenix.LiveView.send_update(view.pid, BrandoAdmin.Components.Form,
      id: "page_form",
      event: "entry_field_upload_complete",
      asset_type: :image,
      field: :meta_image,
      path: [],
      asset: image
    )

    assert_receive %Phoenix.Socket.Broadcast{event: "rerender"}, 3_000
  end

  # The relations the preview merges over the entry (`updated_entry_assocs`)
  # are this form's picks; a revision or a recovery copy loaded into the form
  # replaces them with its own.
  describe "after this editor uploads an image" do
    setup c do
      first = processed_image(c.current_user)
      c.page |> Ecto.Changeset.change(meta_image_id: first.id) |> Repo.update!()
      {:ok, first: first, second: processed_image(c.current_user)}
    end

    test "a revision loaded as a working copy brings its own image", c do
      entry = Brando.Pages.Page |> Repo.get!(c.page.id) |> Repo.preload(Brando.Blueprint.preloads_for(Brando.Pages.Page))
      {:ok, revision} = Brando.Revisions.create_revision(entry, c.current_user)
      {view, _html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}")

      upload(view, c.second)
      assert form_assigns(view).updated_entry_assocs.meta_image.id == c.second.id

      drawer = cid_of(view, "#page_form-revisions-drawer-tab-activity")
      view |> with_target(drawer) |> render_hook("select_revision", %{"revision" => revision.revision})
      render(view)

      assert preview_image_id(view) == c.first.id
    end

    test "a restored recovery copy brings its own image", c do
      {view, html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}")
      # A capture before the blocks have loaded is skipped
      await(fn -> form_assigns(view).blocks_ready? end)
      main = html |> form_params("#page_form_form") |> put_in(["page", "title"], "Example Hotel draft")
      view |> element("#page_form_form") |> render_change(Map.put(main, "_target", ["page", "title"]))

      view
      |> with_target(cid_of(view, "#page_form-el"))
      |> render_hook("draft_capture", %{
        "main" => view |> render() |> form_params("#page_form_form") |> Plug.Conn.Query.encode(),
        "blocks" => %{},
        "generation" => 1,
        "request_id" => 1
      })

      # The copy is written once the block fields have answered the capture
      identity = Brando.Drafts.identity(Brando.Pages.Page, c.page.id, c.current_user.id)
      await(fn -> Brando.Drafts.list(identity) != [] end)
      [copy] = Brando.Drafts.list(identity)
      # Loaded again: the first tab is gone, or it would edit (one tab per user)
      kill_live(view)
      {view, _html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}")
      upload(view, c.second)

      view |> with_target(cid_of(view, "#page_form-el")) |> render_click("draft_restore", %{"id" => copy.id})

      assert preview_image_id(view) == c.first.id
    end

    defp processed_image(user),
      do: Factory.insert(:image, creator: user, focal: %Brando.Images.Focal{x: 50, y: 50}, status: :processed)

    defp upload(view, image) do
      Phoenix.LiveView.send_update(view.pid, BrandoAdmin.Components.Form,
        id: "page_form",
        event: "entry_field_upload_complete",
        asset_type: :image,
        field: :meta_image,
        path: [],
        asset: image
      )

      render(view)
    end

    # The image the preview shows: the form's relation over the changeset's.
    defp preview_image_id(view) do
      assigns = form_assigns(view)

      case Map.fetch(assigns.updated_entry_assocs, :meta_image) do
        {:ok, image} -> image && image.id
        :error -> assigns.form.source.data.meta_image.id
      end
    end

    defp form_assigns(view) do
      {components, _, _} = :sys.get_state(view.pid).components

      Enum.find_value(components, fn
        {_cid, {BrandoAdmin.Components.Form, "page_form", assigns, _, _}} -> assigns
        _ -> nil
      end)
    end
  end

  # A relation picked in a subform row (a variable's image) is reported with
  # the row's path; `[:vars]` covers it as it covers typing in the row.
  test "a relation picked in a subform row fires the trigger on the subform", c do
    {view, _html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}")
    key = open_preview(view, "Localized")
    on_exit(fn -> LivePreview.cleanup_cache(key) end)
    refute_receive %Phoenix.Socket.Broadcast{}, 100

    Phoenix.LiveView.send_update(view.pid, BrandoAdmin.Components.Form,
      id: "page_form",
      event: "update_entry_relation",
      path: [:vars, 0, :image],
      updated_relation: nil
    )

    assert_receive %Phoenix.Socket.Broadcast{event: "rerender"}, 1_000
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
      %{view: view, html: html, key: key}
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

    test "a target segment no atom exists for updates the preview without raising", %{view: view, html: html, key: key} do
      segment = "unknown_#{System.unique_integer([:positive])}"
      assert_preview_renders(key, fn -> change_field(view, html, ["actions_article", segment], "x") end)
      assert render(view) =~ "actions_article_form_form"
    end

    # `[:title]` covers a field below it, not one whose name starts with it.
    # The page does not show the field, so the update renders the page it
    # already shows and sends nothing; a rerender would go out, since only
    # `<main>` is known to be shown after the preview opens.
    test "a field whose name begins with a declared one only updates", %{view: view, html: html, key: key} do
      field = ["actions_article", "title_#{System.unique_integer([:positive])}"]
      assert_preview_renders(key, fn -> change_field(view, html, field, "x") end)
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

  # Between the two halves of a recovery the form has not got its unsaved
  # input back; the render that ends the recovery has it, and the change.
  test "a co-editor's change during preview recovery waits for the recovered form", c do
    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    {view, html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}")
    key = open_preview(view, "Localized")
    on_exit(fn -> LivePreview.cleanup_cache(key) end)
    captured = html |> recovery_params("#page_form_form") |> put_in(["page", "title"], "Recovered title")
    kill_live(view)
    {view, _html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}")

    [target] = view |> render() |> Floki.parse_document!() |> Floki.attribute("#live-preview-recovery", "phx-target")

    view
    |> with_target(String.to_integer(target))
    |> render_hook("recover_live_preview_state", %{"live_preview" => %{"cache_key" => key}})

    {coeditor, coeditor_html} = live_form(log_in_user(build_conn(), other), "/admin/pages/update/#{c.page.id}")
    coeditor_form = with_target(coeditor, cid_of(coeditor, "#page_form-el"))
    render_hook(coeditor_form, "focus", %{"field" => "page[uri]"})

    params =
      coeditor_html
      |> form_params("#page_form_form")
      |> put_in(["page", "uri"], "renamed-uri")
      |> Map.put("_target", ["page", "uri"])

    coeditor |> element("#page_form_form") |> render_change(params)
    render_hook(coeditor_form, "blur", %{"field" => "page[uri]"})
    settle(view)

    refute_receive %Phoenix.Socket.Broadcast{}, 300

    view |> element("#page_form_form") |> render_change(captured)

    assert_receive %Phoenix.Socket.Broadcast{event: "rerender", payload: %{html: html}}, 3_000
    assert html =~ "Recovered title"
  end

  # An added row changes the entry without a round trip through the browser,
  # so the form refreshes the open preview itself.
  test "adding a page variable updates the open preview", %{conn: conn, page: page} do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    key = open_preview(view)
    on_exit(fn -> LivePreview.cleanup_cache(key) end)
    refute_receive %Phoenix.Socket.Broadcast{event: "update"}, 100

    assert_preview_renders(key, fn ->
      view |> element("#page_vars-add-entry") |> render_click()
      settle(view)
    end)
  end

  # The cache holds no block patches, so when a preview page reports it is
  # missing some (`LivePreviewChannel`) the form renders the whole page and
  # says so in the drawer. A closed preview no longer listens.
  test "a page missing block patches gets the whole page again, with a notice", %{conn: conn, page: page} do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    key = open_preview(view)
    on_exit(fn -> LivePreview.cleanup_cache(key) end)
    assert render(view) =~ "The preview was missing some changes"
    listeners = fn -> Registry.lookup(Brando.pubsub(), LivePreview.form_topic(key)) |> Enum.map(&elem(&1, 0)) end
    assert listeners.() == [view.pid]

    LivePreview.report_lost_patches(key)
    assert_receive %Phoenix.Socket.Broadcast{event: "rerender", payload: %{html: html}}, 3_000
    assert html =~ "<head"
    assert_push_event(view, "b:live_preview_notice", %{})

    view |> element(".live-preview-close") |> render_click()
    assert listeners.() == []
    LivePreview.report_lost_patches(key)
    settle(view)
    refute_receive %Phoenix.Socket.Broadcast{event: "rerender"}, 150
  end
end
