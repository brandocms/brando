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
  @child_text ["child_block", "refs", "0", "data", "data", "text"]

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

  # How many times `pid` calls `mfa` while `fun` runs
  defp count_calls(pid, {module, name, _arity} = mfa, fun) do
    :erlang.trace_pattern(mfa, true, [:local])
    :erlang.trace(pid, true, [:call])

    try do
      fun.()
      :erlang.trace(pid, false, [:call])
      count_traced(pid, module, name, 0)
    after
      :erlang.trace_pattern(mfa, false, [:local])
    end
  end

  defp count_traced(pid, module, name, count) do
    receive do
      {:trace, ^pid, :call, {^module, ^name, _args}} -> count_traced(pid, module, name, count + 1)
    after
      100 -> count
    end
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

    test "the line saying the source changed stays when the form is drawn again", %{conn: conn} = c do
      answer_when_told(&("EN " <> &1["source"]))
      view = open(conn, c.target.id)

      translate_all(view)
      assert_receive {:ai_waiting, model}, 2_000
      {:ok, _} = SyncTest.update_article(c.source.id, %{year: 2024}, c.current_user)
      send(model, :answer)
      render_async(view, 5_000)
      assert has_element?(view, "#translation-panel [data-ai-status='dropped']")

      # The LiveView renders the form again (another editor joins, say): it
      # takes the translation's new pending version
      newer = Translations.get_pending_version(Article, c.target.id).id
      Phoenix.LiveView.send_update(view.pid, BrandoAdmin.Components.Form, id: "article_form")
      await_selector(view, "input[name='translation_review[version_id]'][value='#{newer}']")

      assert has_element?(view, "#translation-panel [data-ai-status='dropped']")
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

      # Nor do their items offer the AI action
      assert has_element?(view, "#{item("title")} [data-testid=translation-ai-item]")
      refute has_element?(view, "#{item("subtitle")} [data-testid=translation-ai-item]")
      refute has_element?(view, "#{item(block_key(target.id))} [data-testid=translation-ai-item]")
    end

    test "a text the form has no input for, or hides, is not sent and has no AI action",
         %{conn: conn, current_user: user} do
      {:ok, source} =
        SyncTest.create_article(
          %{
            title: "Tittel",
            subtitle: "Undertittel",
            slug: "tittel",
            language: "no",
            status: "published",
            items: [%{label: "Første punkt"}]
          },
          user
        )

      {:ok, target} = Translations.create_target(Article, source.id, :en, user)
      key = "items/#{hd(load(target.id).items).uid}/label"
      answer_and_report()

      # The `:partial` form: the subtitle shows only for a featured article,
      # and the items' rows have no label
      {view, _html} = live_form(conn, "/admin/articles/update/#{target.id}/partial", "article_form")
      version = Translations.get_pending_version(Article, target.id)
      await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")
      assert has_element?(view, item("subtitle"))
      assert has_element?(view, item(key))

      assert has_element?(view, "#{item("title")} [data-testid=translation-ai-item]")
      refute has_element?(view, "#{item("subtitle")} [data-testid=translation-ai-item]")
      refute has_element?(view, "#{item(key)} [data-testid=translation-ai-item]")

      translate_all(view)
      render_async(view, 5_000)

      assert sent_sources() == ["Tittel"]
      await(fn -> has_element?(view, "#{item("title")}[data-ai='filled']") end)
      refute has_element?(view, "#{item("subtitle")}[data-ai]")
      refute has_element?(view, "#{item(key)}[data-ai]")
    end

    test "a subform in a fieldset only superusers may change is not sent to anyone else",
         %{conn: conn, current_user: user} do
      {:ok, source} =
        SyncTest.create_article(
          %{title: "Tittel", slug: "tittel", language: "no", status: "published", items: [%{label: "Første punkt"}]},
          user
        )

      {:ok, target} = Translations.create_target(Article, source.id, :en, user)
      key = "items/#{hd(load(target.id).items).uid}/label"
      answer_and_report()

      admin = Factory.insert(:random_user, role: :admin, config: %Brando.Users.UserConfig{})
      admin_conn = log_in_user(build_conn(), admin)
      {view, _html} = live_form(admin_conn, "/admin/articles/update/#{target.id}/superuser_items", "article_form")
      version = Translations.get_pending_version(Article, target.id)
      await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")

      translate_all(view)
      render_async(view, 5_000)

      assert sent_sources() == ["Tittel"]
      await(fn -> has_element?(view, "#{item("title")}[data-ai='filled']") end)
      refute has_element?(view, "#{item(key)}[data-ai]")
      _ = conn
    end

    # A row's editor cannot yet be given a text from the server (#3757)
    test "a rich text in a subform's row is not sent and has no AI action", %{conn: conn, current_user: user} do
      {:ok, source} =
        SyncTest.create_article(
          %{title: "Tittel", slug: "tittel", language: "no", status: "published", quotes: [%{text: "<p>Sitatet</p>"}]},
          user
        )

      {:ok, target} = Translations.create_target(Article, source.id, :en, user)
      key = "quotes/#{hd(load(target.id).quotes).uid}/text"
      answer_and_report()

      {view, _html} = live_form(conn, "/admin/articles/update/#{target.id}/rich_quotes", "article_form")
      version = Translations.get_pending_version(Article, target.id)
      await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")
      assert has_element?(view, item(key))
      assert has_element?(view, "#{item("title")} [data-testid=translation-ai-item]")
      refute has_element?(view, "#{item(key)} [data-testid=translation-ai-item]")

      translate_all(view)
      render_async(view, 5_000)

      assert sent_sources() == ["Tittel"]
      await(fn -> has_element?(view, "#{item("title")}[data-ai='filled']") end)
      refute has_element?(view, "#{item(key)}[data-ai]")
    end

    test "a run reads a block with many texts once per pass, not once per text", %{conn: conn, current_user: user} do
      names = ~w(one two three four five six)

      ref = fn name, text ->
        %{name: name, uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: text}}}
      end

      {:ok, module} =
        Brando.Content.create_module(
          Factory.params_for(:module,
            name: %{"en" => "Texts"},
            namespace: %{"en" => "Content"},
            help_text: %{},
            code: Enum.map_join(names, &"{% ref refs.#{&1} %}"),
            refs: Enum.map(names, &ref.(&1, "Default"))
          ),
          user
        )

      {:ok, source} =
        SyncTest.create_article(%{title: "Mange", slug: "mange", language: "no", status: "published"}, user)

      block =
        %Brando.Content.Block{}
        |> Brando.Content.Block.recursive_block_changeset(
          %{
            "uid" => Brando.Utils.generate_uid(),
            "type" => "module",
            "module_id" => module.id,
            "creator_id" => user.id,
            "source" => to_string(Article.Blocks),
            "refs" =>
              Enum.map(names, fn name ->
                %{
                  "uid" => Brando.Utils.generate_uid(),
                  "name" => name,
                  "data" => %{"type" => "text", "data" => %{"text" => "Tekst #{name}"}}
                }
              end)
          },
          user
        )
        |> Repo.insert!()

      struct(Article.Blocks, %{entry_id: source.id, block_id: block.id, sequence: 0}) |> Repo.insert!()
      {:ok, target} = Translations.create_target(Article, source.id, :en, user)
      answer(&("EN " <> &1["source"]))
      view = open(conn, target.id)
      uid = block_uid(target.id)

      count =
        count_calls(view.pid, {BrandoAdmin.Components.Form.BlockField.Ops, :materialize_root, 2}, fn ->
          translate_all(view)
          render_async(view, 5_000)

          await(fn ->
            view
            |> render()
            |> form_params("#entry_block_form-#{uid}")
            |> get_in(["entry_block", "block", "refs", "5", "data", "data", "text"]) ==
              "EN Tekst six"
          end)
        end)

      # Read when the run starts, read and filled when the reply comes, and
      # shown from the store
      assert count <= 3, "the root was materialized #{count} times"
    end

    test "a block text changed during the run keeps the editor's text", %{conn: conn, target: target} do
      answer_when_told(&("EN " <> &1["source"]))
      view = open(conn, target.id)
      uid = block_uid(target.id)
      key = block_key(target.id)

      translate_all(view)
      assert_receive {:ai_waiting, model}, 2_000
      edit_block_text(view, uid, "My paragraph")

      send(model, :answer)
      render_async(view, 5_000)
      await(fn -> title(view) == "EN Tittel" end)
      await(fn -> has_element?(view, "#{item(key)}[data-ai='kept']") end)

      assert block_text(view, uid) == "My paragraph"
    end

    test "a child block's text changed during the run keeps the editor's text",
         %{conn: conn, current_user: user, module: module} do
      {:ok, source} =
        SyncTest.create_article(%{title: "Tittel", slug: "tittel", language: "no", status: "published"}, user)

      child = fn text, sequence ->
        %{
          "uid" => Brando.Utils.generate_uid(),
          "type" => "module",
          "module_id" => module.id,
          "creator_id" => user.id,
          "sequence" => sequence,
          "source" => to_string(Article.Blocks),
          "refs" => [
            %{
              "uid" => Brando.Utils.generate_uid(),
              "name" => "body",
              "data" => %{"type" => "text", "data" => %{"text" => text}}
            }
          ]
        }
      end

      container =
        %Brando.Content.Block{}
        |> Brando.Content.Block.recursive_block_changeset(
          %{
            "uid" => Brando.Utils.generate_uid(),
            "type" => "container",
            "creator_id" => user.id,
            "source" => to_string(Article.Blocks),
            "children" => [child.("Første", 0), child.("Andre", 1)]
          },
          user
        )
        |> Repo.insert!()

      struct(Article.Blocks, %{entry_id: source.id, block_id: container.id, sequence: 0}) |> Repo.insert!()
      {:ok, target} = Translations.create_target(Article, source.id, :en, user)

      [first, second] = hd(load(target.id).entry_blocks).block.children |> Enum.sort_by(& &1.sequence)
      key = fn block -> "entry_blocks/#{block.sync_uid}/refs/body/text" end

      child_text = fn view, block ->
        view |> render() |> form_params("#child_block_form-#{block.uid}") |> get_in(@child_text)
      end

      answer_when_told(&("EN " <> &1["source"]))
      view = open(conn, target.id)

      translate_all(view)
      assert_receive {:ai_waiting, model}, 2_000

      selector = "#child_block_form-#{first.uid}"

      params =
        view |> render() |> form_params(selector) |> put_in(@child_text, "My first") |> Map.put("_target", @child_text)

      view |> element(selector) |> render_change(params)

      send(model, :answer)
      render_async(view, 5_000)
      await(fn -> child_text.(view, second) == "EN Andre" end)
      await(fn -> has_element?(view, "#{item(key.(first))}[data-ai='kept']") end)

      assert child_text.(view, first) == "My first"
    end

    test "a subform row's text changed during the run keeps the editor's text", %{conn: conn, current_user: user} do
      {:ok, source} =
        SyncTest.create_article(
          %{title: "Tittel", slug: "tittel", language: "no", status: "published", items: [%{label: "Første punkt"}]},
          user
        )

      {:ok, target} = Translations.create_target(Article, source.id, :en, user)
      key = "items/#{hd(load(target.id).items).uid}/label"

      label = fn view ->
        view |> render() |> form_params("#article_form_form") |> get_in(["article", "items", "0", "label"])
      end

      answer_when_told(&("EN " <> &1["source"]))
      {view, _html} = live_form(conn, "/admin/articles/update/#{target.id}", "article_form")
      version = Translations.get_pending_version(Article, target.id)
      await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")
      assert has_element?(view, item(key))

      translate_all(view)
      assert_receive {:ai_waiting, model}, 2_000

      change_main(view, fn params ->
        params
        |> put_in(["article", "items", "0", "label"], "My point")
        |> Map.put("_target", ["article", "items", "0", "label"])
      end)

      send(model, :answer)
      render_async(view, 5_000)
      await(fn -> title(view) == "EN Tittel" end)
      await(fn -> has_element?(view, "#{item(key)}[data-ai='kept']") end)

      assert label.(view) == "My point"
    end

    test "a keystroke sent before a filled subform row reached the browser does not take it back",
         %{conn: conn, current_user: user} do
      {:ok, source} =
        SyncTest.create_article(
          %{title: "Tittel", slug: "tittel", language: "no", status: "published", items: [%{label: "Første punkt"}]},
          user
        )

      {:ok, target} = Translations.create_target(Article, source.id, :en, user)
      key = "items/#{hd(load(target.id).items).uid}/label"

      label = fn view ->
        view |> render() |> form_params("#article_form_form") |> get_in(["article", "items", "0", "label"])
      end

      answer_when_told(&("EN " <> &1["source"]))
      {view, _html} = live_form(conn, "/admin/articles/update/#{target.id}", "article_form")
      version = Translations.get_pending_version(Article, target.id)
      await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")

      translate_one(view, key)
      assert_receive {:ai_waiting, model}, 2_000

      # The browser's form before the fill, with a keystroke in the title:
      # it reaches the server after the fill.
      before = view |> render() |> form_params("#article_form_form")

      send(model, :answer)
      render_async(view, 5_000)
      await(fn -> label.(view) == "EN Første punkt" end)

      params = before |> put_in(["article", "title"], "Typed") |> Map.put("_target", ["article", "title"])
      view |> element("#article_form_form") |> render_change(params)

      assert label.(view) == "EN Første punkt"
      assert title(view) == "Typed"
      assert has_element?(view, "#{item(key)}[data-ai='filled']")
    end

    test "a keystroke in another row of an embeds_many subform sent before the fill reached the browser does not take it back",
         %{conn: conn, current_user: user} do
      {:ok, source} =
        SyncTest.create_article(
          %{
            title: "Tittel",
            slug: "tittel",
            language: "no",
            status: "published",
            quotes: [%{text: "Første sitat"}, %{text: "Andre sitat"}]
          },
          user
        )

      {:ok, target} = Translations.create_target(Article, source.id, :en, user)
      key = "quotes/#{hd(load(target.id).quotes).uid}/text"

      quote_text = fn view, index ->
        view |> render() |> form_params("#article_form_form") |> get_in(["article", "quotes", index, "text"])
      end

      answer_when_told(&("EN " <> &1["source"]))
      {view, _html} = live_form(conn, "/admin/articles/update/#{target.id}", "article_form")
      version = Translations.get_pending_version(Article, target.id)
      await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")

      translate_one(view, key)
      assert_receive {:ai_waiting, model}, 2_000

      # The browser's form before the fill, with a keystroke in the other
      # quote: it reaches the server after the fill.
      before = view |> render() |> form_params("#article_form_form")

      send(model, :answer)
      render_async(view, 5_000)
      await(fn -> quote_text.(view, "0") == "EN Første sitat" end)

      params =
        before
        |> put_in(["article", "quotes", "1", "text"], "Typed")
        |> Map.put("_target", ["article", "quotes", "1", "text"])

      view |> element("#article_form_form") |> render_change(params)

      assert quote_text.(view, "0") == "EN Første sitat"
      assert has_element?(view, "#{item(key)}[data-ai='filled']")

      # The form the browser redraws keeps the text in the input with the
      # focus, and sends it again with the next keystroke
      params =
        view
        |> render()
        |> form_params("#article_form_form")
        |> put_in(["article", "quotes", "1", "text"], "Typed!")
        |> Map.put("_target", ["article", "quotes", "1", "text"])

      view |> element("#article_form_form") |> render_change(params)

      assert quote_text.(view, "0") == "EN Første sitat"
      assert quote_text.(view, "1") == "Typed!"
    end

    test "a second editor's change during the run is kept", %{conn: conn, target: target} do
      answer_when_told(&("EN " <> &1["source"]))
      other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      other_conn = log_in_user(Phoenix.ConnTest.build_conn(), other)

      view = open(conn, target.id)
      other_view = open(other_conn, target.id)
      uid = block_uid(target.id)
      key = block_key(target.id)

      translate_all(view)
      assert_receive {:ai_waiting, model}, 2_000

      # The other editor changes the title and the block's text
      other_form = with_target(other_view, cid_of(other_view, "#article_form-el"))
      render_hook(other_form, "focus", %{"field" => "article[title]"})
      edit_title(other_view, "Their title")
      render_hook(other_form, "blur", %{"field" => "article[title]"})
      edit_block_text(other_view, uid, "Their paragraph")

      await(fn -> title(view) == "Their title" end)
      await(fn -> block_text(view, uid) == "Their paragraph" end)

      send(model, :answer)
      render_async(view, 5_000)
      await(fn -> has_element?(view, "#{item("title")}[data-ai='kept']") end)
      await(fn -> has_element?(view, "#{item(key)}[data-ai='kept']") end)

      assert title(view) == "Their title"
      assert block_text(view, uid) == "Their paragraph"
    end

    test "a second editor's change to the field this editor is in during the run is kept",
         %{conn: conn, target: target} do
      answer_when_told(&("EN " <> &1["source"]))
      other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      other_conn = log_in_user(Phoenix.ConnTest.build_conn(), other)

      view = open(conn, target.id)
      other_view = open(other_conn, target.id)
      form = with_target(view, cid_of(view, "#article_form-el"))

      # This editor is in the title: another editor's change to it is held
      # until they leave it
      render_hook(form, "focus", %{"field" => "article[title]"})
      translate_one(view, "title")
      assert_receive {:ai_waiting, model}, 2_000

      other_form = with_target(other_view, cid_of(other_view, "#article_form-el"))
      render_hook(other_form, "focus", %{"field" => "article[title]"})
      edit_title(other_view, "Their title")
      render_hook(other_form, "blur", %{"field" => "article[title]"})

      send(model, :answer)
      render_async(view, 5_000)
      await(fn -> has_element?(view, "#{item("title")}[data-ai='kept']") end)

      render_hook(form, "blur", %{"field" => "article[title]"})

      await(fn -> title(view) == "Their title" end)
      assert title(other_view) == "Their title"
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

    test "translating every text sends a text with Windows line endings the browser sent back", %{conn: conn} = c do
      {:ok, source} =
        SyncTest.create_article(
          %{
            title: "Tittel",
            subtitle: "Linje en\r\nLinje to",
            slug: "tittel",
            language: "no",
            status: "published"
          },
          c.current_user
        )

      {:ok, target} = Translations.create_target(Article, source.id, :en, c.current_user)
      answer_and_report()
      {view, _html} = live_form(conn, "/admin/articles/update/#{target.id}", "article_form")
      version = Translations.get_pending_version(Article, target.id)
      await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")

      # A browser sends a textarea's line endings as \r\n, and the form
      # holds them as \n from the first `validate` on
      change_main(view, fn params ->
        params
        |> put_in(["article", "subtitle"], "Linje en\nLinje to")
        |> Map.put("_target", ["article", "featured"])
      end)

      translate_all(view)
      render_async(view, 5_000)

      assert sent_sources() == ["Linje en\r\nLinje to", "Tittel"]
    end

    test "a text with Windows line endings the browser sent back during the run is filled", %{conn: conn} = c do
      {:ok, source} =
        SyncTest.create_article(
          %{title: "Tittel", subtitle: "Linje en\r\nLinje to", slug: "tittel", language: "no", status: "published"},
          c.current_user
        )

      {:ok, target} = Translations.create_target(Article, source.id, :en, c.current_user)
      answer_when_told(&("EN " <> &1["source"]))
      {view, _html} = live_form(conn, "/admin/articles/update/#{target.id}", "article_form")
      version = Translations.get_pending_version(Article, target.id)
      await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")

      # The run starts before any `validate`, with the stored \r\n text
      translate_one(view, "subtitle")
      assert_receive {:ai_waiting, model}, 2_000

      # The editor types in another field; the browser sends the textarea's
      # text back with \n
      change_main(view, fn params ->
        params
        |> put_in(["article", "subtitle"], "Linje en\nLinje to")
        |> put_in(["article", "featured"], "true")
        |> Map.put("_target", ["article", "featured"])
      end)

      send(model, :answer)
      render_async(view, 5_000)

      await(fn -> has_element?(view, "#{item("subtitle")}[data-ai='filled']") end)
      refute has_element?(view, "#{item("subtitle")}[data-ai='kept']")
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

  describe "a synchronized page" do
    # Pages are made synchronized by configuration; every text unit the work
    # gives is sent, or has a reason not to be. A change to what the form can
    # fill that drops a kind of text fails here.
    setup %{current_user: user} do
      Brando.AIStub.configure()
      put_test_env(Brando.Pages.Page, translatable: [mode: :synchronized])

      page =
        Factory.insert(:page,
          title: "Om oss",
          uri: "om-oss-#{System.unique_integer([:positive])}",
          language: :no,
          creator: user,
          meta_title: "Om oss | Firma",
          meta_description: "Hvem vi er",
          vars: [
            Factory.build(:var_text, key: "intro", label: "Intro", value: "Velkommen", creator: user),
            %Brando.Content.Var{
              type: :link,
              key: "cta",
              label: "Lenke",
              link_type: :url,
              value: "/no/kontakt",
              link_text: "Kontakt oss",
              creator: user
            },
            %Brando.Content.Var{type: :rich_text, key: "body", label: "Tekst", value: "<p>Brødtekst</p>", creator: user}
          ]
        )

      {:ok, target} = Translations.create_target(Brando.Pages.Page, page.id, :en, user)
      %{target: target}
    end

    test "sends every text unit but an address or a variable's rich text, and gives each its AI action",
         %{conn: conn, target: target} do
      answer_and_report()
      {:ok, work} = Brando.Translations.Work.translation_units(Brando.Pages.Page, target.id)
      units = Enum.filter(work.units, &Brando.AI.WorkTranslation.translatable?/1)
      # A rich-text variable's editor cannot yet be given a text from the
      # server (#3757): the editor translates it
      {held, texts} = Enum.split_with(units, &(address?(&1) or &1.key == "vars/body/value"))

      # The page's own texts: the title, the meta title and description, and
      # the text and link variables
      keys = Enum.map(texts, & &1.key)
      assert Enum.all?(~w(title meta_title meta_description vars/intro/value vars/cta/link_text), &(&1 in keys))
      assert held |> Enum.map(& &1.key) |> Enum.sort() == ["vars/body/value", "vars/cta/url"]

      {view, _html} = live_form(conn, "/admin/pages/update/#{target.id}", "page_form")
      version = Translations.get_pending_version(Brando.Pages.Page, target.id)
      await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")

      for unit <- texts, do: assert(has_element?(view, "#{item(unit.key)} [data-testid=translation-ai-item]"))
      for unit <- held, do: refute(has_element?(view, "#{item(unit.key)} [data-testid=translation-ai-item]"))

      translate_all(view)
      render_async(view, 5_000)

      assert sent_sources() == texts |> Enum.map(& &1.source) |> Enum.sort()
      for unit <- texts, do: await(fn -> has_element?(view, "#{item(unit.key)}[data-ai='filled']") end)
    end

    # A link variable that allows no custom text draws no input for its
    # stored text: it is not sent, and has no AI action
    test "leaves out a link's text the variable draws no input for", %{conn: conn, current_user: user} do
      answer_and_report()

      page =
        Factory.insert(:page,
          title: "Kontakt",
          uri: "kontakt-#{System.unique_integer([:positive])}",
          language: :no,
          creator: user,
          vars: [
            %Brando.Content.Var{
              type: :link,
              key: "cta",
              label: "Lenke",
              link_type: :url,
              value: "/no/kontakt",
              link_text: "Kontakt oss",
              link_allow_custom_text: false,
              creator: user
            }
          ]
        )

      {:ok, target} = Translations.create_target(Brando.Pages.Page, page.id, :en, user)
      {view, _html} = live_form(conn, "/admin/pages/update/#{target.id}", "page_form")
      version = Translations.get_pending_version(Brando.Pages.Page, target.id)
      await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")

      assert has_element?(view, item("vars/cta/link_text"))
      refute has_element?(view, "#{item("vars/cta/link_text")} [data-testid=translation-ai-item]")

      translate_all(view)
      render_async(view, 5_000)

      sources = sent_sources()
      assert "Kontakt" in sources
      refute "Kontakt oss" in sources
      await(fn -> has_element?(view, "#{item("title")}[data-ai='filled']") end)
      refute has_element?(view, "#{item("vars/cta/link_text")}[data-ai='filled']")
    end

    defp address?(unit) do
      BrandoAdmin.Components.Form.TranslationFill.address?(
        Brando.Pages.Page,
        Brando.Translations.Labels.target(unit.key, %{})
      )
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
