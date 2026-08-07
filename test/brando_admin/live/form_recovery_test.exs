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

    test "kill_live/1 takes the process down and waits for it", %{conn: conn, page: page} do
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
      pid = view.pid

      assert Process.alive?(pid)
      assert kill_live(view) == :ok
      refute Process.alive?(pid)
    end

    # `kill_live/1` has to trap exits to survive the proxy dying with the view.
    # If it left the flag on, every later line in the test process would quietly
    # stop being killed by a crash — including the assertions this file exists
    # to make.
    test "kill_live/1 leaves trap_exit as it found it", %{conn: conn, page: page} do
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")

      refute Process.info(self(), :trap_exit) == {:trap_exit, true}
      kill_live(view)
      assert Process.info(self(), :trap_exit) == {:trap_exit, false}
    end

    # `await_proxy_exit/1` returns `:ok` only on a real exit. A proxy still
    # alive when the window closes is a hang, and hangs are reported.
    test "kill_live/1 flunks when the proxy outlives the view" do
      {view, proxy} = stub_view_with_live_proxy()

      assert_raise ExUnit.AssertionError, ~r/did not exit within 500ms/, fn ->
        kill_live(view)
      end

      # Subject assertion: reaching the proxy wait at all means `kill_live/1`
      # killed the view first. Goes RED if the kill is removed, or moved after
      # the flunk — either of which leaves the `assert_raise` above still
      # passing, so this is the line that catches them.
      #
      # Reordering the two waits does **not** redden it, and the mutation is
      # named here because it is the one a reader would reach for: the kill
      # runs ahead of both waits, so the view is already dead by the time the
      # proxy wait flunks.
      refute Process.alive?(view.pid)

      # Fixture premise, not a subject assertion — kept, and labelled as one.
      # `kill_live/1` never touches the proxy and the stub is an unlinked
      # infinite sleeper, so this line cannot go RED for *any* change to the
      # subject; its RED comes only from mutating the fixture. It stays because
      # the flunk asserted above is a claim *about the proxy*, and a reader is
      # owed the evidence that the claim was true rather than a coincidence.
      # Asserted on the process rather than on this mailbox for a related
      # reason: `kill_live/1` only ever `receive`s, so no `{:EXIT, …}` can
      # arrive here and a refutation about one would hold whatever the code did.
      assert Process.alive?(proxy)

      # `kill_live/1` restores `trap_exit` from an `after`, so the flunk path
      # hands the flag back too. Without that, a caught flunk leaks it into
      # every later line of this test process.
      assert Process.info(self(), :trap_exit) == {:trap_exit, false}
    end

    # Establishes that a child view's death stops the **root's** proxy, which
    # is why `kill_live/1` awaits the proxy for every view and takes no role
    # from the caller. The child is a real one: every admin page renders three
    # sticky children (`layouts/live.html.heex:2-4`), so no fixture is needed.
    #
    # Asserts on **proxy liveness** rather than on elapsed time because the
    # competing reading — a child shares a proxy that outlives it — predicts
    # the same elapsed time and is satisfied by any wall-clock assertion. Only
    # the proxy's own `:DOWN` separates them. A stub proxy cannot see this at
    # all, because a stub *is* the claim wearing a `spawn/1`.
    test "killing a real child view stops the root's proxy", %{conn: conn, page: page} do
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
      {_ref, _topic, proxy_pid} = view.proxy
      child = find_live_child(view, "brando-chrome")

      assert child, "no `brando-chrome` child mounted — the layout no longer renders one"

      # The three premises that make the result causal. Without them the
      # assertion below is satisfied by any death of the root view inside the
      # window — including one that had nothing to do with the child.
      #
      #   * the child is a genuinely distinct process, not the root under
      #     another name;
      #   * the root is alive going in, so its proxy is not already stopping;
      #   * the proxy is alive going in, so there is something left to stop.
      assert child.pid != view.pid
      assert Process.alive?(view.pid)
      assert Process.alive?(proxy_pid)

      # `live/2` links the test process to the proxy, so if the proxy does go
      # down with the child, an untrapped test dies with it.
      prior_trap? = Process.flag(:trap_exit, true)

      try do
        proxy_ref = Process.monitor(proxy_pid)
        child_ref = Process.monitor(child.pid)

        # Killed with a *distinguishable* reason rather than `:kill`. The child
        # does not trap exits, so this terminates it with `:child_died` —
        # and `client_proxy.ex`'s `handle_info({:DOWN, …}, state)` clause stops
        # the proxy by propagating the monitored view's reason verbatim. That
        # verbatim propagation is what makes the reason usable as evidence: a
        # reason only this line can produce identifies *which* death stopped the
        # proxy. `:kill` would not — every other way the root dies inside this
        # window also reports `:killed`, so the assertion below would pass with
        # the child entirely uninvolved.
        Process.exit(child.pid, :child_died)
        assert_receive {:DOWN, ^child_ref, :process, _, :child_died}, 1_000

        # The same window `await_proxy_exit/1` allows.
        outcome =
          receive do
            {:DOWN, ^proxy_ref, :process, ^proxy_pid, reason} -> {:proxy_stopped, reason}
          after
            500 -> :proxy_survived
          end

        # RED, measured both ways: killing the root instead of the child yields
        # `{:proxy_stopped, :killed}`, and the proxy surviving yields
        # `:proxy_survived`. Matching the reason with `_` accepts the first of
        # those, which is why it is pinned.
        assert outcome == {:proxy_stopped, :child_died}

        Process.demonitor(proxy_ref, [:flush])
        Process.demonitor(child_ref, [:flush])
      after
        Process.flag(:trap_exit, prior_trap?)
      end
    end

    # `recovery_target/2` mirrors `pushFormRecovery` in LiveView's own JS
    # (`view.ts:2434-2450`). Nothing in Elixir-land makes that mirror break when
    # the JS changes, so pin the version it was read against: a bump surfaces
    # here as a prompt to re-read the source, instead of as a test that still
    # passes while modelling a client that no longer exists.
    #
    # It carries a second coupling for the same reason: `stub_view_with_live_proxy/0`
    # below duck-types `%Phoenix.LiveViewTest.View{}`, a struct this repo does
    # not own. A bump is the moment to re-check that struct's shape as well as
    # `pushFormRecovery` — the failure message says so, and the stub's own
    # comment points back here.
    test "the recovery target mirrors a known LiveView version" do
      assert to_string(Application.spec(:phoenix_live_view, :vsn)) == "1.2.8",
             """
             phoenix_live_view moved. Two things to re-read before bumping this:

               * `pushFormRecovery` (assets/js/phoenix_live_view/view.ts) —
                 confirm `Brando.LiveCase.recovery_target/2` still mirrors it;
               * `%Phoenix.LiveViewTest.View{}` — confirm
                 `stub_view_with_live_proxy/0` still duck-types it correctly.

             Then update this version and the docstrings that name it.
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

      kill_live(view)

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

      kill_live(view)

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

      kill_live(view)

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

  # Not a real `%Phoenix.LiveViewTest.View{}`: `kill_live/1` reads `.pid` and
  # `.proxy`, and what the harness tests need is a proxy that stays alive and
  # sends the test process nothing — a root proxy that ignored the kill.
  #
  # That makes this a **duck type of a struct this repo does not own**. If
  # LiveView renames `:proxy`, changes its tuple shape, or starts reading a
  # field this map lacks, `kill_live/1` breaks against real views while every
  # test using this stub keeps passing — the failure lands in consumers, not
  # here. The version assertion above ("the recovery target mirrors a known
  # LiveView version") is the tripwire for that too: it covers this coupling
  # for the same reason it covers the `view.ts` mirror, and a bump is the
  # moment to re-check `%View{}`'s shape as well as `pushFormRecovery`.
  defp stub_view_with_live_proxy do
    proxy = spawn(fn -> Process.sleep(:infinity) end)
    view_pid = spawn(fn -> Process.sleep(:infinity) end)
    on_exit(fn -> Process.exit(proxy, :kill) end)

    {%{pid: view_pid, proxy: {make_ref(), "lv:stub", proxy}}, proxy}
  end
end
