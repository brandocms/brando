defmodule BrandoAdmin.EntrySavedElsewhereTest do
  # Two editors in one entry; A saves. B's form takes what A saved in every
  # field B has not edited: a has_many list, which doesn't ship as a field
  # change, and a value the save set itself (`publish_at`). The fields B
  # edited keep B's values and stay B's edits. Before, B kept the values it
  # opened with, and B's save (or recovery copy) reverted A's.
  use Brando.LiveCase

  import Brando.EditSessionEditors, only: [await: 1]

  alias Brando.Content.ModuleSet
  alias Brando.Pages.Page

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
  # with one field changed and named.
  defp type(view, singular, field, value) do
    params =
      view
      |> render()
      |> form_params("##{singular}_form_form")
      |> put_in([singular, field], value)
      |> Map.put("_target", [singular, field])

    view |> element("##{singular}_form_form") |> render_change(params)
  end

  defp params(view, singular), do: view |> render() |> form_params("##{singular}_form_form") |> Map.fetch!(singular)

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

  describe "a has_many list" do
    setup %{current_user: me, a_conn: a_conn, other_conn: other_conn} do
      [hero, text] = for name <- ["Hero", "Text"], do: Factory.insert(:module, name: name, namespace: "general")
      set = Repo.insert!(%ModuleSet{title: "Set", creator_id: me.id})
      path = "/admin/config/content/module_sets/update/#{set.id}"

      {a, _} = live_form(a_conn, path, "module_set_form")
      {b, _} = live_form(other_conn, path, "module_set_form")

      %{set: set, hero: hero, text: text, path: path, a: a, b: b}
    end

    # Opens the options, picks one and closes them, as an editor does.
    defp pick(view, module) do
      view |> element("#module_set_module_set_modules-field-base button.button-edit") |> render_click()
      view |> element("button.multiselect-option[value='#{module.id}']") |> render_click()
      view |> element("#module_set_module_set_modules-field-base button.button-edit") |> render_click()
    end

    # The modules the form holds; none is an empty marker, `""`.
    defp chosen(view) do
      case params(view, "module_set")["module_set_modules"] do
        %{} = rows -> for {_, %{"module_id" => id}} <- rows, do: String.to_integer(id)
        _ -> []
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

    # Picks reach another editor's open options as they are made
    # (`multi_select_changed`), but not another tab of the same editor.
    test "a pick of B's own stays over A's save", c do
      {b, _} = live_form(c.a_conn, c.path, "module_set_form")

      Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.entry("field_sync", ModuleSet, c.set.id))
      pick(c.a, c.hero)
      pick(b, c.text)
      save_and_stay(c.a, "module_set", false)
      assert_receive {:entry_saved, _}, 5_000
      assert saved_modules(c.set) == [c.hero.id]
      # B's process has the message too: the renders queue behind it.
      settle(b)

      assert chosen(b) == [c.text.id]

      save_and_stay(b, "module_set", false)
      await(fn -> saved_modules(c.set) == [c.text.id] end)
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

      main = b |> render() |> form_params("#module_set_form_form") |> Plug.Conn.Query.encode()

      b
      |> with_target(cid_of(b, "#module_set_form-el"))
      |> render_hook("draft_capture", %{"main" => main, "blocks" => %{}, "generation" => 1, "request_id" => 1})

      [copy] = Brando.Drafts.list(Brando.Drafts.identity(ModuleSet, c.set.id, c.me.id))
      assert copy.payload["main"]["title"] == "Set, typed in B"

      assert copy.payload["main"]["module_set_modules"] |> Enum.map(& &1["module_id"]) |> Enum.sort() ==
               Enum.sort([c.hero.id, c.text.id])
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
  end
end
