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
end
