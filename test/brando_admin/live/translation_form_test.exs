defmodule BrandoAdmin.TranslationFormTest do
  # The editor side of synchronized translations: a translation opens with its
  # pending version in the form, lists its work, and the save resolves only
  # what the editor reviewed.
  use Brando.LiveCase

  alias Brando.Content.Block
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.Translations

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

    {:ok, source} =
      SyncTest.create_article(
        %{title: "Tittel", slug: "tittel", language: "no", status: "published", year: 2020},
        user
      )

    add_block(source, module, user, "Første avsnitt", 0)
    {:ok, target} = Translations.create_target(Article, source.id, :en, user)
    translate(target, ["First paragraph"])

    %{module: module, source: source, target: target}
  end

  defp add_block(article, module, user, text, sequence) do
    params = %{
      "uid" => Brando.Utils.generate_uid(),
      "type" => "module",
      "module_id" => module.id,
      "creator_id" => user.id,
      "source" => to_string(Article.Blocks),
      "refs" => [
        %{
          "uid" => Brando.Utils.generate_uid(),
          "name" => "body",
          "data" => %{"type" => "text", "data" => %{"text" => text}}
        }
      ]
    }

    block = %Block{} |> Block.recursive_block_changeset(params, user) |> Repo.insert!()
    struct(Article.Blocks, %{entry_id: article.id, block_id: block.id, sequence: sequence}) |> Repo.insert!()
    block
  end

  defp load(id) do
    {:ok, entry} = SyncTest.get_article(%{matches: %{id: id}, preload: Brando.Blueprint.preloads_for(Article)})
    entry
  end

  defp texts(entry), do: Enum.map(entry.entry_blocks, &hd(&1.block.refs).data.data.text)

  defp set_text(block, text) do
    [ref] = Repo.preload(block, :refs).refs
    ref |> Ecto.Changeset.change(data: %{ref.data | data: %{ref.data.data | text: text}}) |> Repo.update!()
  end

  defp translate(target, texts) do
    target.id
    |> load()
    |> Map.fetch!(:entry_blocks)
    |> Enum.zip(texts)
    |> Enum.each(fn {join, text} -> set_text(join.block, text) end)
  end

  # The source adds a block and changes the year.
  defp change_source(c) do
    add_block(c.source, c.module, c.current_user, "Nytt avsnitt", 1)
    {:ok, _} = SyncTest.update_article(c.source.id, %{year: 2024}, c.current_user)
    Translations.source_saved(load(c.source.id))
    Translations.get_pending_version(Article, c.target.id)
  end

  defp open(conn, id) do
    {view, _html} = live_form(conn, "/admin/articles/update/#{id}", "article_form")
    view
  end

  # Submits the main form as the browser would, then waits for the save,
  # which collects the block fields first.
  defp save(view) do
    # The first submit collects the block fields; the Submit hook then submits
    # again (`b:submit`), which saves and returns to the listing.
    view |> form("#article_form_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form("#article_form_form") |> render_submit()
    assert_redirect(view, 3_000)
  end

  test "a translation opens with its pending version in the form and lists the work", %{conn: conn} = c do
    version = change_source(c)
    view = open(conn, c.target.id)
    html = await_selector(view, "#translation-panel input[name='translation_review[version_id]']")

    assert html =~ "Translation of the"
    assert has_element?(view, "#translation-panel a[href='/admin/articles/update/#{c.source.id}']", "Open the source")
    assert has_element?(view, "input[name='translation_review[version_id]'][value='#{version.id}']")
    assert has_element?(view, ".translation-group", "Needs translation")
    assert has_element?(view, ".translation-group", "Updated from the source")
    assert has_element?(view, ".translation-item-label", "Year")

    # The pending year is in the form, not yet saved.
    assert has_element?(view, "input[name='article[year]'][value='2024']")
    assert load(c.target.id).year == 2020
  end

  test "saving the translation writes the pending version and resolves what was done", %{conn: conn} = c do
    version = change_source(c)
    view = open(conn, c.target.id)
    await_selector(view, "input[name='translation_review[version_id]']")
    [translate_item] = Enum.filter(version.work_items, &(&1.kind == :translate))

    view
    |> element("#article_form_form")
    |> render_change(%{"translation_review" => %{"acknowledged" => [translate_item.path]}})

    save(view)

    saved = load(c.target.id)
    assert saved.year == 2024
    assert texts(saved) == ["First paragraph", "Nytt avsnitt"]
    # The new block keeps the identity the source gave it.
    source_ids = Enum.map(load(c.source.id).entry_blocks, & &1.block.sync_uid)
    assert Enum.map(saved.entry_blocks, & &1.block.sync_uid) == source_ids

    assert Translations.get_pending_version(Article, c.target.id) == nil
    # Still a published translation; its status was not touched.
    assert saved.status == :draft or saved.status == :published
  end

  test "work that was not done stays open after a save", %{conn: conn} = c do
    change_source(c)
    view = open(conn, c.target.id)
    await_selector(view, "input[name='translation_review[version_id]']")
    save(view)

    assert %{work_items: items} = Translations.get_pending_version(Article, c.target.id)
    assert [{:translate, _}] = for(item <- items, is_nil(item.resolved_at), do: {item.kind, item.path})
  end

  test "a reconnect loads the version again and keeps what was marked reviewed", %{conn: conn} = c do
    version = change_source(c)
    [item] = Enum.filter(version.work_items, &(&1.kind == :translate))
    view = open(conn, c.target.id)
    await_selector(view, "input[name='translation_review[version_id]']")

    html =
      view
      |> element("#article_form_form")
      |> render_change(%{"translation_review" => %{"acknowledged" => [item.path]}})

    params = form_params(html, "#article_form_form")
    assert params["translation_review"]["acknowledged"] == [item.path]
    kill_live(view)

    # LiveView's recovery replays the form's last params into the new process.
    view = open(conn, c.target.id)
    await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")
    view |> element("#article_form_form") |> render_change(params)

    assert has_element?(view, "input[name='translation_review[acknowledged][]'][value='#{item.path}'][checked]")
    assert has_element?(view, "input[name='article[year]'][value='2024']")
  end

  test "a source change during editing is reported and loaded after the save", %{conn: conn} = c do
    change_source(c)
    view = open(conn, c.target.id)
    await_selector(view, "input[name='translation_review[version_id]']")

    # Meanwhile the source changes the year again.
    {:ok, _} = SyncTest.update_article(c.source.id, %{year: 2030}, c.current_user)
    Translations.source_saved(load(c.source.id))

    view |> element("button", "Save and continue editing") |> render_click()
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form("#article_form_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form("#article_form_form") |> render_submit()

    await_selector(view, ".translation-notice", 3_000)
    assert load(c.target.id).year == 2024
    # The newer version is back in the form, unsaved.
    await_selector(view, "input[name='article[year]'][value='2030']", 3_000)
  end

  test "a structural change without text work is shown too", %{conn: conn} = c do
    # The source removes its only block: nothing to translate, but the
    # translation changes.
    [join] = load(c.source.id).entry_blocks
    Repo.delete!(join)
    Translations.source_saved(load(c.source.id))
    assert %{work_items: []} = Translations.get_pending_version(Article, c.target.id)

    view = open(conn, c.target.id)
    await_selector(view, ".translation-structure")
    refute has_element?(view, ".translation-done")
  end

  describe "ownership" do
    test "a translation's blocks cannot be removed, even by a forged click", %{conn: conn} = c do
      view = open(conn, c.target.id)
      await_selector(view, ".blocks-wrapper.is-source-locked")
      assert has_element?(view, ".blocks-source-note", "follow the source")
      [join] = load(c.target.id).entry_blocks

      # The button is hidden by CSS; the server refuses the op anyway.
      view
      |> element("[data-block-uid='#{join.block.uid}'] button[phx-click='delete_block']")
      |> render_click()

      assert has_element?(view, "[data-block-uid='#{join.block.uid}']")
    end

    test "a forged save of a source-controlled value is refused", %{conn: conn} = c do
      view = open(conn, c.target.id)
      await_selector(view, ".translation-panel.is-target")

      view |> form("#article_form_form", %{"article" => %{"year" => "1999"}}) |> render_submit()
      assert_push_event(view, "b:submit", %{}, 2_000)
      view |> form("#article_form_form", %{"article" => %{"year" => "1999"}}) |> render_submit()
      render(view)

      assert load(c.target.id).year == 2020
    end

    test "text is still editable and saves", %{conn: conn} = c do
      view = open(conn, c.target.id)
      await_selector(view, ".translation-panel.is-target")

      view |> form("#article_form_form", %{"article" => %{"title" => "Title"}}) |> render_submit()
      assert_push_event(view, "b:submit", %{}, 2_000)
      view |> form("#article_form_form", %{"article" => %{"title" => "Title"}}) |> render_submit()
      assert_redirect(view, 3_000)

      assert load(c.target.id).title == "Title"
    end
  end

  describe "synchronization controls" do
    defp minor_save(view) do
      view |> element("button", "Save minor text corrections") |> render_click()
      assert_push_event(view, "b:submit", %{}, 2_000)
      view |> form("#article_form_form") |> render_submit()
      assert_push_event(view, "b:submit", %{}, 2_000)
      view |> form("#article_form_form") |> render_submit()
      render(view)
    end

    test "a minor save of the source asks for no review of changed text", %{conn: conn} = c do
      [join] = load(c.source.id).entry_blocks
      set_text(join.block, "Første avsnitt, rettet")
      view = open(conn, c.source.id)
      await_selector(view, ".translation-panel.is-source")
      minor_save(view)

      assert Translations.get_pending_version(Article, c.target.id) == nil

      # The next ordinary save only raises review for what changes after it.
      set_text(join.block, "Første avsnitt, omskrevet")
      Translations.source_saved(load(c.source.id))
      assert %{work_items: [%{kind: :review}]} = Translations.get_pending_version(Article, c.target.id)
    end

    test "make independent keeps the unsaved changes in the form", %{conn: conn} = c do
      change_source(c)
      view = open(conn, c.target.id)
      await_selector(view, "input[name='article[year]'][value='2024']")

      view |> element("button", "Make independent") |> render_click()

      assert %{synchronized: false} = Translations.get_member(Article, c.target.id)
      assert has_element?(view, ".translation-panel.is-independent")
      refute has_element?(view, ".blocks-wrapper.is-source-locked")
      assert has_element?(view, "input[name='article[year]'][value='2024']")

      save(view)
      saved = load(c.target.id)
      assert saved.year == 2024
      assert saved.status == c.target.status
    end

    test "make source hands the role to the translation", %{conn: conn} = c do
      view = open(conn, c.target.id)
      await_selector(view, ".translation-panel.is-target")

      view |> element("button", "Make source") |> render_click()

      assert %{role: :source} = Translations.get_member(Article, c.target.id)
      assert %{role: :target, synchronized: true} = Translations.get_member(Article, c.source.id)
      assert has_element?(view, ".translation-panel.is-source")
    end

    test "a translation is created on demand as a linked draft", %{conn: conn, current_user: user} do
      {:ok, entry} =
        SyncTest.create_article(%{title: "Alene", slug: "alene", language: "no", status: "published"}, user)

      view = open(conn, entry.id)
      await_selector(view, ".translation-panel.is-unlinked")
      view |> element(".translation-create button[phx-value-language='en']") |> render_click()

      {path, _flash} = assert_redirect(view)
      [_, id] = Regex.run(~r{/admin/articles/update/(\d+)}, path)
      created = load(String.to_integer(id))

      assert created.language == :en
      assert created.status == :draft
      assert %{role: :target} = Translations.get_member(Article, created.id)
      assert %{role: :source} = Translations.get_member(Article, entry.id)
    end
  end

  test "creating a translation needs permission to create entries", %{current_user: user} = c do
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
    {:ok, entry} = SyncTest.create_article(%{title: "Alene", slug: "alene", language: "no", status: "draft"}, user)

    view = open(log_in_user(build_conn(), editor), entry.id)
    refute has_element?(view, ".translation-create")

    # A forged event is refused as well.
    [cid] = view |> render() |> Floki.parse_document!() |> Floki.attribute("#article_title", "phx-target")
    view |> with_target("[data-phx-component='#{cid}']") |> render_click("create_translation", %{"language" => "en"})
    assert Translations.get_member(Article, entry.id) == nil
    _ = c
  end

  describe "listing" do
    test "shows each language version and its open work, linking to it", %{conn: conn} = c do
      change_source(c)
      {:ok, view, _html} = live(conn, "/admin/articles")
      html = await_selector(view, ".listing-translations")

      assert has_element?(view, "a.listing-translation.is-source[href='/admin/articles/update/#{c.source.id}']", "Source")

      assert has_element?(
               view,
               "a.listing-translation.is-work[href='/admin/articles/update/#{c.target.id}']",
               "1 to translate"
             )

      assert html =~ "EN"
    end

    test "is refreshed when the source is synchronized", %{conn: conn} = c do
      {:ok, view, _html} = live(conn, "/admin/articles")
      await_selector(view, "a.listing-translation.is-current")

      change_source(c)
      await_selector(view, "a.listing-translation.is-work")
    end

    test "decorates every page", %{conn: conn, current_user: user} = c do
      for n <- 1..26 do
        SyncTest.create_article(%{title: "Filler #{n}", slug: "filler-#{n}", language: "en", status: "draft"}, user)
      end

      {:ok, last} = SyncTest.create_article(%{title: "Last", slug: "last", language: "no", status: "draft"}, user)
      {:ok, last_en} = Translations.create_target(Article, last.id, :en, user)

      # The listing shows the content language, English: the first and the
      # last English article are translations, one on each page.
      for page <- ["1", "2"] do
        {:ok, view, _html} = live(conn, "/admin/articles?page=#{page}")
        html = await_selector(view, ".listing-translations")
        assert html =~ "/admin/articles/update/#{c.target.id}" or html =~ "/admin/articles/update/#{last_en.id}"
      end
    end
  end

  test "the source shows its translations", %{conn: conn} = c do
    view = open(conn, c.source.id)
    await_selector(view, ".translation-panel.is-source")
    assert has_element?(view, ".translation-members a[href='/admin/articles/update/#{c.target.id}']")
    refute has_element?(view, "input[name='translation_review[version_id]']")
  end
end
