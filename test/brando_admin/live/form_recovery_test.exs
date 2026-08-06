defmodule BrandoAdmin.FormRecoveryTest do
  # The first mounted-LiveView tests in this repo. Everything before them drove
  # form components through `update/2` and `handle_event/3` directly, which
  # cannot see the thing the form audit is about: what survives the LiveView
  # process dying, and why.
  #
  # The contract these pin, in the audit's own words: LiveView's default form
  # recovery replays the DOM against a changeset freshly loaded from the
  # database. So a value is recoverable **if and only if** it has a DOM input
  # backing it. Everything Phase 0 fixed was a value that lived only in
  # changeset `changes` or in component assigns, where recovery could not reach.
  use Brando.LiveCase

  alias Brando.Factory

  setup %{current_user: user} do
    page = Factory.insert(:page, creator: user, title: "Stored title")
    {:ok, page: page}
  end

  describe "the harness itself" do
    test "mounts a real entry form with its fields rendered", %{conn: conn, page: page} do
      {_view, html} = live_form(conn, "/admin/pages/update/#{page.id}")

      params = form_params(html, "#page_form_form")

      assert params["page"]["title"] == "Stored title"
      assert params["page"]["uri"] == page.uri
    end

    test "kill_live/2 takes the process down and waits for it", %{conn: conn, page: page} do
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
      pid = view.pid

      assert Process.alive?(pid)
      assert kill_live(view, :root) == :ok
      refute Process.alive?(pid)
    end

    # `kill_live/2` has to trap exits to survive the proxy dying with the view.
    # If it left the flag on, every later line in the test process would quietly
    # stop being killed by a crash — including the assertions this file exists
    # to make.
    test "kill_live/2 leaves trap_exit as it found it", %{conn: conn, page: page} do
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")

      refute Process.info(self(), :trap_exit) == {:trap_exit, true}
      kill_live(view, :root)
      assert Process.info(self(), :trap_exit) == {:trap_exit, false}
    end

    # `await_proxy_exit/1` used to return `:ok` whenever the proxy was still
    # alive after 500ms — which is exactly what a healthy `:child` looks like,
    # so a genuinely hung **root** proxy was reported as a clean kill. Taking
    # the role from the caller is what makes the two distinguishable; these two
    # tests pin both halves of that, since the ambiguity is only removed if
    # each branch actually does its own thing.
    test "kill_live/2 flunks when a root's proxy outlives the view" do
      {view, proxy} = stub_view_with_live_proxy()

      assert_raise ExUnit.AssertionError, ~r/did not exit within 500ms/, fn ->
        kill_live(view, :root)
      end

      refute_received {:EXIT, ^proxy, _}
      restore_trap_exit()
    end

    # The branch the role argument exists for, and the one nothing exercised
    # before: a child shares the root's proxy, so there is no exit in flight.
    # Waiting for one is a guaranteed 500ms of nothing.
    test "kill_live/2 does not wait on a proxy when the view is a child" do
      {view, _proxy} = stub_view_with_live_proxy()

      {elapsed_us, :ok} = :timer.tc(fn -> kill_live(view, :child) end)

      assert elapsed_us < 400_000, "`:child` waited #{div(elapsed_us, 1000)}ms on a live proxy"
    end

    # `recovery_target/2` mirrors `pushFormRecovery` in LiveView's own JS
    # (`view.ts:2434-2450`). Nothing in Elixir-land makes that mirror break when
    # the JS changes, so pin the version it was read against: a bump surfaces
    # here as a prompt to re-read the source, instead of as a test that still
    # passes while modelling a client that no longer exists.
    test "the recovery target mirrors a known LiveView version" do
      assert to_string(Application.spec(:phoenix_live_view, :vsn)) == "1.2.8",
             """
             phoenix_live_view moved. Re-read `pushFormRecovery`
             (assets/js/phoenix_live_view/view.ts) and confirm
             `Brando.LiveCase.recovery_target/2` still mirrors it — then update
             this version and the docstring that names it.
             """
    end
  end

  # `form_params/2` only earns its keep if it serializes the way a browser does.
  # Where it does not, every recovery assertion built on it is replaying params
  # no real reconnect would ever send.
  describe "form_params/2 serializes the way a browser submits" do
    test "a single-select with no selected option submits its first option" do
      html = """
      <form id="f">
        <select name="page[status]">
          <option value="draft">Draft</option>
          <option value="published">Published</option>
        </select>
      </form>
      """

      assert form_params(html, "#f")["page"]["status"] == "draft"
    end

    test "an explicit selected option still wins" do
      html = """
      <form id="f">
        <select name="page[status]">
          <option value="draft">Draft</option>
          <option value="published" selected>Published</option>
        </select>
      </form>
      """

      assert form_params(html, "#f")["page"]["status"] == "published"
    end

    # The one case where "nothing selected" really does mean "submit nothing".
    test "a multi-select with nothing selected submits nothing" do
      html = """
      <form id="f">
        <select name="page[tags][]" multiple>
          <option value="a">A</option>
          <option value="b">B</option>
        </select>
      </form>
      """

      assert form_params(html, "#f") == %{}
    end
  end

  describe "form recovery" do
    # The baseline the rest of the audit is measured against: a crash on its own
    # restores nothing. Recovery is the *client* replaying the DOM afterwards,
    # not the server remembering anything.
    test "an unsaved edit is gone after the process dies", %{conn: conn, page: page} do
      {view, html} = live_form(conn, "/admin/pages/update/#{page.id}")

      type_title(view, html, "Edited title")
      assert render(view) =~ "Edited title"

      kill_live(view, :root)

      {_view, html} = live_form(conn, "/admin/pages/update/#{page.id}")
      assert form_params(html, "#page_form_form")["page"]["title"] == "Stored title"
    end

    # ...and this is what makes it recoverable: the edit is in the DOM, so
    # replaying the DOM through `phx-change` against the fresh changeset brings
    # it back. This models exactly what `getFormsForRecovery()` does on
    # reconnect.
    test "replaying the captured DOM restores the edit", %{conn: conn, page: page} do
      {view, html} = live_form(conn, "/admin/pages/update/#{page.id}")

      type_title(view, html, "Edited title")

      # What the browser holds when the socket drops: the current DOM, nothing else.
      captured =
        render(view)
        |> form_params("#page_form_form")
        |> Map.put("_target", ["page", "title"])

      assert captured["page"]["title"] == "Edited title"

      kill_live(view, :root)

      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
      recovered = view |> element("#page_form_form") |> render_change(captured)

      assert form_params(recovered, "#page_form_form")["page"]["title"] == "Edited title"
    end

    # The one above replays with the `_target` a *keystroke* would carry. This
    # one replays with the `_target` **recovery** actually carries, which is not
    # the same thing and is where the bug lived: `pushFormRecovery` has no
    # originating element, so it names the first non-hidden input in the form —
    # and on the entry form that is the hidden-by-CSS `image_editor_upload` file
    # input (`form.ex:2105`), not an entry field at all.
    test "recovery replays through the target LiveView actually sends", %{conn: conn, page: page} do
      {view, html} = live_form(conn, "/admin/pages/update/#{page.id}")

      type_title(view, html, "Edited title")

      captured = recovery_params(render(view), "#page_form_form")
      # Pin the premise, so this test explains itself if the form's first input
      # ever changes: the target is not under the entry's singular.
      assert captured["_target"] == ["image_editor_upload"]

      kill_live(view, :root)

      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
      recovered = render_change(view |> element("#page_form_form"), captured)

      assert form_params(recovered, "#page_form_form")["page"]["title"] == "Edited title"
    end

    # `validate` used to branch on `_target` with only two clauses and no
    # fallback, so a change event carrying no target at all killed the form
    # LiveView with `case_clause: nil` — taking every unsaved edit with it.
    test "a validate with no _target does not kill the form", %{conn: conn, page: page} do
      {view, html} = live_form(conn, "/admin/pages/update/#{page.id}")

      params = Map.delete(form_params(html, "#page_form_form"), "_target")
      view |> element("#page_form_form") |> render_change(params)

      assert Process.alive?(view.pid)
    end

    # The corollary, stated as a test so it cannot quietly stop being true: a
    # change the user made is only replayable because an input carries it. This
    # asserts the *mechanism* rather than the outcome — if the title input ever
    # stopped rendering its value, the test above would still pass by replaying
    # a stale param, and this one would not.
    test "the edited value is carried by an input, not by server state", %{conn: conn, page: page} do
      {view, html} = live_form(conn, "/admin/pages/update/#{page.id}")

      type_title(view, html, "Edited title")

      title_input =
        render(view)
        |> Floki.parse_document!()
        |> Floki.find(~s(#page_form_form input[name="page[title]"]))

      assert Floki.attribute(title_input, "value") == ["Edited title"]
    end
  end

  describe "recovery-critical DOM" do
    # C2 shipped a drawer-recovery form that is rendered unconditionally,
    # precisely so it exists in both the old and the new DOM when LiveView's
    # recovery diff runs. If it ever became `:if`-gated again the drawer's
    # in-progress edits would be unrecoverable, exactly as C2 described.
    test "the drawer recovery form is always in the DOM", %{conn: conn, page: page} do
      {_view, html} = live_form(conn, "/admin/pages/update/#{page.id}")

      form =
        html
        |> Floki.parse_document!()
        |> Floki.find("#page_form-drawer-recovery")

      assert form != [], "the drawer recovery form must render whether or not a drawer is open"
      assert Floki.attribute(form, "phx-change") == ["noop"]
    end

    # C1/C3 key the block recovery snapshot on the hook element. C4 made that key
    # entry-scoped, which only works if the entry id actually reaches the DOM.
    test "the block field hook element carries its entry id", %{conn: conn, page: page} do
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")

      # The block editor is deferred a further tick past the entry load
      # (`send_update_after(…, :render_blocks, 50)`), so the form being rendered
      # is not yet the blocks being rendered.
      html = await_selector(view, ~s([phx-hook="Brando.BlockField"]))

      entry_ids =
        html
        |> Floki.parse_document!()
        |> Floki.find(~s([phx-hook="Brando.BlockField"]))
        |> Floki.attribute("data-entry-id")

      assert entry_ids != [], "no BlockField hook element rendered"
      assert Enum.all?(entry_ids, &(&1 == to_string(page.id)))
    end
  end

  # A keystroke in the title field: the whole form's current DOM, with the one
  # field changed, targeted at that field. That `_target` is what separates a
  # keystroke from a recovery replay.
  defp type_title(view, html, title) do
    params =
      html
      |> form_params("#page_form_form")
      |> put_in(["page", "title"], title)
      |> Map.put("_target", ["page", "title"])

    view |> element("#page_form_form") |> render_change(params)
  end

  # Not a real `%Phoenix.LiveViewTest.View{}`: `kill_live/2` reads `.pid` and
  # `.proxy`, and what the harness tests need is a proxy that stays alive and
  # sends the test process nothing — a root proxy that ignored the kill.
  defp stub_view_with_live_proxy do
    proxy = spawn(fn -> Process.sleep(:infinity) end)
    view_pid = spawn(fn -> Process.sleep(:infinity) end)
    on_exit(fn -> Process.exit(proxy, :kill) end)

    {%{pid: view_pid, proxy: {make_ref(), "lv:stub", proxy}}, proxy}
  end

  # `kill_live/2` flunks before it restores the flag. That only matters where
  # the flunk is deliberately caught — a real failure ends the test process and
  # the flag with it.
  defp restore_trap_exit, do: Process.flag(:trap_exit, false)
end
