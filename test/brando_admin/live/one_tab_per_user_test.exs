defmodule BrandoAdmin.OneTabPerUserTest do
  # One editor, two tabs on one entry, through real LiveViews: one tab edits
  # at a time (`BrandoAdmin.LiveView.Form.Tabs`).
  use Brando.LiveCase

  import Brando.EditSessionEditors, only: [await: 1]

  alias Brando.Pages.Page

  setup %{current_user: me, conn: conn} do
    page = Factory.insert(:page, creator: me, title: "Om oss", uri: "om-oss")
    path = "/admin/pages/update/#{page.id}"
    a = open(conn, path, "tab-a")
    %{page: page, path: path, a: a}
  end

  # A browser tab: its id is in sessionStorage and goes with every join,
  # which it counts.
  defp open(conn, path, tab) do
    params = %{"brando_tab" => tab, "brando_tab_seq" => System.unique_integer([:monotonic, :positive])}
    {view, _html} = conn |> Phoenix.LiveViewTest.put_connect_params(params) |> live_form(path)
    view
  end

  defp form_assigns(view) do
    {components, _, _} = :sys.get_state(view.pid).components

    Enum.find_value(components, fn
      {_cid, {BrandoAdmin.Components.Form, _id, assigns, _private, _prints}} -> assigns
      _ -> nil
    end)
  end

  defp mode(view), do: :sys.get_state(view.pid).socket.assigns.tab_access.mode

  defp form(view), do: with_target(view, cid_of(view, "#page_form-el"))

  defp type(view, field, value) do
    params =
      view
      |> render()
      |> form_params("#page_form_form")
      |> put_in(["page", field], value)
      |> Map.put("_target", ["page", field])

    view |> element("#page_form_form") |> render_change(params)
  end

  defp edit(view, field, value) do
    view |> form() |> render_hook("focus", %{"field" => "page[#{field}]"})
    type(view, field, value)
    view |> form() |> render_hook("blur", %{"field" => "page[#{field}]"})
  end

  defp field(view, field), do: Ecto.Changeset.get_field(form_assigns(view).form.source, field)

  defp capture(view) do
    main = view |> render() |> form_params("#page_form_form") |> Plug.Conn.Query.encode()

    view
    |> form()
    |> render_hook("draft_capture", %{"main" => main, "blocks" => %{}, "generation" => 1, "request_id" => "r1"})
  end

  defp claim(view),
    do: view |> element(~s([data-testid="tab-notice"] button[phx-click="brando_tab_claim"])) |> render_click()

  # `to` presses Edit here; `from`'s browser answers the last capture.
  defp take_over(to, from) do
    claim(to)
    assert_push_event(from, "b:draft-release", %{})
    capture(from)
    await_mode(to, :editing)
    settle(to)
  end

  defp notice(view, mode), do: has_element?(view, ~s([data-testid="tab-notice"][data-mode="#{mode}"]))

  defp await_mode(view, mode), do: await(fn -> mode(view) == mode end)

  test "a tab opened alone edits", c do
    assert mode(c.a) == :editing
    refute has_element?(c.a, ~s([data-testid="tab-notice"]))
    refute has_element?(c.a, "#page_form_form[inert]")
  end

  test "the second tab shows the notice, and changes nothing", c do
    b = open(c.conn, c.path, "tab-b")

    assert mode(b) == :waiting
    assert notice(b, "waiting")
    assert has_element?(b, "#page_form_form[inert]")
    assert mode(c.a) == :editing

    # What gets through anyway is ignored
    type(b, "title", "Om oss, B")
    assert field(b, :title) == "Om oss"
    settle(c.a)
    assert field(c.a, :title) == "Om oss"
  end

  test "Edit here hands editing over, with the unsaved fields and the recovery copy", c do
    b = open(c.conn, c.path, "tab-b")
    edit(c.a, "title", "Om oss, A")
    await(fn -> field(b, :title) == "Om oss, A" end)
    capture(c.a)
    a_copy = form_assigns(c.a).draft.id
    assert Enum.any?(Brando.Drafts.list(form_assigns(c.a).draft.identity), &(&1.id == a_copy))

    claim(b)

    # A's last capture comes from its browser, which the test plays
    assert_push_event(c.a, "b:draft-release", %{})
    capture(c.a)

    await_mode(b, :editing)
    await_mode(c.a, :released)
    settle(b)

    assert notice(c.a, "released")
    assert has_element?(c.a, "#page_form_form[inert]")
    refute has_element?(b, ~s([data-testid="tab-notice"]))
    refute has_element?(b, "#page_form_form[inert]")

    # B goes on with A's work and A's copy, which it doesn't offer
    assert field(b, :title) == "Om oss, A"
    assert form_assigns(b).draft.id == a_copy
    refute Enum.any?(form_assigns(b).draft.candidates, &(&1.id == a_copy))
    refute has_element?(b, ~s([data-testid="draft-notice"]))
    refute form_assigns(c.a).draft.id == a_copy

    # B edits and saves; A follows, and doesn't save
    edit(b, "uri", "om-oss-b")
    await(fn -> field(c.a, :uri) == "om-oss-b" end)
    type(c.a, "uri", "om-oss-a")
    assert field(c.a, :uri) == "om-oss-b"
  end

  # A cleared required title doesn't cast, and the field sync leaves it out:
  # it goes over with the copy.
  test "a value typed that didn't cast goes over with the copy", c do
    b = open(c.conn, c.path, "tab-b")
    view = c.a
    view |> form() |> render_hook("focus", %{"field" => "page[title]"})
    type(view, "title", "")
    assert field(b, :title) == "Om oss"

    take_over(b, c.a)

    await(fn -> b |> render() |> form_params("#page_form_form") |> get_in(["page", "title"]) == "" end)
    assert Keyword.has_key?(form_assigns(b).form.source.errors, :title)
  end

  # A revision loaded as a working copy left the edit session: its blocks
  # are in the copy alone, and the tab that takes over restores it whole.
  test "a revision's working copy goes over as a working copy", c do
    entry = Page |> Brando.Repo.get!(c.page.id) |> Brando.Repo.preload(Brando.Blueprint.preloads_for(Page))
    {:ok, revision} = Brando.Revisions.create_revision(entry, c.current_user)
    b = open(c.conn, c.path, "tab-b")

    drawer = cid_of(c.a, "#page_form-revisions-drawer-tab-activity")
    c.a |> with_target(drawer) |> render_hook("select_revision", %{"revision" => revision.revision})
    await(fn -> form_assigns(c.a).working_copy == revision.revision end)

    take_over(b, c.a)

    await(fn -> form_assigns(b).working_copy == revision.revision end)
    assert form_assigns(b).blocks_detached?
  end

  test "Take editing back goes the other way", c do
    b = open(c.conn, c.path, "tab-b")
    claim(b)
    assert_push_event(c.a, "b:draft-release", %{})
    capture(c.a)
    await_mode(b, :editing)
    await_mode(c.a, :released)

    claim(c.a)
    assert_push_event(b, "b:draft-release", %{})
    capture(b)
    await_mode(c.a, :editing)
    await_mode(b, :released)
    settle(c.a)

    refute has_element?(c.a, ~s([data-testid="tab-notice"]))
    assert notice(b, "released")
  end

  test "closing the editing tab leaves the other one waiting", c do
    b = open(c.conn, c.path, "tab-b")
    assert mode(b) == :waiting

    kill_live(c.a)
    await(fn -> b |> render() |> String.contains?("The other tab was closed") end)

    assert mode(b) == :waiting
    assert has_element?(b, "#page_form_form[inert]")

    # Edit here: no tab to hand over
    claim(b)
    await_mode(b, :editing)
  end

  # A reconnect the server hasn't noticed yet: the old process is still
  # there. The new one is the tab, and the old one edits nothing.
  test "a tab that reconnects while its old process is still there keeps editing", c do
    a2 = open(c.conn, c.path, "tab-a")

    assert mode(a2) == :editing
    await_mode(c.a, :released)
  end

  # A new entry's first save patches the form to its update route, and the
  # tab claims then: connect params are gone after mount.
  test "a create form patched to the update route takes part", c do
    {view, _} =
      c.conn
      |> Phoenix.LiveViewTest.put_connect_params(%{"brando_tab" => "tab-new"})
      |> live_form("/admin/pages/create")

    render_patch(view, c.path)
    assert mode(view) == :waiting
    assert mode(c.a) == :editing
  end

  test "a reconnect with offline edits, after another tab took over, makes a recovery copy, not a save", c do
    b = open(c.conn, c.path, "tab-b")
    claim(b)
    assert_push_event(c.a, "b:draft-release", %{})
    capture(c.a)
    await_mode(b, :editing)

    # A goes offline, and comes back as a new process with the same tab id,
    # its form as the browser had it, with the title typed while offline.
    html = render(c.a)
    kill_live(c.a)
    a = open(c.conn, c.path, "tab-a")
    # its old process is gone: it opens as a tab beside the one that edits
    assert mode(a) == :waiting

    params =
      html
      |> recovery_params("#page_form_form")
      |> put_in(["page", "title"], "Typed offline")
      |> Map.put("__offline_edits", "page[title]")

    a |> form() |> render_hook("recover_form", params)
    assert field(a, :title) == "Om oss"

    main = Plug.Conn.Query.encode(Map.delete(params, "_target"))

    a
    |> form()
    |> render_hook("draft_capture", %{"main" => main, "blocks" => %{}, "generation" => 2, "request_id" => "r2"})

    # B offers it; nothing was applied or saved
    await(fn -> Enum.any?(form_assigns(b).draft.candidates, &(&1.payload["main"]["title"] == "Typed offline")) end)
    assert field(b, :title) == "Om oss"
    assert Brando.Repo.get!(Page, c.page.id).title == "Om oss"
  end

  # Picks made with the options still open have not synced: the tab that
  # takes over gets them from the copy the other tab handed over.
  test "the tab that takes over gets the relations that don't sync from the handed-over copy", c do
    alias Brando.Content.ModuleSet

    hero = Factory.insert(:module, name: "Hero", namespace: "general")
    set = Brando.Repo.insert!(%ModuleSet{title: "Set", creator_id: c.current_user.id})
    path = "/admin/config/content/module_sets/update/#{set.id}"

    open_set = fn tab ->
      {view, _} =
        c.conn |> Phoenix.LiveViewTest.put_connect_params(%{"brando_tab" => tab}) |> live_form(path, "module_set_form")

      view
    end

    a = open_set.("set-a")
    b = open_set.("set-b")
    a |> element("#module_set_module_set_modules-field-base button.button-edit") |> render_click()
    a |> element("button.multiselect-option[value='#{hero.id}']") |> render_click()

    b |> element(~s([data-testid="tab-notice"] button[phx-click="brando_tab_claim"])) |> render_click()
    assert_push_event(a, "b:draft-release", %{})
    main = a |> render() |> form_params("#module_set_form_form") |> Plug.Conn.Query.encode()

    a
    |> with_target(cid_of(a, "#module_set_form-el"))
    |> render_hook("draft_capture", %{"main" => main, "blocks" => %{}, "generation" => 1, "request_id" => "r1"})

    await_mode(b, :editing)
    settle(b)

    picked =
      for {_, %{"module_id" => id}} <-
            b |> render() |> form_params("#module_set_form_form") |> get_in(["module_set", "module_set_modules"]) || %{},
          do: String.to_integer(id)

    assert picked == [hero.id]
  end

  # The preview recovers with the form, which a tab that doesn't edit
  # recovers without applying it.
  test "a tab that doesn't edit gets its live preview back after a reconnect", c do
    b = open(c.conn, c.path, "tab-b")
    take_over(b, c.a)
    await_mode(c.a, :released)

    c.a |> element("button[phx-click=toggle_preview_targets]") |> render_click()
    c.a |> element("button.preview-choice", "Blocks") |> render_click()
    html = await_selector(c.a, "iframe[src*='__livepreview']")
    [key] = Regex.run(~r/__livepreview\?key=([A-Za-z0-9_-]+)/, html, capture: :all_but_first)
    on_exit(fn -> Brando.LivePreview.cleanup_cache(key) end)

    kill_live(c.a)
    a = open(c.conn, c.path, "tab-a")
    refute mode(a) == :editing
    [target] = a |> render() |> Floki.parse_document!() |> Floki.attribute("#live-preview-recovery", "phx-target")

    a
    |> with_target(String.to_integer(target))
    |> render_hook("recover_live_preview_state", %{"live_preview" => %{"cache_key" => key}})

    assert form_assigns(a).live_preview_recovery_pending?

    a |> form() |> render_hook("recover_form", recovery_params(html, "#page_form_form"))
    refute form_assigns(a).live_preview_recovery_pending?
  end

  test "an upload finishing in a tab that edits no more stays in the library", c do
    b = open(c.conn, c.path, "tab-b")
    claim(b)
    assert_push_event(c.a, "b:draft-release", %{})
    capture(c.a)
    await_mode(c.a, :released)

    image = Factory.insert(:image)
    @endpoint.subscribe("user:#{c.current_user.id}")

    send(c.a.pid, {:asset_ready, %{"kind" => "entry_field", "field" => "meta_image"}, image})

    assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: message}}, 2_000
    assert message =~ "library"
    settle(c.a)
    refute Ecto.Changeset.get_field(form_assigns(c.a).form.source, :meta_image_id) == image.id
  end
end
