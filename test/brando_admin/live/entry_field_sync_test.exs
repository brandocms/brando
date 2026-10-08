defmodule BrandoAdmin.EntryFieldSyncTest do
  # Two editors in one entry's fields (title, URI), through real LiveViews.
  # Each edit is an op on the one field the editor changed: an editor ships
  # what it changed since its last shipment, a value set back to the saved
  # one included, and never a value it merely holds.
  use Brando.LiveCase

  import Brando.EditSessionEditors, only: [await: 1]
  import Ecto.Query, only: [from: 2]

  alias Brando.Pages.Page

  setup %{current_user: me, conn: conn} do
    page = Factory.insert(:page, creator: me, title: "Om oss", uri: "om-oss")
    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    other_conn = log_in_user(Phoenix.ConnTest.build_conn(), other)

    a = open(conn, page)
    b = open(other_conn, page)

    %{page: page, me: me, other: other, other_conn: other_conn, a: a, b: b}
  end

  defp open(conn, page) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    view
  end

  # The Form component, which takes the focus and blur of its fields.
  defp form(view), do: with_target(view, cid_of(view, "#page_form-el"))

  defp focus(view, field), do: view |> form() |> render_hook("focus", %{"field" => "page[#{field}]"})

  defp blur(view, field \\ "title"), do: view |> form() |> render_hook("blur", %{"field" => "page[#{field}]"})

  # A keystroke as the browser sends it: the whole form, from what the view
  # shows (or showed: `shown`), with one field changed and named.
  defp type(view, field, value, shown \\ nil) do
    params =
      (shown || render(view))
      |> form_params("#page_form_form")
      |> put_in(["page", field], value)
      |> Map.put("_target", ["page", field])

    view |> element("#page_form_form") |> render_change(params)
  end

  defp edit(view, field, value) do
    focus(view, field)
    type(view, field, value)
    blur(view)
  end

  defp shown(view, field), do: view |> render() |> form_params("#page_form_form") |> get_in(["page", field])

  defp shows?(view, field, value), do: shown(view, field) == value

  defp await_shown(view, field, value), do: await(fn -> shows?(view, field, value) end)

  # Both editors end where they should, and stay there once every message
  # has arrived.
  defp assert_both(%{a: a, b: b}, expected) do
    for view <- [a, b], {field, value} <- expected, do: await_shown(view, field, value)
    settle(a) && settle(b)
    for view <- [a, b], {field, value} <- expected, do: assert(shown(view, field) == value)
  end

  test "a title set back to its saved value reaches the other editor, and their next field doesn't undo it", c do
    edit(c.a, "title", "Om oss, A")
    await_shown(c.b, "title", "Om oss, A")

    edit(c.b, "title", "Om oss")
    await_shown(c.a, "title", "Om oss")

    edit(c.a, "uri", "om-oss-a")

    assert_both(c, %{"title" => "Om oss", "uri" => "om-oss-a"})
  end

  test "another editor's new title survives the first editor's next field", c do
    edit(c.a, "title", "Om oss, A")
    await_shown(c.b, "title", "Om oss, A")

    edit(c.b, "title", "Om oss, B")
    await_shown(c.a, "title", "Om oss, B")

    edit(c.a, "uri", "om-oss-a")

    assert_both(c, %{"title" => "Om oss, B", "uri" => "om-oss-a"})
  end

  test "three reverts in a row each reach the other editor", c do
    for n <- 1..3 do
      edit(c.a, "title", "Om oss #{n}")
      await_shown(c.b, "title", "Om oss #{n}")

      edit(c.b, "title", "Om oss")
      await_shown(c.a, "title", "Om oss")

      edit(c.a, "uri", "om-oss-#{n}")
      assert_both(c, %{"title" => "Om oss", "uri" => "om-oss-#{n}"})
    end
  end

  test "two editors typing in different fields without leaving them in between", c do
    focus(c.a, "title")
    focus(c.b, "uri")

    type(c.a, "title", "Om oss, A")
    type(c.b, "uri", "om-oss-b")
    type(c.a, "title", "Om oss, AA")
    type(c.b, "uri", "om-oss-bb")

    blur(c.a)
    await_shown(c.b, "title", "Om oss, AA")
    type(c.b, "uri", "om-oss-bbb")
    blur(c.b)

    assert_both(c, %{"title" => "Om oss, AA", "uri" => "om-oss-bbb"})
  end

  # The browser sends the form as it showed it: a keystroke B sent before
  # A's title reached its page carries B's old title.
  test "a keystroke sent before another editor's change arrived does not undo that change", c do
    focus(c.b, "uri")
    before = render(c.b)

    edit(c.a, "title", "Om oss, A")
    await_shown(c.b, "title", "Om oss, A")

    type(c.b, "uri", "om-oss-b", before)
    blur(c.b)

    assert_both(c, %{"title" => "Om oss, A", "uri" => "om-oss-b"})
  end

  test "a change that arrives while the field is focused applies on blur when nothing was typed", c do
    focus(c.a, "title")

    edit(c.b, "title", "Om oss, B")
    settle(c.a)
    blur(c.a)

    assert_both(c, %{"title" => "Om oss, B"})
  end

  # B's block field joins the edit session a moment after its form loads,
  # so its join can reach A after B has shipped. A, holding B's title for
  # the field it is in, must not send B the title its form still shows.
  test "an editor who joins late is sent the held value, not the one on screen", c do
    focus(c.a, "title")

    edit(c.b, "title", "Om oss, B")
    settle(c.a)
    send(c.a.pid, {:editor_joined, %{user_id: c.other.id}})
    settle(c.a)
    settle(c.b)
    blur(c.a)

    assert_both(c, %{"title" => "Om oss, B"})
  end

  test "what was typed in a focused field wins over a change that arrived meanwhile", c do
    focus(c.a, "title")

    edit(c.b, "title", "Om oss, B")
    settle(c.a)
    type(c.a, "title", "Om oss, A")
    blur(c.a)

    assert_both(c, %{"title" => "Om oss, A"})
  end

  test "each editor saves what both see", c do
    edit(c.a, "title", "Om oss, A")
    await_shown(c.b, "title", "Om oss, A")
    edit(c.b, "title", "Om oss")
    await_shown(c.a, "title", "Om oss")
    edit(c.a, "uri", "om-oss-a")
    assert_both(c, %{"title" => "Om oss", "uri" => "om-oss-a"})

    # A save is two submits: the first collects the blocks, the second writes.
    c.b |> element("#page_form_form") |> render_submit()
    assert_push_event(c.b, "b:submit", %{}, 5_000)
    c.b |> element("#page_form_form") |> render_submit()

    await(fn ->
      saved = Repo.get!(Page, c.page.id)
      saved.title == "Om oss" and saved.uri == "om-oss-a"
    end)
  end

  # A's title reaches the joiner from B as well; the other editors are not
  # sent values they already hold.
  test "an editor who joins gets the unsaved fields", c do
    edit(c.a, "title", "Om oss, A")
    await_shown(c.b, "title", "Om oss, A")
    focus(c.b, "uri")
    type(c.b, "uri", "om-oss-b")

    Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.entry("field_sync", Page, c.page.id))
    third = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    joiner = open(log_in_user(Phoenix.ConnTest.build_conn(), third), c.page)

    await_shown(joiner, "title", "Om oss, A")
    await_shown(joiner, "uri", "om-oss-b")
    assert_both(c, %{"title" => "Om oss, A", "uri" => "om-oss-b"})

    to_everyone = for {:fields_shipped, %{to: nil, changes: changes}} <- messages(), change <- changes, do: change.field
    assert to_everyone == [:uri]
  end

  # A value the form writes itself, with no browser event to follow, ships at
  # once: AI text here, an image copy or an uploaded video likewise
  # (`update_changeset/3,4`).
  test "a value the form writes itself reaches the other editor", c do
    Brando.AIStub.configure()
    Brando.AIStub.reply("A description by A")

    c.a
    |> form()
    |> render_hook("ai_generate_input", %{"field_name" => "page[meta_description]", "field_key" => "meta_description"})

    await_shown(c.b, "meta_description", "A description by A")
  end

  # The reconnected tab's browser sends its old form (`recover_form`); the
  # other editor changed the title meanwhile. The recovered title is not a
  # change of B's and must not undo A's.
  test "a reconnect doesn't ship the browser's old values", c do
    edit(c.b, "title", "Om oss, B")
    await_shown(c.a, "title", "Om oss, B")
    before = render(c.b)
    kill_live(c.b)

    edit(c.a, "title", "Om oss, A")
    b = open(c.other_conn, c.page)
    await_shown(b, "title", "Om oss, A")

    recovered = before |> form_params("#page_form_form") |> Map.put("_target", ["image_editor_upload"])
    b |> form() |> render_hook("recover_form", recovered)
    assert shown(b, "title") == "Om oss, A"

    # After a reconnect the input can still have the focus, so a blur comes
    # without a focus first, and still ships what was typed.
    type(b, "uri", "om-oss-b")
    blur(b, "uri")

    await_shown(c.a, "uri", "om-oss-b")
    assert_both(%{a: c.a, b: b}, %{"title" => "Om oss, A", "uri" => "om-oss-b"})
  end

  test "an editor of an entry without block fields who joins gets the unsaved fields", %{conn: conn, me: me} do
    {:ok, article} =
      Brando.SyncTest.create_article(
        %{title: "No blocks", slug: "no-blocks-sync", language: "en", status: "published", year: 2020},
        me
      )

    path = "/admin/articles/update/#{article.id}/no-blocks"
    {a, _html} = live_form(conn, path, "article_form")
    a_form = with_target(a, cid_of(a, "#article_form-el"))
    a_form |> render_hook("focus", %{"field" => "article[title]"})

    params =
      a
      |> render()
      |> form_params("#article_form_form")
      |> put_in(["article", "title"], "No blocks, typed by A")
      |> Map.put("_target", ["article", "title"])

    a |> element("#article_form_form") |> render_change(params)

    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    {b, _html} = live_form(log_in_user(Phoenix.ConnTest.build_conn(), other), path, "article_form")

    await(fn ->
      b |> render() |> form_params("#article_form_form") |> get_in(["article", "title"]) ==
        "No blocks, typed by A"
    end)
  end

  # Both send the title at once: each gets the other's value while still
  # in the field, and leaving it, the one who typed ships theirs on top. The
  # clocks make both end with the same title.
  test "two editors leaving one field at once end with the same value", c do
    focus(c.a, "title")
    focus(c.b, "title")
    type(c.a, "title", "Om oss, A")
    type(c.b, "title", "Om oss, B")

    blur(c.a)
    blur(c.b)

    settle(c.a) && settle(c.b)
    assert shown(c.a, "title") == shown(c.b, "title")
  end

  describe "field locks" do
    setup c do
      Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.entry("active_field", Page, c.page.id))
      :ok
    end

    test "a blur releases the field for the other editors", c do
      focus(c.a, "title")
      assert_receive {:active_field, "page[title]", user_id, _tab} when user_id == c.me.id
      assert_push_event(c.b, "b:set_active_field", %{field: "page[title]"})

      blur(c.a)
      assert_receive {:active_field, nil, user_id, _tab} when user_id == c.me.id
      assert_push_event(c.b, "b:set_active_field", %{field: nil})
      await(fn -> presence_meta(c.page, c.me).active_field == nil end)
    end

    # Every presence write is a diff every editor's process handles. The
    # meta only serves editors who join later, so moving between fields
    # writes it once, after the moves settle.
    test "moving between fields writes the tab's presence once", c do
      Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.scoped("url:/admin/pages/update/#{c.page.id}"))

      focus(c.a, "title")
      blur(c.a)
      focus(c.a, "uri")
      await(fn -> presence_meta(c.page, c.me).active_field == "page[uri]" end)
      Process.sleep(400)

      diffs = for %Phoenix.Socket.Broadcast{event: "presence_diff"} <- messages(), do: :diff
      assert length(diffs) == 1
    end

    test "leaving the entry releases the field", c do
      focus(c.a, "title")
      assert_push_event(c.b, "b:set_active_field", %{field: "page[title]"})
      await(fn -> presence_meta(c.page, c.me).active_field == "page[title]" end)

      kill_live(c.a)
      user_id = c.me.id
      assert_push_event(c.b, "b:clear_user_presence", %{user_id: ^user_id}, 2_000)
    end

    test "an image field is locked while its drawer is open, and every way of closing it releases it", c do
      image = Factory.insert(:image, creator: c.me, focal: %Brando.Images.Focal{x: 50, y: 50}, status: :processed)
      Repo.update_all(from(p in Page, where: p.id == ^c.page.id), set: [meta_image_id: image.id])
      a = open(c.conn, c.page)

      # ×, Done and the backdrop; Escape runs the drawer's `data-modal-close`,
      # the same commands as ×.
      for close <- [".drawer-close-button", ".drawer-footer .workspace-button.primary", "+ .media-drawer-backdrop"] do
        a |> element("#page_meta_image-media button[phx-click*=open_image]") |> render_click()
        assert_push_event(c.b, "b:set_active_field", %{field: "page[meta_image]"})

        # The drawer's own inputs are the image's, not the entry's: they
        # neither take the lock nor release it.
        a |> form() |> render_hook("focus", %{"field" => "image[alt][en]"})
        a |> form() |> render_hook("blur", %{"field" => "image[alt][en]"})
        refute_push_event(c.b, "b:set_active_field", %{field: nil}, 100)

        a |> element("#image-drawer #{close}") |> render_click()
        assert_push_event(c.b, "b:set_active_field", %{field: nil})
      end

      assert a |> element("#image-drawer") |> render() =~ ~s(data-modal-close=)
      assert a |> element("#image-drawer") |> render() =~ "&quot;blur&quot;"
    end

    test "removing the image from its drawer ships the removal", c do
      image = Factory.insert(:image, creator: c.me, focal: %Brando.Images.Focal{x: 50, y: 50}, status: :processed)
      Repo.update_all(from(p in Page, where: p.id == ^c.page.id), set: [meta_image_id: image.id])
      a = open(c.conn, c.page)
      b = open(c.other_conn, c.page)

      a |> element("#page_meta_image-media button[phx-click*=open_image]") |> render_click()
      a |> element("#image-drawer button.destructive") |> render_click()

      await_shown(b, "meta_image_id", "")
    end

    # One editor with the entry open in two tabs, each in its own field: the
    # other editor sees both, and closing one tab releases only its field.
    test "locks are per tab, and closing a tab releases only its field", c do
      second_tab = open(c.conn, c.page)

      focus(c.a, "title")
      assert_push_event(c.b, "b:set_active_field", %{field: "page[title]", tab: first})
      focus(second_tab, "uri")
      assert_push_event(c.b, "b:set_active_field", %{field: "page[uri]", tab: second})
      assert first != second

      kill_live(c.a)
      assert_push_event(c.b, "b:set_active_field", %{field: nil, tab: ^first}, 2_000)
      refute_push_event(c.b, "b:set_active_field", %{field: nil, tab: ^second}, 300)
      refute_push_event(c.b, "b:clear_user_presence", %{}, 100)
    end

    # Moving to another field updates the tab's presence: a leave and a join
    # of the same tab. That must not release the field it moved to.
    test "a tab moving between fields is never released by its own presence update", c do
      _second_tab = open(c.conn, c.page)

      focus(c.a, "title")
      assert_push_event(c.b, "b:set_active_field", %{field: "page[title]", tab: tab})
      focus(c.a, "uri")
      assert_push_event(c.b, "b:set_active_field", %{field: "page[uri]", tab: ^tab})
      await(fn -> Enum.any?(presence_metas(c.page, c.me), &(&1.active_field == "page[uri]")) end)
      settle(c.b)

      refute_push_event(c.b, "b:set_active_field", %{field: nil, tab: ^tab}, 300)
    end
  end

  defp messages, do: self() |> Process.info(:messages) |> elem(1)

  defp presence_meta(page, user), do: page |> presence_metas(user) |> List.first(%{active_field: :absent})

  defp presence_metas(page, user) do
    "url:/admin/pages/update/#{page.id}"
    |> Brando.Tenant.Topic.scoped()
    |> Brando.presence().list()
    |> then(&(Map.get(&1, to_string(user.id)) || Map.get(&1, user.id) || %{metas: []}))
    |> Map.get(:metas)
  end
end
