defmodule BrandoAdmin.EntryFieldSyncTest do
  # Two editors in one entry's fields (title, URI), through real LiveViews.
  # Each edit is an op on the one field the editor changed: an editor ships
  # what it changed since its last shipment, a value set back to the saved
  # one included, and never a value it merely holds.
  use Brando.LiveCase

  import Brando.EditSessionEditors, only: [await: 1]

  alias Brando.Pages.Page

  setup %{current_user: me, conn: conn} do
    page = Factory.insert(:page, creator: me, title: "Om oss", uri: "om-oss")
    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    other_conn = log_in_user(Phoenix.ConnTest.build_conn(), other)

    a = open(conn, page)
    b = open(other_conn, page)

    %{page: page, me: me, other: other, a: a, b: b}
  end

  defp open(conn, page) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    view
  end

  # The Form component, which takes the focus and blur of its fields.
  defp form(view) do
    cid =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("[data-phx-component]")
      |> Enum.filter(&(Floki.find(&1, "#page_form-el") != []))
      |> Enum.min_by(&(&1 |> Floki.raw_html() |> byte_size()))
      |> Floki.attribute("data-phx-component")
      |> hd()
      |> String.to_integer()

    with_target(view, cid)
  end

  defp focus(view, field), do: view |> form() |> render_hook("focus", %{"field" => "page[#{field}]"})

  defp blur(view), do: view |> form() |> render_hook("blur", %{})

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

  test "an editor who joins gets the unsaved fields, and the others keep theirs", c do
    edit(c.a, "title", "Om oss, A")
    await_shown(c.b, "title", "Om oss, A")
    focus(c.b, "uri")
    type(c.b, "uri", "om-oss-b")

    third = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    joiner = open(log_in_user(Phoenix.ConnTest.build_conn(), third), c.page)

    await_shown(joiner, "title", "Om oss, A")
    await_shown(joiner, "uri", "om-oss-b")
    settle(c.a)
    assert shown(c.a, "uri") == "om-oss"
    assert shown(c.b, "uri") == "om-oss-b"
  end

  describe "field locks" do
    setup c do
      Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.entry("active_field", Page, c.page.id))
      :ok
    end

    test "a blur releases the field for the other editors", c do
      focus(c.a, "title")
      assert_receive {:active_field, "page[title]", user_id} when user_id == c.me.id
      assert_push_event(c.b, "b:set_active_field", %{field: "page[title]"})

      blur(c.a)
      assert_receive {:active_field, nil, user_id} when user_id == c.me.id
      assert_push_event(c.b, "b:set_active_field", %{field: nil})
      await(fn -> presence_meta(c.page, c.me).active_field == nil end)
    end

    test "leaving the entry releases the field", c do
      focus(c.a, "title")
      assert_push_event(c.b, "b:set_active_field", %{field: "page[title]"})
      await(fn -> presence_meta(c.page, c.me).active_field == "page[title]" end)

      kill_live(c.a)
      user_id = c.me.id
      assert_push_event(c.b, "b:clear_user_presence", %{user_id: ^user_id}, 2_000)
    end
  end

  defp presence_meta(page, user) do
    "url:/admin/pages/update/#{page.id}"
    |> Brando.Tenant.Topic.scoped()
    |> Brando.presence().list()
    |> then(&(Map.get(&1, to_string(user.id)) || Map.get(&1, user.id) || %{metas: [%{active_field: :absent}]}))
    |> Map.get(:metas)
    |> hd()
  end
end
