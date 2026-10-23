defmodule BrandoAdmin.EntrySavedElsewhereTest do
  # Two editors in one entry; A saves. B's form takes what A saved in every
  # field B has not edited: a has_many list, which doesn't ship as a field
  # change, and a value the save set itself (`publish_at`). The fields B
  # edited keep B's values and stay B's edits. Before, B kept the values it
  # opened with, and B's save (or recovery copy) reverted A's.
  use Brando.LiveCase

  import Brando.EditSessionEditors, only: [await: 1]

  alias Brando.Content.ModuleSet
  alias Brando.Content.ModuleSetModule
  alias Brando.Pages.Page
  alias Brando.SyncTest.Article

  setup %{conn: conn, current_user: me} do
    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    %{other_conn: log_in_user(Phoenix.ConnTest.build_conn(), other), a_conn: conn, me: me}
  end

  # The Form component, which takes the focus and blur of its fields.
  defp form_of(view, singular), do: with_target(view, cid_of(view, "##{singular}_form-el"))

  defp focus(view, singular, field),
    do: view |> form_of(singular) |> render_hook("focus", %{"field" => "#{singular}[#{field}]"})

  defp blur(view, singular, field),
    do: view |> form_of(singular) |> render_hook("blur", %{"field" => "#{singular}[#{field}]"})

  # A keystroke as the browser sends it: the whole form as the view shows it,
  # with one field changed and named. `field` is a path into a subform or an
  # embed as a list (`["items", "0", "label"]`).
  defp type(view, singular, field, value), do: type_in(view, singular, render(view), field, value)

  # The same, in the form as the browser showed it in `html`.
  defp type_in(view, singular, html, field, value) do
    path = [singular | List.wrap(field)]

    params =
      html
      |> form_params("##{singular}_form_form")
      |> put_in(path, value)
      |> Map.put("_target", path)

    view |> element("##{singular}_form_form") |> render_change(params)
  end

  defp params(view, singular), do: view |> render() |> form_params("##{singular}_form_form") |> Map.fetch!(singular)

  # The notice for a relation both tabs changed (`Form.SavedElsewhere`).
  defp conflict?(view, field), do: has_element?(view, ~s([data-testid="saved-elsewhere"][data-field="#{field}"]))

  defp settle_conflict(view, field, button),
    do: view |> element(~s([data-testid="saved-elsewhere"][data-field="#{field}"] button), button) |> render_click()

  # "Save and continue editing". A save of a form with block fields is two
  # submits: the first collects the blocks, the second writes.
  defp save_and_stay(view, singular, blocks?) do
    view |> form_of(singular) |> render_hook("save_redirect_target", %{})
    view |> element("##{singular}_form_form") |> render_submit()

    if blocks? do
      assert_push_event(view, "b:submit", %{}, 5_000)
      view |> element("##{singular}_form_form") |> render_submit()
    end
  end

  # The Form component's assigns.
  defp form_assigns(view) do
    {components, _, _} = :sys.get_state(view.pid).components

    Enum.find_value(components, fn
      {_cid, {BrandoAdmin.Components.Form, _id, assigns, _private, _prints}} -> assigns
      _ -> nil
    end)
  end

  # Another tab of the entry saved it.
  defp announce_save(schema, id) do
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      Brando.Tenant.Topic.entry("field_sync", schema, id),
      {:entry_saved, %{tab: "another-tab", user_id: 0}}
    )
  end

  describe "a has_many list" do
    setup %{current_user: me, a_conn: a_conn, other_conn: other_conn} = c do
      [hero, text] = for name <- ["Hero", "Text"], do: Factory.insert(:module, name: name, namespace: "general")

      held =
        for {module, n} <- Enum.with_index(c[:held] || []),
            do: %ModuleSetModule{module_id: %{hero: hero, text: text}[module].id, sequence: n}

      set = Repo.insert!(%ModuleSet{title: "Set", creator_id: me.id, module_set_modules: held})
      path = "/admin/config/content/module_sets/update/#{set.id}"

      {a, _} = live_form(a_conn, path, "module_set_form")
      {b, _} = live_form(other_conn, path, "module_set_form")

      %{set: set, hero: hero, text: text, path: path, a: a, b: b}
    end

    defp toggle_options(view),
      do: view |> element("#module_set_module_set_modules-field-base button.button-edit") |> render_click()

    defp click_option(view, module),
      do: view |> element("button.multiselect-option[value='#{module.id}']") |> render_click()

    # Opens the options, picks one (or takes it out) and closes them, as an
    # editor does. Closing sends the picks to the other editors.
    defp pick(view, module) do
      toggle_options(view)
      click_option(view, module)
      toggle_options(view)
    end

    # The modules the form holds; none is an empty marker, `""`.
    defp chosen(view) do
      case params(view, "module_set")["module_set_modules"] do
        %{} = rows ->
          for {_, %{"module_id" => id} = row} <- rows, row["marked_as_deleted"] != "true", do: String.to_integer(id)

        _ ->
          []
      end
    end

    defp saved_modules(set) do
      ModuleSet
      |> Repo.get!(set.id)
      |> Repo.preload(:module_set_modules)
      |> Map.fetch!(:module_set_modules)
      |> Enum.map(& &1.module_id)
      |> Enum.sort()
    end

    defp capture(view) do
      main = view |> render() |> form_params("#module_set_form_form") |> Plug.Conn.Query.encode()

      view
      |> with_target(cid_of(view, "#module_set_form-el"))
      |> render_hook("draft_capture", %{"main" => main, "blocks" => %{}, "generation" => 1, "request_id" => 1})
    end

    # A required field B cleared is no change, only an error: it stays
    # cleared, whether B is still in the field or has left it.
    for left? <- [false, true] do
      test "a title B cleared stays cleared over A's save (left the field: #{left?})", c do
        focus(c.b, "module_set", "title")
        type(c.b, "module_set", "title", "")
        if unquote(left?), do: blur(c.b, "module_set", "title")

        pick(c.a, c.hero)
        save_and_stay(c.a, "module_set", false)
        await(fn -> saved_modules(c.set) == [c.hero.id] end)
        await(fn -> chosen(c.b) == [c.hero.id] end)

        assert params(c.b, "module_set")["title"] == ""
        assert has_element?(c.b, "#module_set_form_form .field-error")
      end
    end

    test "B's form takes the rows A saved, and B's next save keeps them", c do
      # B is typing in the title when A saves: an edit A doesn't have.
      focus(c.b, "module_set", "title")
      type(c.b, "module_set", "title", "Set, typed by B")

      pick(c.a, c.hero)
      pick(c.a, c.text)
      save_and_stay(c.a, "module_set", false)
      await(fn -> saved_modules(c.set) == Enum.sort([c.hero.id, c.text.id]) end)

      await(fn -> Enum.sort(chosen(c.b)) == Enum.sort([c.hero.id, c.text.id]) end)
      assert params(c.b, "module_set")["title"] == "Set, typed by B"

      # The title is still B's edit: leaving the field ships it.
      blur(c.b, "module_set", "title")
      await(fn -> params(c.a, "module_set")["title"] == "Set, typed by B" end)

      save_and_stay(c.b, "module_set", false)

      await(fn ->
        saved = Repo.get!(ModuleSet, c.set.id)
        saved.title == "Set, typed by B" and saved_modules(c.set) == Enum.sort([c.hero.id, c.text.id])
      end)
    end

    # The picks A sends as A makes them (`multi_select_changed`) leave out
    # the rows A took out, and B holds them as A's, not as B's own edit.
    @tag held: [:text]
    test "a row A took out stays out of B's form, B's save and B's recovery copy", c do
      pick(c.a, c.text)
      pick(c.a, c.hero)
      await(fn -> chosen(c.b) == [c.hero.id] end)

      save_and_stay(c.a, "module_set", false)
      await(fn -> saved_modules(c.set) == [c.hero.id] end)
      settle(c.b)
      assert chosen(c.b) == [c.hero.id]

      capture(c.b)

      for copy <- Brando.Drafts.list(Brando.Drafts.identity(ModuleSet, c.set.id, form_assigns(c.b).current_user.id)) do
        refute c.text.id in Enum.map(copy.payload["main"]["module_set_modules"] || [], & &1["module_id"])
      end

      save_and_stay(c.b, "module_set", false)
      settle(c.b)
      assert saved_modules(c.set) == [c.hero.id]
    end

    test "a list B only had from A takes what A saved", c do
      pick(c.a, c.hero)
      await(fn -> chosen(c.b) == [c.hero.id] end)

      # A changes the picks again, and saves with the options still open:
      # the change reaches B only with the save.
      toggle_options(c.a)
      click_option(c.a, c.hero)
      click_option(c.a, c.text)
      save_and_stay(c.a, "module_set", false)
      await(fn -> saved_modules(c.set) == [c.text.id] end)

      await(fn -> chosen(c.b) == [c.text.id] end)
    end

    # Picks reach another editor's open options as they are made
    # (`multi_select_changed`), but not another tab of the same editor. Both
    # tabs changed the list: B keeps its own and is asked which to keep.
    defp picked_in_two_tabs(c) do
      {b, _} = live_form(c.a_conn, c.path, "module_set_form")

      Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.entry("field_sync", ModuleSet, c.set.id))
      pick(c.a, c.hero)
      pick(b, c.text)
      save_and_stay(c.a, "module_set", false)
      assert_receive {:entry_saved, _}, 5_000
      assert saved_modules(c.set) == [c.hero.id]
      # B's process has the message too: the renders queue behind it.
      settle(b)
      b
    end

    test "a pick of B's own stays over A's save, and B keeps it", c do
      b = picked_in_two_tabs(c)

      assert chosen(b) == [c.text.id]
      assert conflict?(b, "module_set_modules")

      settle_conflict(b, "module_set_modules", "Keep my version")
      refute conflict?(b, "module_set_modules")
      assert chosen(b) == [c.text.id]

      save_and_stay(b, "module_set", false)
      await(fn -> saved_modules(c.set) == [c.text.id] end)
    end

    # B's recovery copy holds the pick the form still shows: it is not one
    # to offer B after A's save.
    test "B isn't offered its own recovery copy after A's save", c do
      {b, _} = live_form(c.a_conn, c.path, "module_set_form")
      pick(b, c.text)
      capture(b)
      own = form_assigns(b).draft.id
      assert Enum.any?(Brando.Drafts.list(form_assigns(b).draft.identity), &(&1.id == own))

      pick(c.a, c.hero)
      save_and_stay(c.a, "module_set", false)
      await(fn -> saved_modules(c.set) == [c.hero.id] end)
      await(fn -> conflict?(b, "module_set_modules") end)

      refute Enum.any?(form_assigns(b).draft.candidates, &(&1.id == own))
      refute has_element?(b, ~s([data-testid="draft-notice"]))
    end

    test "B takes the rows A saved over its own pick", c do
      b = picked_in_two_tabs(c)

      settle_conflict(b, "module_set_modules", "Use the saved version")
      refute conflict?(b, "module_set_modules")
      assert chosen(b) == [c.hero.id]

      # The browser sends the rows it showed before: they stay the saved ones.
      type(b, "module_set", "title", "Set, typed by B")
      assert chosen(b) == [c.hero.id]

      save_and_stay(b, "module_set", false)
      await(fn -> Repo.get!(ModuleSet, c.set.id).title == "Set, typed by B" end)
      assert saved_modules(c.set) == [c.hero.id]
    end

    # The modules B's form holds, in the order it shows them.
    defp chosen_in_order(view) do
      rows = params(view, "module_set")["module_set_modules"] || %{}
      order = params(view, "module_set")["sort_module_set_module_ids"] || Map.keys(rows)

      for index <- order,
          %{"module_id" => id} = row <- [rows[index]],
          row["marked_as_deleted"] != "true",
          do: String.to_integer(id)
    end

    defp saved_modules_in_order(set) do
      ModuleSet
      |> Repo.get!(set.id)
      |> Repo.preload(:module_set_modules)
      |> Map.fetch!(:module_set_modules)
      |> Enum.map(& &1.module_id)
    end

    # A's pick reaches B as A makes it, and B's reaches A: each holds both
    # as rows it hasn't saved, and A saves them. B's are the rows A saved.
    test "picks A and B shipped to each other are the rows A saved, once", c do
      pick(c.a, c.hero)
      await(fn -> chosen(c.b) == [c.hero.id] end)
      pick(c.b, c.text)
      await(fn -> Enum.sort(chosen(c.a)) == Enum.sort([c.hero.id, c.text.id]) end)

      save_and_stay(c.a, "module_set", false)
      await(fn -> saved_modules(c.set) == Enum.sort([c.hero.id, c.text.id]) end)
      settle(c.b)

      assert Enum.sort(chosen(c.b)) == Enum.sort([c.hero.id, c.text.id])

      save_and_stay(c.b, "module_set", false)
      settle(c.b)
      assert saved_modules(c.set) == Enum.sort([c.hero.id, c.text.id])
    end

    # Another tab of the same editor gets no picks as they are made: both
    # tabs picked Hero, and A saved it.
    test "an option picked in two tabs is one row after A's save", c do
      {b, _} = live_form(c.a_conn, c.path, "module_set_form")

      Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.entry("field_sync", ModuleSet, c.set.id))
      pick(c.a, c.hero)
      pick(b, c.hero)
      pick(b, c.text)
      save_and_stay(c.a, "module_set", false)
      assert_receive {:entry_saved, _}, 5_000
      assert saved_modules(c.set) == [c.hero.id]
      settle(b)

      assert chosen_in_order(b) == [c.hero.id, c.text.id]

      save_and_stay(b, "module_set", false)
      settle(b)
      assert saved_modules_in_order(c.set) == [c.hero.id, c.text.id]
    end

    # B drags Text above Hero; A's save is of the title.
    @tag held: [:hero, :text]
    test "B's new order stays over A's save, and B's save writes it", c do
      type(c.b, "module_set", "sort_module_set_module_ids", ["1", "0"])
      assert chosen_in_order(c.b) == [c.text.id, c.hero.id]

      type(c.a, "module_set", "title", "Set, typed by A")
      save_and_stay(c.a, "module_set", false)
      await(fn -> Repo.get!(ModuleSet, c.set.id).title == "Set, typed by A" end)
      await(fn -> params(c.b, "module_set")["title"] == "Set, typed by A" end)

      assert chosen_in_order(c.b) == [c.text.id, c.hero.id]
      # A didn't change the list: nothing to ask
      refute conflict?(c.b, "module_set_modules")

      save_and_stay(c.b, "module_set", false)

      await(fn ->
        Repo.get!(ModuleSet, c.set.id).title == "Set, typed by A" and
          saved_modules_in_order(c.set) == [c.text.id, c.hero.id]
      end)
    end

    # B's browser sends a keystroke in the form it showed before the save
    # reached it: the rows in it are the ones the save replaced.
    test "B's browser sending the rows it showed before A's save doesn't undo the save", c do
      {b, _} = live_form(c.a_conn, c.path, "module_set_form")
      before = render(b)

      pick(c.a, c.hero)
      save_and_stay(c.a, "module_set", false)
      await(fn -> saved_modules(c.set) == [c.hero.id] end)
      await(fn -> chosen(b) == [c.hero.id] end)

      type_in(b, "module_set", before, "title", "Set, typed by B")
      assert chosen(b) == [c.hero.id]
      assert params(b, "module_set")["title"] == "Set, typed by B"

      save_and_stay(b, "module_set", false)

      await(fn ->
        Repo.get!(ModuleSet, c.set.id).title == "Set, typed by B" and saved_modules(c.set) == [c.hero.id]
      end)
    end

    # The other tab's recovery copy is of the form it shows, compared with
    # the entry as saved: it has A's rows, and B's title as B's change.
    test "a recovery copy B captures after A's save has the saved rows", c do
      {b, _} = live_form(c.a_conn, c.path, "module_set_form")
      focus(b, "module_set", "title")
      type(b, "module_set", "title", "Set, typed in B")

      pick(c.a, c.hero)
      pick(c.a, c.text)
      save_and_stay(c.a, "module_set", false)
      await(fn -> Enum.sort(chosen(b)) == Enum.sort([c.hero.id, c.text.id]) end)

      capture(b)

      [copy] = Brando.Drafts.list(Brando.Drafts.identity(ModuleSet, c.set.id, c.me.id))
      assert copy.payload["main"]["title"] == "Set, typed in B"

      assert copy.payload["main"]["module_set_modules"] |> Enum.map(& &1["module_id"]) |> Enum.sort() ==
               Enum.sort([c.hero.id, c.text.id])
    end

    # B's browser captures the form it showed before A's save reached it:
    # the rows in it are the ones A's save replaced.
    test "a recovery copy of the form B showed before A's save keeps A's rows", c do
      focus(c.b, "module_set", "title")
      type(c.b, "module_set", "title", "Set, typed by B")
      before = render(c.b)

      pick(c.a, c.hero)
      pick(c.a, c.text)
      save_and_stay(c.a, "module_set", false)
      await(fn -> Enum.sort(chosen(c.b)) == Enum.sort([c.hero.id, c.text.id]) end)

      main = before |> form_params("#module_set_form_form") |> Plug.Conn.Query.encode()

      c.b
      |> with_target(cid_of(c.b, "#module_set_form-el"))
      |> render_hook("draft_capture", %{"main" => main, "blocks" => %{}, "generation" => 1, "request_id" => 1})

      [copy] = Brando.Drafts.list(form_assigns(c.b).draft.identity)
      assert copy.payload["main"]["title"] == "Set, typed by B"

      assert copy.payload["main"]["module_set_modules"] |> Enum.map(& &1["module_id"]) |> Enum.sort() ==
               Enum.sort([c.hero.id, c.text.id])
    end

    # B reconnects (`recover_form`): its browser sends the form it had, with
    # the fingerprint of the entry that form was built on. B is another tab
    # of A's editor, which A's picks don't reach as they are made.
    defp reconnect(c, html) do
      recovered = html |> form_params("#module_set_form_form") |> Map.put("_target", ["image_editor_upload"])
      {b, _} = live_form(c.a_conn, c.path, "module_set_form")
      b |> form_of("module_set") |> render_hook("recover_form", recovered)
      b
    end

    test "B's picks, recovered after A saved others while B was away, are B's to settle", c do
      {b, _} = live_form(c.a_conn, c.path, "module_set_form")
      pick(b, c.text)
      html = render(b)
      kill_live(b)

      pick(c.a, c.hero)
      save_and_stay(c.a, "module_set", false)
      await(fn -> saved_modules(c.set) == [c.hero.id] end)

      b = reconnect(c, html)
      assert chosen(b) == [c.text.id]
      assert conflict?(b, "module_set_modules")

      settle_conflict(b, "module_set_modules", "Use the saved version")
      assert chosen(b) == [c.hero.id]
    end

    test "B's picks, recovered when nobody saved meanwhile, are B's edit", c do
      {b, _} = live_form(c.a_conn, c.path, "module_set_form")
      pick(b, c.text)
      html = render(b)
      kill_live(b)

      b = reconnect(c, html)
      assert chosen(b) == [c.text.id]
      refute conflict?(b, "module_set_modules")

      type(c.a, "module_set", "title", "Set, typed by A")
      save_and_stay(c.a, "module_set", false)
      await(fn -> params(b, "module_set")["title"] == "Set, typed by A" end)
      assert chosen(b) == [c.text.id]
    end

    defp reconnect_after_kill(c, b) do
      html = render(b)
      kill_live(b)
      reconnect(c, html)
    end

    # A's save changed the entry, but not its modules: B's recovered picks
    # are B's edit, as if nobody had saved.
    test "B's picks, recovered after A saved another field while B was away, are B's edit", c do
      {b, _} = live_form(c.a_conn, c.path, "module_set_form")
      pick(b, c.text)
      html = render(b)
      kill_live(b)

      type(c.a, "module_set", "title", "Set, typed by A")
      save_and_stay(c.a, "module_set", false)
      await(fn -> Repo.get!(ModuleSet, c.set.id).title == "Set, typed by A" end)

      b = reconnect(c, html)
      assert chosen(b) == [c.text.id]
      refute conflict?(b, "module_set_modules")
    end

    # B hasn't answered which to keep when its tab reconnects: it is still
    # asked, however often it reconnects, and the saved rows stay on offer.
    test "a conflict B hasn't settled is asked again after B reconnects", c do
      b = picked_in_two_tabs(c)
      assert conflict?(b, "module_set_modules")

      b = reconnect_after_kill(c, b)
      assert chosen(b) == [c.text.id]
      assert conflict?(b, "module_set_modules")

      b = reconnect_after_kill(c, b)
      assert conflict?(b, "module_set_modules")

      settle_conflict(b, "module_set_modules", "Use the saved version")
      assert chosen(b) == [c.hero.id]
    end

    test "a conflict B settled is not asked again after B reconnects", c do
      b = picked_in_two_tabs(c)
      settle_conflict(b, "module_set_modules", "Keep my version")

      b = reconnect_after_kill(c, b)
      assert chosen(b) == [c.text.id]
      refute conflict?(b, "module_set_modules")
    end

    # B's form is rebuilt on the entry as it reads it again (`:update_entry`,
    # as a revision restore or a child component sends it), with a module
    # added meanwhile: B's pick after that is B's edit.
    test "B's picks on an entry the form read again are B's edit after a reconnect", c do
      {b, _} = live_form(c.a_conn, c.path, "module_set_form")
      Repo.insert!(%ModuleSetModule{module_set_id: c.set.id, module_id: c.hero.id, sequence: 0})
      entry = Repo.preload(form_assigns(b).entry, [:module_set_modules], force: true)

      Phoenix.LiveView.send_update(b.pid, BrandoAdmin.Components.Form,
        id: form_assigns(b).id,
        action: :update_entry,
        updated_entry: entry
      )

      await(fn -> chosen(b) == [c.hero.id] end)

      pick(b, c.text)
      html = render(b)
      kill_live(b)

      b = reconnect(c, html)
      assert Enum.sort(chosen(b)) == Enum.sort([c.hero.id, c.text.id])
      refute conflict?(b, "module_set_modules")
    end

    # The entry went (removed for good, or out of what B may read) between
    # the save and B reading it back.
    test "a save B can't read back leaves B's form as it is", c do
      type(c.b, "module_set", "title", "Set, typed by B")
      Repo.delete!(c.set)

      announce_save(ModuleSet, c.set.id)
      settle(c.b)

      assert Process.alive?(c.b.pid)
      assert params(c.b, "module_set")["title"] == "Set, typed by B"
    end
  end

  describe "a value the save set" do
    defp shown_publish_at(view) do
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.attribute("#page_publish_at-datetimepicker", "data-value")
      |> List.first()
    end

    setup %{current_user: me, a_conn: a_conn, other_conn: other_conn} do
      page = Factory.insert(:page, creator: me, title: "Om oss", uri: "om-oss", status: :draft, publish_at: nil)
      path = "/admin/pages/update/#{page.id}"
      {a, _} = live_form(a_conn, path)
      {b, _} = live_form(other_conn, path)
      %{page: page, a: a, b: b}
    end

    test "B's form takes the publish_at A's publishing save set, and keeps B's own edit", c do
      focus(c.b, "page", "uri")
      type(c.b, "page", "uri", "om-oss-b")

      type(c.a, "page", "status", "published")
      save_and_stay(c.a, "page", true)
      await(fn -> Repo.get!(Page, c.page.id).publish_at != nil end)
      publish_at = Repo.get!(Page, c.page.id).publish_at

      # The picker's input is the hook's (`phx-update="ignore"`); it takes the
      # value the wrapper carries.
      await(fn -> shown_publish_at(c.b) not in [nil, ""] end)
      assert {:ok, ^publish_at, _} = DateTime.from_iso8601(shown_publish_at(c.b))
      assert params(c.b, "page")["uri"] == "om-oss-b"

      blur(c.b, "page", "uri")
      save_and_stay(c.b, "page", true)

      await(fn ->
        saved = Repo.get!(Page, c.page.id)
        saved.uri == "om-oss-b" and saved.publish_at == publish_at and saved.status == :published
      end)
    end

    test "B's browser sending the form it showed before A's save keeps the publish_at", c do
      before = render(c.b)

      type(c.a, "page", "status", "published")
      save_and_stay(c.a, "page", true)
      await(fn -> Repo.get!(Page, c.page.id).publish_at != nil end)
      publish_at = Repo.get!(Page, c.page.id).publish_at
      await(fn -> shown_publish_at(c.b) not in [nil, ""] end)

      focus(c.b, "page", "uri")
      type_in(c.b, "page", before, "uri", "om-oss-b")
      assert {:ok, ^publish_at, _} = DateTime.from_iso8601(shown_publish_at(c.b))

      blur(c.b, "page", "uri")
      save_and_stay(c.b, "page", true)

      await(fn ->
        saved = Repo.get!(Page, c.page.id)
        saved.uri == "om-oss-b" and saved.publish_at == publish_at and saved.status == :published
      end)
    end

    # While B's own save collects its blocks, B's save is what B's form
    # becomes; A's doesn't rebuild it in between.
    test "B's form isn't rebuilt while B's own save runs", c do
      type(c.b, "page", "uri", "om-oss-b")
      c.b |> form_of("page") |> render_hook("save_redirect_target", %{})
      c.b |> element("#page_form_form") |> render_submit()
      assert form_assigns(c.b).processing

      held = form_assigns(c.b).form

      type(c.a, "page", "title", "Om oss, A")
      save_and_stay(c.a, "page", true)
      await(fn -> Repo.get!(Page, c.page.id).title == "Om oss, A" end)
      settle(c.b)

      # Values other editors ship still reach it (`apply_remote/2`); the
      # entry under it stays the one B's save started from.
      assert form_assigns(c.b).form.data == held.data
    end

    # The browser submits again once the blocks are collected, until the
    # save has run.
    defp submit_collected(view) do
      assert_push_event(view, "b:submit", %{}, 5_000)
      view |> element("#page_form_form") |> render_submit()
      if form_assigns(view).processing, do: submit_collected(view)
    end

    # A's save arrives while B's own save collects its blocks, and B's save
    # then fails (the title is blank): B's form takes A's save in after all,
    # and keeps B's edit.
    test "B's form takes A's save once B's own save fails", c do
      type(c.b, "page", "uri", "om-oss-b")
      type(c.b, "page", "title", "")
      c.b |> form_of("page") |> render_hook("save_redirect_target", %{})
      c.b |> element("#page_form_form") |> render_submit()
      assert form_assigns(c.b).processing

      type(c.a, "page", "status", "published")
      save_and_stay(c.a, "page", true)
      await(fn -> Repo.get!(Page, c.page.id).publish_at != nil end)
      settle(c.b)

      submit_collected(c.b)
      refute form_assigns(c.b).processing
      assert Repo.get!(Page, c.page.id).title == "Om oss"

      assert shown_publish_at(c.b) not in [nil, ""]
      assert params(c.b, "page")["uri"] == "om-oss-b"
    end

    # A revision loaded as a working copy is the form B saves; the saved
    # entry is not.
    test "B's working copy of a revision stays over A's save", c do
      {:ok, revision} =
        Page
        |> Repo.get!(c.page.id)
        |> Ecto.Changeset.change(title: "Revision title")
        |> Repo.update!()
        |> Repo.preload(Brando.Blueprint.preloads_for(Page))
        |> Brando.Revisions.create_revision(c.me)

      c.page |> Ecto.Changeset.change(title: "Om oss") |> Repo.update!()

      drawer = cid_of(c.b, "#page_form-revisions-drawer-tab-activity")
      c.b |> with_target(drawer) |> render_hook("select_revision", %{"revision" => revision.revision})
      await(fn -> params(c.b, "page")["title"] == "Revision title" end)

      type(c.a, "page", "uri", "om-oss-a")
      save_and_stay(c.a, "page", true)
      await(fn -> Repo.get!(Page, c.page.id).uri == "om-oss-a" end)
      settle(c.b)

      assert form_assigns(c.b).working_copy
      assert params(c.b, "page")["title"] == "Revision title"
    end
  end

  describe "an entry whose blocks are still loading" do
    setup %{current_user: me, a_conn: a_conn, other_conn: other_conn} do
      {:ok, module} =
        Brando.Content.create_module(
          Factory.params_for(:module,
            name: %{"en" => "Paragraph"},
            namespace: %{"en" => "Content"},
            help_text: %{"en" => "Help"},
            code: "<p>Paragraph</p>"
          ),
          me
        )

      page = Factory.insert(:page, creator: me, title: "Om oss", uri: "om-oss")

      for _ <- 1..(BrandoAdmin.Components.Form.light_block_limit() + 1),
          do: Brando.Test.insert_block(page, module, user: me)

      path = "/admin/pages/update/#{page.id}"
      {a, _} = live_form(a_conn, path)

      test = self()

      Application.put_env(:brando, :form_load_gate, fn key ->
        send(test, {:load_held, key, self()})

        receive do
          :release -> :ok
        after
          5_000 -> :ok
        end
      end)

      on_exit(fn -> Application.delete_env(:brando, :form_load_gate) end)

      {:ok, b, _html} = live(other_conn, path)
      assert_receive {:load_held, :blocks_load, task}

      %{page: page, a: a, b: b, task: task}
    end

    test "takes A's save in its fields, and its blocks still load", c do
      type(c.a, "page", "title", "Om oss, A")
      save_and_stay(c.a, "page", true)
      await(fn -> Repo.get!(Page, c.page.id).title == "Om oss, A" end)
      await(fn -> params(c.b, "page")["title"] == "Om oss, A" end)

      send(c.task, :release)
      render_async(c.b, 5_000)
      await_selector(c.b, ~s([phx-hook="Brando.BlockField"]))

      count = BrandoAdmin.Components.Form.light_block_limit() + 1
      assert c.b |> render() |> Floki.parse_document!() |> Floki.find("[data-block-uid]") |> length() >= count
      assert params(c.b, "page")["title"] == "Om oss, A"
    end
  end

  describe "an entry's blocks" do
    setup %{a_conn: a_conn, other_conn: other_conn} do
      c = Brando.ProposalFixtures.context()
      uids = c.identity |> Brando.EditSessionEditors.rows() |> Enum.map(& &1.block.uid)
      path = "/admin/pages/update/#{c.identity.id}"
      {a, _} = live_form(a_conn, path)
      {b, _} = live_form(other_conn, path)
      for view <- [a, b], do: await_selector(view, "[data-block-uid]")
      %{page: c.identity, uids: uids, a: a, b: b}
    end

    # What recovery compares a copy with: the entry as saved, its blocks too.
    defp saved_baseline(view, page) do
      %{form_blueprint: blueprint, current_user: user} = form_assigns(view)

      entry =
        Page
        |> Repo.get!(page.id)
        |> Repo.preload(Brando.Blueprint.preloads_for(Page), force: true)

      payload = BrandoAdmin.Components.Form.Drafts.saved_payload(Page, blueprint, entry, user)
      payload |> Map.put("modules", Brando.Drafts.Modules.manifest(payload["blocks"])) |> Brando.Drafts.Content.checksum()
    end

    # B reads A's save back without its blocks; they reach B through the
    # edit session, and so does the baseline.
    test "B's recovery baseline has the blocks A saved", c do
      [first | _] = c.uids
      assert form_assigns(c.b).draft.baseline == saved_baseline(c.b, c.page)

      Brando.EditSessionEditors.type(c.a, first, "<p>Saved by A</p>")
      save_and_stay(c.a, "page", true)
      await(fn -> Brando.EditSessionEditors.shown_text(c.b, first) == "<p>Saved by A</p>" end)
      settle(c.b)

      assert form_assigns(c.b).draft.baseline == saved_baseline(c.b, c.page)
    end
  end

  describe "an entry with a subform and an image" do
    setup %{current_user: me, a_conn: a_conn, other_conn: other_conn} = c do
      items = for {label, n} <- Enum.with_index(c[:items] || ["Old"]), do: %{label: label, sequence: n}

      {:ok, article} =
        Brando.SyncTest.create_article(
          %{title: "Article", slug: "article", language: "en", status: "published", items: items},
          me
        )

      image =
        Factory.insert(:image,
          creator: me,
          config_target: "image:Brando.SyncTest.Article:cover",
          focal: %Brando.Images.Focal{x: 50, y: 50},
          status: :processed
        )

      path = "/admin/articles/update/#{article.id}/elsewhere"
      {a, _} = live_form(a_conn, path, "article_form")
      {b, _} = live_form(other_conn, path, "article_form")

      %{article: article, image: image, a: a, b: b}
    end

    defp row_label(view), do: params(view, "article")["items"]["0"]["label"]

    defp saved_article(article), do: Article |> Repo.get!(article.id) |> Repo.preload(:items)

    test "B's edit in a row stays over A's save, and B's save writes both", c do
      type(c.b, "article", ["items", "0", "label"], "Row by B")

      type(c.a, "article", "title", "Title by A")
      save_and_stay(c.a, "article", true)
      await(fn -> params(c.b, "article")["title"] == "Title by A" end)
      assert row_label(c.b) == "Row by B"

      save_and_stay(c.b, "article", true)

      await(fn ->
        saved = saved_article(c.article)
        saved.title == "Title by A" and Enum.map(saved.items, & &1.label) == ["Row by B"]
      end)
    end

    test "a row B sets back to what it was before A's save is B's edit", c do
      type(c.a, "article", ["items", "0", "label"], "New")
      save_and_stay(c.a, "article", true)
      await(fn -> Enum.map(saved_article(c.article).items, & &1.label) == ["New"] end)
      await(fn -> row_label(c.b) == "New" end)

      type(c.b, "article", ["items", "0", "label"], "Old")
      assert row_label(c.b) == "Old"

      save_and_stay(c.b, "article", true)
      await(fn -> Enum.map(saved_article(c.article).items, & &1.label) == ["Old"] end)
    end

    # Picking the image applies the form's changes into its data
    # (`commit_entry_field_asset/5`), and the browser's `validate` that
    # follows can come after A's save.
    test "B's row edit stays when B picks an image just before A's save arrives", c do
      type(c.b, "article", ["items", "0", "label"], "Row by B")

      c.b
      |> with_target(cid_of(c.b, ~s(input[name="article[cover_id]"])))
      |> render_click("select_image", %{"id" => to_string(c.image.id)})

      picked = render(c.b)

      type(c.a, "article", "title", "Title by A")
      save_and_stay(c.a, "article", true)
      await(fn -> params(c.b, "article")["title"] == "Title by A" end)
      assert row_label(c.b) == "Row by B"

      # The browser's `validate` for the pick (`b:validate`), from the form
      # it showed before the save reached it
      type_in(c.b, "article", picked, "cover_id", to_string(c.image.id))
      assert row_label(c.b) == "Row by B"
      assert params(c.b, "article")["title"] == "Title by A"

      save_and_stay(c.b, "article", true)

      await(fn ->
        saved = saved_article(c.article)

        saved.title == "Title by A" and saved.cover_id == c.image.id and
          Enum.map(saved.items, & &1.label) == ["Row by B"]
      end)
    end

    defp row_labels(view) do
      rows = params(view, "article")["items"]
      for {_, row} <- Enum.sort_by(rows, &String.to_integer(elem(&1, 0))), do: row["label"]
    end

    defp saved_labels(article), do: Enum.map(saved_article(article).items, & &1.label)

    # Each tab edits a row of its own: B keeps its row, and the row it didn't
    # change is A's. Both changed the list, so B is asked.
    @tag items: ["Old", "Second"]
    test "B's edit in one row and A's saved edit in another both stay", c do
      type(c.b, "article", ["items", "0", "label"], "Row 0 by B")
      before = render(c.b)

      type(c.a, "article", ["items", "1", "label"], "Row 1 by A")
      save_and_stay(c.a, "article", true)
      await(fn -> saved_labels(c.article) == ["Old", "Row 1 by A"] end)

      await(fn -> row_labels(c.b) == ["Row 0 by B", "Row 1 by A"] end)
      assert conflict?(c.b, "items")

      # A keystroke from the form B's browser showed before the save reached
      # it, where row 1 is still the old one, leaves the rows as they are.
      type_in(c.b, "article", before, ["items", "0", "label"], "Row 0 by B, again")
      assert row_labels(c.b) == ["Row 0 by B", "Row 1 by A"]

      # The browser has drawn the save by its next keystroke.
      type(c.b, "article", ["items", "0", "label"], "Row 0 by B, again")
      assert row_labels(c.b) == ["Row 0 by B, again", "Row 1 by A"]

      save_and_stay(c.b, "article", true)
      await(fn -> saved_labels(c.article) == ["Row 0 by B, again", "Row 1 by A"] end)
    end

    # A row A removed stays removed in B's form unless B edited it; a row
    # B edited that A removed stays, as a new row.
    @tag items: ["Old", "Second", "Third"]
    test "a row A removed stays out of B's form, and one B edited stays", c do
      type(c.b, "article", ["items", "2", "label"], "Third by B")

      [_old, second, third] = saved_article(c.article).items
      Repo.delete!(second)
      Repo.delete!(third)
      announce_save(Article, c.article.id)

      await(fn -> row_labels(c.b) == ["Old", "Third by B"] end)
      assert conflict?(c.b, "items")

      save_and_stay(c.b, "article", true)
      await(fn -> saved_labels(c.article) == ["Old", "Third by B"] end)
    end

    # B's browser sends a keystroke in a row from the form it showed before
    # A's save reached it: the rows it sends are the ones A's save replaced,
    # so the form keeps A's. The input B types in keeps its text while it has
    # focus, and the next keystroke sends it again.
    @tag items: ["Old", "Second", "Third"]
    test "B's keystroke in a row, sent from the form before A's save, keeps A's rows", c do
      before = render(c.b)

      [_old, second, third] = saved_article(c.article).items
      second |> Ecto.Changeset.change(label: "Second by A") |> Repo.update!()
      Repo.delete!(third)
      announce_save(Article, c.article.id)
      await(fn -> row_labels(c.b) == ["Old", "Second by A"] end)

      type_in(c.b, "article", before, ["items", "0", "label"], "Row 0 by B")
      assert row_labels(c.b) == ["Old", "Second by A"]
      refute conflict?(c.b, "items")

      # The browser has drawn the save by its next keystroke.
      type(c.b, "article", ["items", "0", "label"], "Row 0 by B, again")
      assert row_labels(c.b) == ["Row 0 by B, again", "Second by A"]

      save_and_stay(c.b, "article", true)
      await(fn -> saved_labels(c.article) == ["Row 0 by B, again", "Second by A"] end)
    end

    # B edited a row A removed: B's form holds it as a new row. B's browser
    # then sends a keystroke in it from the form it showed before, which
    # names the row by its old id: the form keeps the row as it is.
    @tag items: ["Old", "Second", "Third"]
    test "a row B edited that A removed takes B's late keystroke in place", c do
      type(c.b, "article", ["items", "2", "label"], "Third by B")
      before = render(c.b)

      [_old, second, third] = saved_article(c.article).items
      Repo.delete!(second)
      Repo.delete!(third)
      announce_save(Article, c.article.id)
      await(fn -> row_labels(c.b) == ["Old", "Third by B"] end)

      type_in(c.b, "article", before, ["items", "2", "label"], "Third by B!")
      assert row_labels(c.b) == ["Old", "Third by B"]

      # The browser has drawn the save by its next keystroke.
      type(c.b, "article", ["items", "1", "label"], "Third by B!!")
      assert row_labels(c.b) == ["Old", "Third by B!!"]

      save_and_stay(c.b, "article", true)
      await(fn -> saved_labels(c.article) == ["Old", "Third by B!!"] end)
    end

    defp row_link(view), do: params(view, "article")["items"]["0"]["link"]

    # A sets the row's link and saves; B's keystroke in the row's label comes
    # from the form B's browser showed before, with the old link.
    test "B's late keystroke in a row's label keeps the link A saved in it", c do
      before = render(c.b)

      [item] = saved_article(c.article).items
      item |> Ecto.Changeset.change(link: "Link by A") |> Repo.update!()
      announce_save(Article, c.article.id)
      await(fn -> row_link(c.b) == "Link by A" end)

      type_in(c.b, "article", before, ["items", "0", "label"], "Label by B")
      assert row_label(c.b) == "Old"
      assert row_link(c.b) == "Link by A"

      # The browser has drawn the save by its next keystroke.
      type(c.b, "article", ["items", "0", "label"], "Label by B")
      assert row_label(c.b) == "Label by B"
      assert row_link(c.b) == "Link by A"

      save_and_stay(c.b, "article", true)

      await(fn ->
        [item] = saved_article(c.article).items
        item.label == "Label by B" and item.link == "Link by A"
      end)
    end

    defp row_modules(view) do
      case params(view, "article")["items"]["0"]["item_modules"] do
        %{} = rows ->
          for {_, %{"module_id" => id} = row} <- rows, row["marked_as_deleted"] != "true", do: String.to_integer(id)

        _ ->
          []
      end
    end

    # B picks a module in the multi-select of a row (the row's own relation,
    # `{:subform, :has_many}`); A's save is of the title.
    test "B's pick in a row's multi-select stays over A's save", c do
      hero = Factory.insert(:module, name: "Hero", namespace: "general")
      toggle = "#article_items_0_item_modules-field-base button.button-edit"
      c.b |> element(toggle) |> render_click()
      c.b |> element("button.multiselect-option[value='#{hero.id}']") |> render_click()
      c.b |> element(toggle) |> render_click()
      await(fn -> row_modules(c.b) == [hero.id] end)

      type(c.a, "article", "title", "Title by A")
      save_and_stay(c.a, "article", true)
      await(fn -> params(c.b, "article")["title"] == "Title by A" end)
      assert row_modules(c.b) == [hero.id]

      save_and_stay(c.b, "article", true)

      await(fn ->
        saved = Article |> Repo.get!(c.article.id) |> Repo.preload(items: :item_modules)
        saved.title == "Title by A" and Enum.map(hd(saved.items).item_modules, & &1.module_id) == [hero.id]
      end)
    end

    # B's edit in the row doesn't cast: the row's values are the saved ones,
    # and what B typed is in its params, with the error.
    test "B's row edit that didn't cast stays over A's save, with its error", c do
      type(c.b, "article", ["items", "0", "sequence"], "1.5")
      assert [%{errors: [sequence: _]}] = form_assigns(c.b).form.source.changes.items

      type(c.a, "article", "title", "Title by A")
      save_and_stay(c.a, "article", true)
      await(fn -> params(c.b, "article")["title"] == "Title by A" end)

      assert [%{errors: [sequence: _]} = row] = form_assigns(c.b).form.source.changes.items
      assert row.params["sequence"] == "1.5"
      refute form_assigns(c.b).form.source.valid?
    end

    # A picks a module in row 0 and saves, while row 1 holds B's edit.
    @tag items: ["Old", "Second"]
    test "B's edit in one row stays over A's save of a pick in another row", c do
      hero = Factory.insert(:module, name: "Hero", namespace: "general")
      type(c.b, "article", ["items", "1", "label"], "Second by B")

      toggle = "#article_items_0_item_modules-field-base button.button-edit"
      c.a |> element(toggle) |> render_click()
      c.a |> element("button.multiselect-option[value='#{hero.id}']") |> render_click()
      c.a |> element(toggle) |> render_click()
      assert row_modules(c.a) == [hero.id]

      save_and_stay(c.a, "article", true)

      await(fn ->
        [item | _] = Article |> Repo.get!(c.article.id) |> Repo.preload(items: :item_modules) |> Map.fetch!(:items)
        Enum.map(item.item_modules, & &1.module_id) == [hero.id]
      end)

      settle(c.b)
      assert row_labels(c.b) == ["Old", "Second by B"]
      assert row_modules(c.b) == [hero.id]

      save_and_stay(c.b, "article", true)

      await(fn ->
        items = Article |> Repo.get!(c.article.id) |> Repo.preload(items: :item_modules) |> Map.fetch!(:items)

        Enum.map(items, & &1.label) == ["Old", "Second by B"] and
          Enum.map(hd(items).item_modules, & &1.module_id) == [hero.id]
      end)
    end

    # A picks a module in the row's multi-select and saves; B's keystroke in
    # the row's label comes from the form B's browser showed before.
    test "B's late keystroke in a row's label keeps the pick A saved in it", c do
      hero = Factory.insert(:module, name: "Hero", namespace: "general")
      before = render(c.b)

      [item] = saved_article(c.article).items
      Repo.insert!(%Brando.SyncTest.ArticleItemModule{item_id: item.id, module_id: hero.id, sequence: 0})
      announce_save(Article, c.article.id)
      await(fn -> row_modules(c.b) == [hero.id] end)

      type_in(c.b, "article", before, ["items", "0", "label"], "Label by B")
      assert row_label(c.b) == "Old"
      assert row_modules(c.b) == [hero.id]

      # The browser has drawn the save by its next keystroke.
      type(c.b, "article", ["items", "0", "label"], "Label by B")
      assert row_label(c.b) == "Label by B"
      assert row_modules(c.b) == [hero.id]

      save_and_stay(c.b, "article", true)

      await(fn ->
        [item] = Article |> Repo.get!(c.article.id) |> Repo.preload(items: :item_modules) |> Map.fetch!(:items)
        item.label == "Label by B" and Enum.map(item.item_modules, & &1.module_id) == [hero.id]
      end)
    end

    # The form's `after_save` writes to the entry once the save is done; the
    # other tabs read the entry after it.
    test "what the form's after_save writes reaches B", c do
      type(c.a, "article", "title", "Written after save")
      save_and_stay(c.a, "article", true)
      await(fn -> Repo.get!(Article, c.article.id).subtitle == "Set by after_save" end)

      await(fn -> params(c.b, "article")["subtitle"] == "Set by after_save" end)
    end

    # The blocks sync through the edit session; B reads the entry's fields
    # back, not its blocks.
    test "B reads A's save back without the blocks", c do
      test = self()
      id = {__MODULE__, :queries, make_ref()}
      b_pid = c.b.pid

      :telemetry.attach(
        id,
        [:brando_integration, :repo, :query],
        fn _event, _measurements, meta, _config ->
          if b_pid in [self() | Process.get(:"$callers", [])], do: send(test, {:b_query, meta.source})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(id) end)

      type(c.a, "article", "title", "Title by A")
      save_and_stay(c.a, "article", true)
      await(fn -> params(c.b, "article")["title"] == "Title by A" end)
      :telemetry.detach(id)

      sources = collect_queries([])
      assert "synctest_articles" in sources
      refute Enum.any?(sources, &(&1 in ["synctest_articles_blocks", "synctest_articles_notes", "content_blocks"]))
    end
  end

  defp collect_queries(sources) do
    receive do
      {:b_query, source} -> collect_queries([source | sources])
    after
      0 -> sources
    end
  end

  describe "a has_one subform" do
    setup %{current_user: me, a_conn: a_conn, other_conn: other_conn} do
      {:ok, article} =
        Brando.SyncTest.create_article(
          %{title: "Article", slug: "article", language: "en", status: "published"},
          me
        )

      Repo.insert!(%Brando.SyncTest.ArticleAuthor{article_id: article.id, name: "Old name"})

      path = "/admin/articles/update/#{article.id}/author"
      {a, _} = live_form(a_conn, path, "article_form")
      {b, _} = live_form(other_conn, path, "article_form")

      %{article: article, a: a, b: b}
    end

    test "B's edit stays over A's save, and B's save writes both", c do
      type(c.b, "article", ["author", "name"], "Name by B")

      type(c.a, "article", "title", "Title by A")
      save_and_stay(c.a, "article", true)
      await(fn -> params(c.b, "article")["title"] == "Title by A" end)
      assert params(c.b, "article")["author"]["name"] == "Name by B"

      save_and_stay(c.b, "article", true)

      await(fn ->
        saved = Article |> Repo.get!(c.article.id) |> Repo.preload(:author)
        saved.title == "Title by A" and saved.author.name == "Name by B"
      end)
    end
  end

  describe "a has_one subform, empty" do
    setup %{current_user: me, a_conn: a_conn, other_conn: other_conn} do
      {:ok, article} =
        Brando.SyncTest.create_article(%{title: "Article", slug: "article", language: "en", status: "published"}, me)

      path = "/admin/articles/update/#{article.id}/author"
      {a, _} = live_form(a_conn, path, "article_form")
      {b, _} = live_form(other_conn, path, "article_form")

      %{article: article, a: a, b: b}
    end

    defp saved_authors(article), do: Repo.all(Ecto.assoc(article, :author))

    # Both tabs fill in the author the article doesn't have; A saves first.
    test "B's author, typed when A saved one, goes onto the saved author", c do
      type(c.b, "article", ["author", "name"], "Name by B")

      type(c.a, "article", ["author", "name"], "Name by A")
      save_and_stay(c.a, "article", true)
      await(fn -> Enum.map(saved_authors(c.article), & &1.name) == ["Name by A"] end)

      await(fn -> form_assigns(c.b).entry.author != nil end)
      assert Process.alive?(c.b.pid)
      assert params(c.b, "article")["author"]["name"] == "Name by B"

      save_and_stay(c.b, "article", true)
      await(fn -> Enum.map(saved_authors(c.article), & &1.name) == ["Name by B"] end)
    end
  end

  describe "an embeds_many subform" do
    setup %{current_user: me, a_conn: a_conn, other_conn: other_conn} do
      palette = Factory.insert(:palette, creator: me, status: :published, colors: [Factory.build(:color)])
      path = "/admin/config/content/palettes/update/#{palette.id}"
      {a, _} = live_form(a_conn, path, "palette_form")
      {b, _} = live_form(other_conn, path, "palette_form")
      %{palette: palette, a: a, b: b}
    end

    test "B's edit in a row stays over A's save, and B's save writes both", c do
      type(c.b, "palette", ["colors", "0", "name"], "Color by B")

      type(c.a, "palette", "instructions", "Instructions by A")
      save_and_stay(c.a, "palette", false)
      await(fn -> params(c.b, "palette")["instructions"] == "Instructions by A" end)
      assert params(c.b, "palette")["colors"]["0"]["name"] == "Color by B"

      save_and_stay(c.b, "palette", false)

      await(fn ->
        saved = Repo.get!(Brando.Content.Palette, c.palette.id)
        saved.instructions == "Instructions by A" and Enum.map(saved.colors, & &1.name) == ["Color by B"]
      end)
    end
  end

  describe "a has_many that can't replace a row" do
    setup %{current_user: me, a_conn: a_conn, other_conn: other_conn} do
      {:ok, article} =
        Brando.SyncTest.create_article(
          %{title: "Shelf", slug: "shelf", language: "en", status: "published", items: [%{label: "Old", sequence: 0}]},
          me
        )

      %{shelf: article, a_conn: a_conn, other_conn: other_conn}
    end

    defp shelf_labels(shelf),
      do:
        Brando.SavedElsewhereTest.Shelf
        |> Repo.get!(shelf.id)
        |> Repo.preload(:items)
        |> Map.fetch!(:items)
        |> Enum.map(& &1.label)

    # The form reads the entry without its rows (`query`): they are not the
    # form's to keep.
    test "a form that leaves the rows unloaded takes A's save", c do
      path = "/admin/shelves/update/#{c.shelf.id}/title-only"
      {a, _} = live_form(c.a_conn, path, "shelf_form")
      {b, _} = live_form(c.other_conn, path, "shelf_form")

      type(a, "shelf", "title", "Shelf by A")
      save_and_stay(a, "shelf", false)
      await(fn -> Repo.get!(Brando.SavedElsewhereTest.Shelf, c.shelf.id).title == "Shelf by A" end)

      await(fn -> params(b, "shelf")["title"] == "Shelf by A" end)
      assert Process.alive?(b.pid)
    end

    # A adds a row and saves; B's browser sends the form it showed before,
    # without A's row.
    test "B's keystroke from the form before A's save keeps A's row", c do
      path = "/admin/shelves/update/#{c.shelf.id}"
      {b, _} = live_form(c.other_conn, path, "shelf_form")
      before = render(b)

      Repo.insert!(%Brando.SyncTest.ArticleItem{article_id: c.shelf.id, label: "Added by A", sequence: 1})
      announce_save(Brando.SavedElsewhereTest.Shelf, c.shelf.id)
      await(fn -> map_size(params(b, "shelf")["items"]) == 2 end)

      # As the browser sends it: the form it showed, which has no row of A's
      # (`render_change/2` would add the inputs the view shows now).
      params =
        before
        |> form_params("#shelf_form_form")
        |> put_in(["shelf", "title"], "Shelf by B")
        |> Map.put("_target", ["shelf", "title"])

      refute Enum.any?(Map.values(params["shelf"]["items"]), &(&1["label"] == "Added by A"))
      b |> form_of("shelf") |> render_hook("validate", params)
      assert Process.alive?(b.pid)
      assert params(b, "shelf")["title"] == "Shelf by B"

      save_and_stay(b, "shelf", false)

      await(fn ->
        Repo.get!(Brando.SavedElsewhereTest.Shelf, c.shelf.id).title == "Shelf by B" and
          shelf_labels(c.shelf) == ["Old", "Added by A"]
      end)
    end
  end
end
