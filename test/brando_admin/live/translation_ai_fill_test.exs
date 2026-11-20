defmodule BrandoAdmin.TranslationAIFillTest do
  # Translate with AI on a synchronized translation's work list (#3749): the
  # model's texts fill the form as unsaved changes, for the editor to check
  # and save. The model is a stub.
  use Brando.LiveCase

  import Brando.EditSessionEditors, only: [await: 1]

  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.TranslationFixtures
  alias Brando.Translations

  @text ["entry_block", "block", "refs", "0", "data", "data", "text"]

  setup %{current_user: user} do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Text"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: "{% ref refs.body %}",
          refs: [%{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "Default"}}}]
        ),
        user
      )

    %{module: module}
  end

  defp source(c, title, text, language \\ "no") do
    {:ok, source} =
      SyncTest.create_article(
        %{title: title, slug: Brando.Utils.slugify(title), language: language, status: "published", year: 2020},
        c.current_user
      )

    TranslationFixtures.add_block(source, c.module, c.current_user, text, 0)
    source
  end

  defp load(id) do
    {:ok, entry} = SyncTest.get_article(%{matches: %{id: id}, preload: Brando.Blueprint.preloads_for(Article)})
    entry
  end

  defp set_body(id, text) do
    ref = Enum.find(Repo.preload(hd(load(id).entry_blocks).block, :refs, force: true).refs, &(&1.name == "body"))
    ref |> Ecto.Changeset.change(data: %{ref.data | data: %{ref.data.data | text: text}}) |> Repo.update!()
  end

  defp block_uid(id), do: hd(load(id).entry_blocks).block.uid
  defp block_key(id), do: "entry_blocks/#{hd(load(id).entry_blocks).block.sync_uid}/refs/body/text"

  defp open_items(id) do
    case Translations.get_pending_version(Article, id) do
      nil -> []
      version -> for item <- version.work_items, is_nil(item.resolved_at), do: item.path
    end
  end

  defp open(conn, id, query \\ "") do
    {view, _html} = live_form(conn, "/admin/articles/update/#{id}#{query}", "article_form")
    version = Translations.get_pending_version(Article, id)
    await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")
    await_selector(view, "[data-block-uid]")
    view
  end

  defp title(view), do: view |> render() |> form_params("#article_form_form") |> get_in(["article", "title"])
  defp block_text(view, uid), do: view |> render() |> form_params("#entry_block_form-#{uid}") |> get_in(@text)

  defp item(key), do: "#translation-panel [data-translation-item='#{key}']"

  defp translate_all(view), do: view |> element("#translation-panel [data-testid=translation-ai-all]") |> render_click()

  defp translate_one(view, key),
    do: view |> element("#{item(key)} [data-testid=translation-ai-item]") |> render_click()

  # The items the prompt sends
  defp items(prompt) do
    [json] = Regex.run(~r/\{"items":.*\}/s, prompt)
    json |> Jason.decode!() |> Map.fetch!("items")
  end

  # Answers each item with `fun` of it
  defp answer(fun) do
    Brando.AIStub.reply(fn prompt -> prompt |> items() |> Map.new(&{&1["n"], fun.(&1)}) |> Jason.encode!() end)
  end

  # A model that waits for the test before it answers: `{:ai_waiting, pid}`
  # comes first, then `send(pid, :answer)`.
  defp answer_when_told(fun) do
    test = self()

    Brando.AIStub.reply(fn prompt ->
      send(test, {:ai_waiting, self()})

      receive do
        :answer -> prompt |> items() |> Map.new(&{&1["n"], fun.(&1)}) |> Jason.encode!()
      after
        5_000 -> {:error, 504}
      end
    end)
  end

  # Answers each item with "EN " and its source, and sends the test each prompt
  defp answer_and_report do
    test = self()

    Brando.AIStub.reply(fn prompt ->
      send(test, {:prompt, prompt})
      prompt |> items() |> Map.new(&{&1["n"], "EN " <> &1["source"]}) |> Jason.encode!()
    end)
  end

  defp sent_sources do
    assert_receive {:prompt, prompt}, 2_000
    prompt |> items() |> Enum.map(& &1["source"]) |> Enum.sort()
  end

  defp change_main(view, fun) do
    params = view |> render() |> form_params("#article_form_form") |> fun.()
    view |> element("#article_form_form") |> render_change(params)
  end

  defp edit_title(view, title) do
    change_main(view, fn params ->
      params |> put_in(["article", "title"], title) |> Map.put("_target", ["article", "title"])
    end)
  end

  defp tick_reviewed(view, key) do
    change_main(view, fn params ->
      params
      |> put_in(["translation_review", "acknowledged"], [key])
      |> Map.put("_target", ["translation_review", "acknowledged"])
    end)
  end

  defp edit_block_text(view, uid, text) do
    selector = "#entry_block_form-#{uid}"
    params = view |> render() |> form_params(selector) |> put_in(@text, text) |> Map.put("_target", @text)
    view |> element(selector) |> render_change(params)
  end

  defp save(view) do
    view |> form("#article_form_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form("#article_form_form") |> render_submit()
    assert_redirect(view, 3_000)
  end

  describe "with AI configured" do
    setup %{current_user: user} = c do
      Brando.AIStub.configure()
      source = source(c, "Tittel", "Første avsnitt")
      {:ok, target} = Translations.create_target(Article, source.id, :en, user)
      %{source: source, target: target}
    end

    test "fills every open text as unsaved changes, and the save resolves them", %{conn: conn, target: target} do
      answer(&("EN " <> &1["source"]))
      view = open(conn, target.id)
      uid = block_uid(target.id)
      key = block_key(target.id)

      translate_all(view)
      render_async(view, 5_000)
      await(fn -> block_text(view, uid) == "EN Første avsnitt" end)

      assert title(view) == "EN Tittel"
      assert has_element?(view, "#{item("title")}[data-ai='filled']")
      assert has_element?(view, "#{item(key)}[data-ai='filled']")

      # Nothing is saved, and the work stays open
      assert load(target.id).title == "Tittel"
      assert Enum.sort(open_items(target.id)) == Enum.sort(["title", key])

      save(view)

      saved = load(target.id)
      assert saved.title == "EN Tittel"

      assert hd(saved.entry_blocks).block.refs |> hd() |> Map.get(:data) |> Map.get(:data) |> Map.get(:text) ==
               "EN Første avsnitt"

      assert open_items(target.id) == []
    end

    test "an item's own action fills only that item", %{conn: conn, target: target} do
      answer(&("EN " <> &1["source"]))
      view = open(conn, target.id)
      uid = block_uid(target.id)

      translate_one(view, "title")
      render_async(view, 5_000)
      await(fn -> title(view) == "EN Tittel" end)

      assert block_text(view, uid) == "Første avsnitt"
      assert has_element?(view, "#{item("title")}[data-ai='filled']")
      refute has_element?(view, "#{item(block_key(target.id))}[data-ai]")
    end

    test "a text the reply lost markup in is not filled, and says why", %{conn: conn} = c do
      source = source(c, "Kilde", ~s(<p>Første <a href="https://example.com/">avsnitt</a></p>))
      {:ok, target} = Translations.create_target(Article, source.id, :en, c.current_user)

      answer(fn
        %{"format" => "html"} -> "First paragraph"
        item -> "EN " <> item["source"]
      end)

      view = open(conn, target.id)
      uid = block_uid(target.id)
      key = block_key(target.id)

      translate_all(view)
      render_async(view, 5_000)
      await(fn -> title(view) == "EN Kilde" end)

      assert has_element?(view, "#{item(key)}[data-ai='skipped'] [data-ai-reason]")
      assert block_text(view, uid) =~ "Første"
    end

    test "an AI error changes nothing and tells the editor", %{conn: conn, target: target} do
      Brando.AIStub.reply(fn _prompt -> {:error, 500} end)
      view = open(conn, target.id)

      translate_all(view)
      render_async(view, 5_000)

      assert has_element?(view, "#translation-panel [data-ai-status='failed'][role='alert']")
      assert title(view) == "Tittel"
      refute has_element?(view, "#translation-panel [data-ai='filled']")
    end

    test "a result for a pending version the source has since replaced is dropped", %{conn: conn} = c do
      answer_when_told(&("EN " <> &1["source"]))
      view = open(conn, c.target.id)

      translate_all(view)
      assert_receive {:ai_waiting, model}, 2_000

      # The source changes while the model works: the translation gets a new
      # pending version.
      {:ok, _} = SyncTest.update_article(c.source.id, %{year: 2024}, c.current_user)
      send(model, :answer)
      render_async(view, 5_000)

      assert has_element?(view, "#translation-panel [data-ai-status='dropped']")
      assert title(view) == "Tittel"
    end

    test "a text the editor changed during the run keeps the editor's text", %{conn: conn, target: target} do
      answer_when_told(&("EN " <> &1["source"]))
      view = open(conn, target.id)
      uid = block_uid(target.id)

      translate_all(view)
      assert_receive {:ai_waiting, model}, 2_000

      params =
        view
        |> render()
        |> form_params("#article_form_form")
        |> put_in(["article", "title"], "My title")
        |> Map.put("_target", ["article", "title"])

      view |> element("#article_form_form") |> render_change(params)

      send(model, :answer)
      render_async(view, 5_000)
      await(fn -> block_text(view, uid) == "EN Første avsnitt" end)

      assert title(view) == "My title"
      assert has_element?(view, "#{item("title")}[data-ai='kept']")
    end

    test "a keystroke sent before the filled texts reached the browser does not take them back",
         %{conn: conn, target: target} do
      answer_when_told(&("EN " <> &1["source"]))
      view = open(conn, target.id)

      translate_one(view, "title")
      assert_receive {:ai_waiting, model}, 2_000

      # The browser's form as it is before the fill, with a keystroke in
      # another field: it reaches the server after the fill.
      before = view |> render() |> form_params("#article_form_form")

      send(model, :answer)
      render_async(view, 5_000)
      await(fn -> title(view) == "EN Tittel" end)

      params = before |> put_in(["article", "subtitle"], "Typed") |> Map.put("_target", ["article", "subtitle"])
      view |> element("#article_form_form") |> render_change(params)

      assert title(view) == "EN Tittel"
      assert has_element?(view, "#{item("title")}[data-ai='filled']")
    end

    test "filling a block the editor is in keeps the widget with the focus", %{conn: conn, target: target} do
      answer(&("EN " <> &1["source"]))
      view = open(conn, target.id)
      uid = block_uid(target.id)

      render_hook(view, "block_focused", %{"uid" => uid, "field" => "f", "label" => "L"})
      translate_one(view, block_key(target.id))
      render_async(view, 5_000)
      await(fn -> block_text(view, uid) == "EN Første avsnitt" end)

      assert_push_event(view, "b:component:remount_block", %{uid: ^uid} = filled)
      assert filled[:skip_focused] == true

      # Leaving the field shows the block once more, the field's input too
      render_hook(view, "block_focused", %{"uid" => "elsewhere", "field" => "g", "label" => "L"})
      assert_push_event(view, "b:component:remount_block", %{uid: ^uid} = left)
      refute Map.has_key?(left, :skip_focused)
    end

    test "the marks go when the form takes a newer pending version", %{conn: conn} = c do
      answer(&("EN " <> &1["source"]))
      view = open(conn, c.target.id)

      translate_one(view, "title")
      render_async(view, 5_000)
      await(fn -> title(view) == "EN Tittel" end)
      assert has_element?(view, "#{item("title")}[data-ai='filled']")
      assert has_element?(view, "#translation-panel [data-ai-status='done']")

      # The source changes, and the LiveView renders the form again: it
      # takes the translation's new pending version.
      {:ok, _} = SyncTest.update_article(c.source.id, %{year: 2024}, c.current_user)
      newer = Translations.get_pending_version(Article, c.target.id).id
      Phoenix.LiveView.send_update(view.pid, BrandoAdmin.Components.Form, id: "article_form")
      await_selector(view, "input[name='translation_review[version_id]'][value='#{newer}']")

      refute has_element?(view, "#translation-panel [data-ai]")
      refute has_element?(view, "#translation-panel [data-ai-status]")
    end

    test "a field locked for this editor, and blocks the form has no field for, are not sent", %{conn: conn} = c do
      {:ok, source} =
        SyncTest.create_article(
          %{title: "Tittel", subtitle: "Undertittel", slug: "tittel", language: "no", status: "published", year: 2020},
          c.current_user
        )

      TranslationFixtures.add_block(source, c.module, c.current_user, "Første avsnitt", 0)
      {:ok, target} = Translations.create_target(Article, source.id, :en, c.current_user)
      answer_and_report()

      # The `:locked` form: `subtitle` is read-only, and it has no block field
      {view, _html} = live_form(conn, "/admin/articles/update/#{target.id}/locked", "article_form")
      version = Translations.get_pending_version(Article, target.id)
      await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")

      translate_all(view)
      render_async(view, 5_000)

      assert sent_sources() == ["Tittel"]
      await(fn -> has_element?(view, "#{item("title")}[data-ai='filled']") end)
      refute has_element?(view, "#{item("subtitle")}[data-ai]")
      refute has_element?(view, "#{item(block_key(target.id))}[data-ai]")
    end

    test "a review item sends the source's text and the translation's", %{conn: conn, current_user: user} = c do
      source = source(c, "Gammel", "Gammel tekst")
      {:ok, target} = Translations.create_target(Article, source.id, :en, user, mark_translate: false)
      {:ok, _} = SyncTest.update_article(target.id, %{title: "Old"}, user)
      {:ok, _} = SyncTest.update_article(source.id, %{title: "Ny"}, user)

      test = self()

      Brando.AIStub.reply(fn prompt ->
        send(test, {:prompt, prompt})
        prompt |> items() |> Map.new(&{&1["n"], "New"}) |> Jason.encode!()
      end)

      view = open(conn, target.id)
      assert has_element?(view, "#{item("title")}")

      translate_one(view, "title")
      render_async(view, 5_000)

      assert_received {:prompt, prompt}
      assert [%{"source" => "Ny", "translation" => "Old"}] = items(prompt)
      await(fn -> title(view) == "New" end)
    end

    test "translating every text leaves out what the editor changed or ticked Reviewed", %{conn: conn} = c do
      {:ok, source} =
        SyncTest.create_article(
          %{title: "Tittel", subtitle: "Undertittel", slug: "tittel", language: "no", status: "published", year: 2020},
          c.current_user
        )

      TranslationFixtures.add_block(source, c.module, c.current_user, "Første avsnitt", 0)
      {:ok, target} = Translations.create_target(Article, source.id, :en, c.current_user)
      answer_and_report()

      view = open(conn, target.id)
      uid = block_uid(target.id)
      key = block_key(target.id)

      edit_title(view, "My title")
      tick_reviewed(view, key)
      translate_all(view)
      render_async(view, 5_000)

      assert sent_sources() == ["Undertittel"]
      await(fn -> render(view) =~ "EN Undertittel" end)
      assert title(view) == "My title"
      assert block_text(view, uid) == "Første avsnitt"
      refute has_element?(view, "#{item("title")}[data-ai]")
      refute has_element?(view, "#{item(key)}[data-ai]")

      # An item's own action translates it, on the editor's word
      translate_one(view, "title")
      render_async(view, 5_000)

      assert sent_sources() == ["Tittel"]
      await(fn -> title(view) == "EN Tittel" end)
    end

    test "a second run leaves out the texts the first filled and the editor corrected", %{conn: conn, target: target} do
      answer_and_report()
      view = open(conn, target.id)
      uid = block_uid(target.id)

      translate_one(view, "title")
      render_async(view, 5_000)
      assert sent_sources() == ["Tittel"]
      await(fn -> title(view) == "EN Tittel" end)

      edit_title(view, "The title")
      translate_all(view)
      render_async(view, 5_000)

      assert sent_sources() == ["Første avsnitt"]
      await(fn -> block_text(view, uid) == "EN Første avsnitt" end)
      assert title(view) == "The title"
    end

    test "a review sends the translation as the form has it, a field's and a block's",
         %{conn: conn, current_user: user} = c do
      source = source(c, "Gammel", "Gammel tekst")
      {:ok, target} = Translations.create_target(Article, source.id, :en, user, mark_translate: false)
      {:ok, _} = SyncTest.update_article(target.id, %{title: "Old"}, user)
      set_body(target.id, "Old text")
      {:ok, _} = SyncTest.update_article(source.id, %{title: "Ny"}, user)
      set_body(source.id, "Ny tekst")
      Translations.source_saved(load(source.id))

      test = self()

      Brando.AIStub.reply(fn prompt ->
        send(test, {:prompt, prompt})
        prompt |> items() |> Map.new(&{&1["n"], "New"}) |> Jason.encode!()
      end)

      view = open(conn, target.id)
      key = block_key(target.id)
      assert has_element?(view, item(key))

      edit_title(view, "Old, edited")
      edit_block_text(view, block_uid(target.id), "Old text, edited")
      translate_one(view, "title")
      render_async(view, 5_000)
      assert_receive {:prompt, prompt}, 2_000
      assert [%{"source" => "Ny", "translation" => "Old, edited"}] = items(prompt)

      translate_one(view, key)
      render_async(view, 5_000)
      assert_receive {:prompt, prompt}, 2_000
      assert [%{"source" => "Ny tekst", "translation" => "Old text, edited"}] = items(prompt)
    end

    test "a second editor in the entry sees the filled texts", %{conn: conn, target: target} do
      answer(&("EN " <> &1["source"]))
      other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      other_conn = log_in_user(Phoenix.ConnTest.build_conn(), other)

      view = open(conn, target.id)
      other_view = open(other_conn, target.id)
      uid = block_uid(target.id)

      translate_all(view)
      render_async(view, 5_000)

      await(fn -> title(other_view) == "EN Tittel" end)
      await(fn -> block_text(other_view, uid) == "EN Første avsnitt" end)
    end

    test "a link with translate=ai starts nothing for a legacy account that may not write",
         %{target: target} do
      answer_and_report()
      reader = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
      view = open(log_in_user(build_conn(), reader), target.id, "?translate=ai")

      refute_receive {:prompt, _}, 500
      refute has_element?(view, "#translation-panel [data-ai-status]")
      assert title(view) == "Tittel"
    end

    # With groups, a member who may only read cannot open the form; one who
    # may update gets the run.
    test "a link with translate=ai starts a run for a group member who may update",
         %{current_user: user, target: target} do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Brando.Authorization.Migration.run()
      alias Brando.Authorization.{Catalog, Groups, Scope}
      editor = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
      scope = Scope.standalone(user)

      {:ok, group} =
        Groups.create(scope, %{name: "Article editors"}, [
          Catalog.get(:access, :backend).key,
          Catalog.get(:read, Article).key,
          Catalog.get(:update, Article).key
        ])

      {:ok, :ok} = Groups.add_member(scope, group.id, editor.id)
      answer_and_report()
      view = open(log_in_user(build_conn(), editor), target.id, "?translate=ai")

      assert sent_sources() == ["Første avsnitt", "Tittel"]
      await(fn -> render_async(view, 1_000) && title(view) == "EN Tittel" end)
    end

    test "the listing creates the translation and starts translating in its form",
         %{conn: conn, current_user: user} = c do
      answer(&("EN " <> &1["source"]))
      # The listing shows the content language, English
      source = source(c, "Alone", "Text", "en")
      {:ok, view, _html} = live(conn, "/admin/articles")
      await_selector(view, "[id$='_create_and_translate_#{source.id}_lang_no']")

      view |> element("[id$='_create_and_translate_#{source.id}_lang_no']") |> render_click()

      assert %{group_id: group_id} = Translations.get_member(Article, source.id)
      assert [%{entry_id: target_id}] = group_id |> Translations.list_members() |> Enum.filter(&(&1.language == "no"))
      assert_redirect(view, "/admin/articles/update/#{target_id}?translate=ai")

      form = open(conn, target_id, "?translate=ai")
      await(fn -> render_async(form, 1_000) && title(form) == "EN Alone" end)
      assert has_element?(form, "#{item("title")}[data-ai='filled']")
      assert load(target_id).title == "Alone"
      _ = user
    end
  end

  describe "without AI configured" do
    test "offers no AI actions", %{conn: conn, current_user: user} = c do
      source = source(c, "Tittel", "Første avsnitt")
      {:ok, target} = Translations.create_target(Article, source.id, :en, user)
      view = open(conn, target.id)

      assert has_element?(view, item("title"))
      refute has_element?(view, "[data-testid^=translation-ai]")

      alone = source(c, "Alone", "Text", "en")
      {:ok, listing, _html} = live(conn, "/admin/articles")
      await_selector(listing, "[id$='_create_translation_#{alone.id}_lang_no']")
      refute has_element?(listing, "[id*='_create_and_translate_']")
    end
  end
end
