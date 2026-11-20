defmodule BrandoAdmin.TranslationFormTest do
  # The editor side of synchronized translations: a translation opens with its
  # pending version in the form, lists its work, and the save resolves only
  # what the editor reviewed.
  use Brando.LiveCase

  alias Brando.Content.Block
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.TranslationFixtures
  alias Brando.Translations
  alias Brando.Translations.PendingVersion

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

    TranslationFixtures.add_block(source, module, user, "Første avsnitt", 0)
    # A translation that has been translated: its text is written below,
    # past the editor, so none of it is marked to translate.
    {:ok, target} = Translations.create_target(Article, source.id, :en, user, mark_translate: false)
    translate(target, ["First paragraph"])

    %{module: module, source: source, target: target}
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

  defp add_block(c, article, params, sequence) do
    params =
      Map.merge(
        %{
          "uid" => Brando.Utils.generate_uid(),
          "type" => "module",
          "module_id" => c.module.id,
          "creator_id" => c.current_user.id,
          "source" => to_string(Article.Blocks)
        },
        params
      )

    block =
      %Block{} |> Block.recursive_block_changeset(params, c.current_user) |> Repo.insert!()

    struct(Article.Blocks, %{entry_id: article.id, block_id: block.id, sequence: sequence}) |> Repo.insert!()
  end

  defp picture_refs(id) do
    for join <- load(id).entry_blocks, ref <- join.block.refs, ref.name == "photo", do: ref
  end

  defp set_alt(id, image_id, alt) do
    [ref] = picture_refs(id)

    ref
    |> Ecto.Changeset.change(image_id: image_id, data: %{ref.data | data: %{ref.data.data | alt: alt}})
    |> Repo.update!()
  end

  # The source adds a block and changes the year.
  defp change_source(c) do
    TranslationFixtures.add_block(c.source, c.module, c.current_user, "Nytt avsnitt", 1)
    {:ok, _} = SyncTest.update_article(c.source.id, %{year: 2024}, c.current_user)
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

  test "a new translation lists every text it copied as needing translation", %{conn: conn, current_user: user} = c do
    {:ok, source} =
      SyncTest.create_article(
        %{title: "Ny kilde", slug: "ny-kilde", language: "no", status: "published", year: 2020},
        user
      )

    TranslationFixtures.add_block(source, c.module, user, "Avsnitt", 0)
    {:ok, target} = Translations.create_target(Article, source.id, :en, user)
    version = Translations.get_pending_version(Article, target.id)

    view = open(conn, target.id)
    await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")

    refute has_element?(view, ".translation-done")
    assert has_element?(view, ".translation-summary", "2 items need attention")
    assert has_element?(view, ".translation-group", "Needs translation")
    assert has_element?(view, ".translation-item-label", "Title")
    # The version changes nothing yet: the form opens as it was saved, not
    # with the version loaded as unsaved changes.
    refute has_element?(view, ".translation-summary", "The changes from the source are in the form")
    refute_push_event(view, "b:draft-dirty", _, 200)

    # Marked reviewed, the title is done; the block's text stays open.
    view
    |> element("#article_form_form")
    |> render_change(%{"translation_review" => %{"acknowledged" => ["title"]}})

    save(view)

    assert [{:translate, "entry_blocks/" <> _}] =
             for(
               item <- Translations.get_pending_version(Article, target.id).work_items,
               is_nil(item.resolved_at),
               do: {item.kind, item.path}
             )
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
    # The version the editor reviewed is the one applied: no recompute queued by
    # the save replaced it first.
    assert Repo.get!(PendingVersion, version.id).status == :applied
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

  # A form without block fields saves in one submit, without collecting
  # blocks first (`has_blocks?: false`).
  describe "a form without block fields" do
    defp save_without_blocks(view, params) do
      view |> form("#article_form_form", params) |> render_submit()
      assert_push_event(view, "b:submit", %{}, 2_000)
      view |> form("#article_form_form", params) |> render_submit()
      assert_redirect(view, 3_000)
    end

    test "a translation saves", %{conn: conn} = c do
      {view, _html} = live_form(conn, "/admin/articles/update/#{c.target.id}/no-blocks", "article_form")
      await_selector(view, ".translation-panel.is-target")

      save_without_blocks(view, %{"article" => %{"title" => "Title"}})

      assert load(c.target.id).title == "Title"
    end

    # The form has no input for the year or the blocks, so the pending
    # version's stay pending: the save keeps the saved ones.
    test "a translation with a pending version saves what the form holds", %{conn: conn} = c do
      version = change_source(c)
      {view, _html} = live_form(conn, "/admin/articles/update/#{c.target.id}/no-blocks", "article_form")
      await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")

      save_without_blocks(view, %{"article" => %{"title" => "Title"}})

      saved = load(c.target.id)
      assert saved.title == "Title"
      assert saved.year == 2020
      assert texts(saved) == ["First paragraph"]

      assert %{work_items: items} = Translations.get_pending_version(Article, c.target.id)
      assert Enum.any?(items, &(&1.kind == :translate))
    end

    # The source rewrites its block and hides it. The form can't show the
    # block, so marking its text reviewed doesn't resolve the review: the
    # save left the block as it was.
    test "work in a block the save left stays open", %{conn: conn} = c do
      [join] = load(c.source.id).entry_blocks
      set_text(join.block, "Første avsnitt, endret")
      join.block |> Ecto.Changeset.change(active: false) |> Repo.update!()
      Translations.source_saved(load(c.source.id))
      version = Translations.get_pending_version(Article, c.target.id)
      [item] = Enum.filter(version.work_items, &(&1.kind == :review))

      {view, _html} = live_form(conn, "/admin/articles/update/#{c.target.id}/no-blocks", "article_form")
      await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")

      view
      |> element("#article_form_form")
      |> render_change(%{"translation_review" => %{"acknowledged" => [item.path]}})

      save_without_blocks(view, %{"article" => %{"title" => "Title"}})

      assert [%{active: true}] = Enum.map(load(c.target.id).entry_blocks, & &1.block)
      assert %{work_items: items} = Translations.get_pending_version(Article, c.target.id)
      assert Enum.any?(items, &(&1.path == item.path and is_nil(&1.resolved_at)))
    end

    # The blocks the form can't show stay as they were, which the save may
    # do; the forged year is neither the saved nor the pending one, and is
    # the only thing refused.
    test "a forged value it has no input for is still refused", %{conn: conn} = c do
      version = change_source(c)
      {view, _html} = live_form(conn, "/admin/articles/update/#{c.target.id}/no-blocks", "article_form")
      await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")

      Logger.put_module_level(BrandoAdmin.Components.Form, :warning)
      on_exit(fn -> Logger.delete_module_level(BrandoAdmin.Components.Form) end)
      params = %{"article" => %{"title" => "Title", "year" => "1999"}}

      log =
        ExUnit.CaptureLog.capture_log([level: :warning], fn ->
          view |> form("#article_form_form") |> render_submit(params)
          assert_push_event(view, "b:submit", %{}, 2_000)
          view |> form("#article_form_form") |> render_submit(params)
          render(view)
        end)

      assert log =~ ~s(source-controlled content: ["year"])

      saved = load(c.target.id)
      assert saved.title == "Tittel"
      assert saved.year == 2020
    end

    # The source swaps the picture's image and rewrites its alt text. The form
    # can't show the picture, so the image stays pending, and marking the alt
    # text reviewed doesn't resolve its review: the save left the picture as
    # it was.
    test "text work in a ref whose media the save left stays open", %{conn: conn, current_user: user} = c do
      [image, other] =
        for _ <- 1..2,
            do: Factory.insert(:image, creator: user, focal: %Brando.Images.Focal{x: 50, y: 50}, status: :processed)

      ref = %{
        "uid" => Brando.Utils.generate_uid(),
        "name" => "photo",
        "image_id" => image.id,
        "data" => %{"type" => "picture", "data" => %{"alt" => "Hund"}}
      }

      {:ok, source} =
        SyncTest.create_article(%{title: "Bilde", slug: "bilde", language: "no", status: "published"}, user)

      add_block(c, source, %{"refs" => [ref]}, 0)
      {:ok, target} = Translations.create_target(Article, source.id, :en, user)
      set_alt(target.id, image.id, "Dog")

      set_alt(source.id, other.id, "Katt")
      Translations.source_saved(load(source.id))
      version = Translations.get_pending_version(Article, target.id)
      [item] = Enum.filter(version.work_items, &String.ends_with?(&1.path, "/refs/photo/alt"))

      {view, _html} = live_form(conn, "/admin/articles/update/#{target.id}/no-blocks", "article_form")
      await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")

      view
      |> element("#article_form_form")
      |> render_change(%{"translation_review" => %{"acknowledged" => [item.path]}})

      save_without_blocks(view, %{"article" => %{"title" => "Title"}})

      assert [%{image_id: image_id}] = picture_refs(target.id)
      assert image_id == image.id
      assert %{work_items: items} = Translations.get_pending_version(Article, target.id)
      assert Enum.any?(items, &(&1.path == item.path and is_nil(&1.resolved_at)))
    end

    test "a translation takes the source's new cover", %{conn: conn, current_user: user} = c do
      cover = Factory.insert(:image, creator: user, focal: %Brando.Images.Focal{x: 50, y: 50}, status: :processed)
      {:ok, _} = SyncTest.update_article(c.source.id, %{cover_id: cover.id}, user)
      version = Translations.get_pending_version(Article, c.target.id)
      {view, _html} = live_form(conn, "/admin/articles/update/#{c.target.id}/elsewhere", "article_form")
      await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")

      save_without_blocks(view, %{"article" => %{"title" => "Title"}})

      saved = load(c.target.id)
      assert saved.title == "Title"
      assert saved.cover_id == cover.id
    end
  end

  # The form opens an entry in the trash, so a translation there saves, its
  # pending version with it.
  test "a translation in the trash saves", %{conn: conn, current_user: user} do
    put_test_env(Page, translatable: [mode: :synchronized])
    source = Factory.insert(:page, title: "Om oss", uri: "om-oss", language: :no, creator: user)
    {:ok, target} = Translations.create_target(Page, source.id, :en, user)
    {:ok, _} = Brando.Pages.update_page(source.id, %{title: "Om oss, endret"}, user)
    version = Translations.get_pending_version(Page, target.id)
    {:ok, _} = Brando.Pages.delete_page(target.id, user)

    {view, _html} = live_form(conn, "/admin/pages/update/#{target.id}")
    await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")
    view |> form("#page_form_form", %{"page" => %{"title" => "About us"}}) |> render_submit()
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form("#page_form_form", %{"page" => %{"title" => "About us"}}) |> render_submit()
    assert_redirect(view, 3_000)

    {:ok, saved} = Brando.Pages.get_page(%{matches: %{id: target.id}, with_deleted: true})
    assert {saved.title, saved.deleted_at != nil} == {"About us", true}
    assert Repo.get!(PendingVersion, version.id).status == :applied
  end

  # The trash gives a translation's URI a trash form, freeing it for another
  # page. A pending version taken before the trash holds the live URI, one
  # taken in the trash holds the trash form: the save takes the version's
  # content and leaves the URI as the entry has it.
  describe "a translation in the trash" do
    setup %{current_user: user} do
      put_test_env(Page, translatable: [mode: :synchronized, source_controlled_fields: [:css_classes]])
      source = Factory.insert(:page, title: "Om oss", uri: "om-oss", language: :no, creator: user)
      {:ok, target} = Translations.create_target(Page, source.id, :en, user)
      {:ok, _} = Brando.Pages.update_page(source.id, %{title: "Om oss, endret", css_classes: "wide"}, user)
      version = Translations.get_pending_version(Page, target.id)
      {:ok, _} = Brando.Pages.delete_page(target.id, user)

      %{target: Repo.get!(Page, target.id), version: version}
    end

    defp save_page(conn, id) do
      {view, _html} = live_form(conn, "/admin/pages/update/#{id}")
      await_selector(view, "input[name='translation_review[version_id]']")
      view |> form("#page_form_form") |> render_submit()
      assert_push_event(view, "b:submit", %{}, 2_000)
      view |> form("#page_form_form") |> render_submit()
      assert_redirect(view, 3_000)

      {:ok, saved} = Brando.Pages.get_page(%{matches: %{id: id}, with_deleted: true})
      saved
    end

    test "keeps its trash URI and takes the source's content", %{conn: conn, target: target, version: version} do
      assert target.uri =~ "$$$"

      saved = save_page(conn, target.id)

      assert {saved.uri, saved.css_classes, saved.deleted_at != nil} == {target.uri, "wide", true}
      assert Repo.get!(PendingVersion, version.id).status == :applied
    end

    test "restored, gets its URI back and keeps the source's content", c do
      _ = save_page(c.conn, c.target.id)
      {:ok, restored} = Brando.Authorization.Boundary.restore(c.current_user, Repo.get!(Page, c.target.id))
      assert {restored.uri, restored.css_classes, restored.deleted_at} == {"om-oss", "wide", nil}

      # The title's review is still open, in a version taken in the trash
      assert Translations.get_pending_version(Page, c.target.id)

      saved = save_page(c.conn, c.target.id)
      assert {saved.uri, saved.css_classes, saved.deleted_at} == {"om-oss", "wide", nil}
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

      # The chips list the language versions; the alternates button would repeat them.
      refute has_element?(view, ".listing-alternates")
    end

    test "a row's menu creates a translation in the group, not a copy beside it", %{conn: conn, current_user: user} = c do
      {:ok, alone} = SyncTest.create_article(%{title: "Alone", slug: "alone", language: "en", status: "draft"}, user)
      {:ok, view, _html} = live(conn, "/admin/articles")
      await_selector(view, ".listing-translations")

      refute has_element?(view, "[phx-click='duplicate_entry_to_language']")
      refute has_element?(view, "[phx-click='translate_entry_to_language']")
      # The translated entry has every language already.
      refute has_element?(view, "[id$='_create_translation_#{c.target.id}_lang_no']")

      view |> element("[id$='_create_translation_#{alone.id}_lang_no']") |> render_click()

      assert %{role: :source, group_id: group_id} = Translations.get_member(Article, alone.id)

      assert [%{language: "no", role: :target, entry_id: target_id}] =
               group_id |> Translations.list_members() |> Enum.filter(&(&1.language == "no"))

      # It opens the new translation, as the form's button does.
      assert_redirect(view, "/admin/articles/update/#{target_id}")
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

  # The source drops blocks and adds others: the pending version holds the
  # field as the source has it, and the translation's form saves it as it
  # opened it. The pending version leaves the dropped rows out, so the
  # changeset it is loaded from marks them `:replace` (#3756).
  describe "the source dropped a block and added another" do
    defp drop_block(join) do
      Repo.delete!(join)
      Repo.delete!(join.block)
    end

    # The source's next save makes the pending version.
    defp source_saved(c) do
      {:ok, _} = SyncTest.update_article(c.source.id, %{year: 2024}, c.current_user)
      Translations.get_pending_version(Article, c.target.id)
    end

    defp open_version(conn, id, version) do
      view = open(conn, id)
      await_selector(view, "input[name='translation_review[version_id]'][value='#{version.id}']")
      view
    end

    defp assert_follows_source(c, version) do
      assert Repo.get!(PendingVersion, version.id).status == :applied
      saved = load(c.target.id)
      assert block_ids(saved) == block_ids(load(c.source.id))
      saved
    end

    # Each block's identity, with its children's, in order.
    defp block_ids(entry), do: Enum.map(entry.entry_blocks, &block_id(&1.block))

    defp block_id(block) do
      children = block.children |> Enum.sort_by(&{&1.sequence, &1.id}) |> Enum.map(&block_id/1)
      rows = block.table_rows |> Enum.sort_by(&{&1.sequence, &1.id}) |> Enum.map(& &1.sync_uid)
      {block.sync_uid, children, rows}
    end

    test "a translation saves it", %{conn: conn} = c do
      [join] = load(c.source.id).entry_blocks
      drop_block(join)
      TranslationFixtures.add_block(c.source, c.module, c.current_user, "Nytt avsnitt", 0)
      version = source_saved(c)

      conn |> open_version(c.target.id, version) |> save()

      saved = assert_follows_source(c, version)
      assert {saved.year, texts(saved)} == {2024, ["Nytt avsnitt"]}
    end

    test "a drop alone leaves the block out", %{conn: conn} = c do
      c = pair(c, &TranslationFixtures.add_block(&1, c.module, c.current_user, "Andre avsnitt", 1))
      translate(c.target, ["First paragraph", "Second paragraph"])

      [first, _second] = load(c.source.id).entry_blocks
      drop_block(first)
      version = source_saved(c)

      conn |> open_version(c.target.id, version) |> save()

      saved = assert_follows_source(c, version)
      assert texts(saved) == ["Second paragraph"]
    end

    test "several dropped and several added", %{conn: conn} = c do
      c =
        pair(c, fn source ->
          TranslationFixtures.add_block(source, c.module, c.current_user, "Andre", 1)
          TranslationFixtures.add_block(source, c.module, c.current_user, "Tredje", 2)
        end)

      [first, _second, third] = load(c.source.id).entry_blocks
      drop_block(first)
      drop_block(third)
      TranslationFixtures.add_block(c.source, c.module, c.current_user, "Fjerde", 0)
      TranslationFixtures.add_block(c.source, c.module, c.current_user, "Femte", 3)
      version = source_saved(c)

      conn |> open_version(c.target.id, version) |> save()

      saved = assert_follows_source(c, version)
      assert texts(saved) == ["Fjerde", "Andre", "Femte"]
    end

    test "a container's child dropped while a sibling is added", %{conn: conn} = c do
      c = pair(c, &add_container(c, &1, ["Første barn", "Andre barn"]))
      [_, %{block: container}] = load(c.source.id).entry_blocks

      [first_child, _] = Repo.preload(container, :children).children |> Enum.sort_by(& &1.sequence)
      Repo.delete!(first_child)
      add_child(c, container, "Tredje barn", 2)
      version = source_saved(c)

      conn |> open_version(c.target.id, version) |> save()

      saved = assert_follows_source(c, version)
      [_, %{block: shown}] = saved.entry_blocks
      assert length(shown.children) == 2
    end

    test "a table row dropped while another is added", %{conn: conn} = c do
      c = pair(c, &add_table_block(c, &1, ["r1", "r2"]))
      [_, %{block: block}] = load(c.source.id).entry_blocks

      [r1, _] = Repo.preload(block, :table_rows).table_rows |> Enum.sort_by(& &1.sequence)
      Repo.delete!(r1)
      insert_row(block, "r3", 2)
      version = source_saved(c)

      conn |> open_version(c.target.id, version) |> save()

      saved = assert_follows_source(c, version)
      [_, %{block: table}] = saved.entry_blocks
      assert Enum.map(Enum.sort_by(table.table_rows, & &1.sequence), & &1.sync_uid) == ["r2", "r3"]
    end

    test "a second editor in the entry saves it", %{conn: conn} = c do
      [join] = load(c.source.id).entry_blocks
      drop_block(join)
      TranslationFixtures.add_block(c.source, c.module, c.current_user, "Nytt avsnitt", 0)
      version = source_saved(c)

      _first = open_version(conn, c.target.id, version)
      other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      other_conn = log_in_user(Phoenix.ConnTest.build_conn(), other)
      other_conn |> open_version(c.target.id, version) |> save()

      saved = assert_follows_source(c, version)
      assert texts(saved) == ["Nytt avsnitt"]
    end

    test "a reconnect saves it", %{conn: conn} = c do
      [join] = load(c.source.id).entry_blocks
      drop_block(join)
      TranslationFixtures.add_block(c.source, c.module, c.current_user, "Nytt avsnitt", 0)
      version = source_saved(c)

      view = open_version(conn, c.target.id, version)
      params = view |> render() |> form_params("#article_form_form")
      kill_live(view)

      # LiveView's recovery replays the form's last params into the new process.
      view = open_version(conn, c.target.id, version)
      view |> element("#article_form_form") |> render_change(params)
      save(view)

      saved = assert_follows_source(c, version)
      assert texts(saved) == ["Nytt avsnitt"]
    end

    test "a source change while the form is open saves after the form takes it", %{conn: conn} = c do
      first = change_year(c, 2024)
      view = open_version(conn, c.target.id, first)

      [join] = load(c.source.id).entry_blocks
      drop_block(join)
      TranslationFixtures.add_block(c.source, c.module, c.current_user, "Nytt avsnitt", 0)
      change_year(c, 2030)

      # The save writes the version the form opened with, then takes the new one.
      view |> element("button", "Save and continue editing") |> render_click()
      assert_push_event(view, "b:submit", %{}, 2_000)
      view |> form("#article_form_form") |> render_submit()
      assert_push_event(view, "b:submit", %{}, 2_000)
      view |> form("#article_form_form") |> render_submit()
      await_selector(view, "input[name='article[year]'][value='2030']", 3_000)
      second = Translations.get_pending_version(Article, c.target.id)

      view |> element("button", "Save and continue editing") |> render_click()
      assert_push_event(view, "b:submit", %{}, 2_000)
      view |> form("#article_form_form") |> render_submit()
      assert_push_event(view, "b:submit", %{}, 2_000)
      view |> form("#article_form_form") |> render_submit()

      Brando.EditSessionEditors.await(fn -> Repo.get!(PendingVersion, second.id).status == :applied end)
      saved = load(c.target.id)
      assert block_ids(saved) == block_ids(load(c.source.id))
      assert {saved.year, texts(saved)} == {2030, ["Nytt avsnitt"]}
    end

    # The source moves a container's child into another container.
    defp move_child(c) do
      c =
        pair(c, fn source ->
          add_container(c, source, ["Første barn", "Andre barn"])
          add_container(c, source, ["Tredje barn"], 2)
        end)

      [_, %{block: from}, %{block: to}] = load(c.source.id).entry_blocks
      [moved, _] = Repo.preload(from, :children).children |> Enum.sort_by(& &1.sequence)
      moved |> Ecto.Changeset.change(parent_id: to.id, sequence: 1) |> Repo.update!()
      {c, source_saved(c)}
    end

    defp assert_moved(c, version) do
      saved = assert_follows_source(c, version)
      [_, %{block: from}, %{block: to}] = saved.entry_blocks
      assert {length(from.children), length(to.children)} == {1, 2}
    end

    test "a child the source moved to another container", %{conn: conn} = c do
      {c, version} = move_child(c)

      conn |> open_version(c.target.id, version) |> save()

      assert_moved(c, version)
    end

    test "a child the source moved to another container, with a second editor in the entry", %{conn: conn} = c do
      {c, version} = move_child(c)

      # the translation's copy of the moved child, still in the first container
      [_, %{block: from}, %{block: to}] = load(c.target.id).entry_blocks
      [moved | _] = Enum.sort_by(from.children, & &1.sequence)

      first = open_version(conn, c.target.id, version)
      other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      other_conn = log_in_user(Phoenix.ConnTest.build_conn(), other)
      second = open_version(other_conn, c.target.id, version)

      # each shows the moved child once, in the container the source has it in
      for view <- [first, second] do
        assert view |> element("#child-#{moved.uid}") |> render() =~ ~s(data-parent_uid="#{to.uid}")
      end

      save(second)

      assert_moved(c, version)
    end

    test "a container whose only child the source moved out shows as empty to a second editor", %{conn: conn} = c do
      c =
        pair(c, fn source ->
          add_container(c, source, ["Første barn"])
          add_container(c, source, ["Andre barn"], 2)
        end)

      [_, %{block: from}, %{block: to}] = load(c.source.id).entry_blocks
      [moved] = Repo.preload(from, :children).children
      moved |> Ecto.Changeset.change(parent_id: to.id, sequence: 1) |> Repo.update!()
      version = source_saved(c)

      [_, %{block: emptied}, _] = load(c.target.id).entry_blocks

      _first = open_version(conn, c.target.id, version)
      other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      second = log_in_user(Phoenix.ConnTest.build_conn(), other) |> open_version(c.target.id, version)

      # its only child is in the other container: it holds none, so it shows the empty hint
      assert has_element?(second, "[data-block-uid='#{emptied.uid}'] .blocks-empty-instructions")
      refute has_element?(second, "[data-block-uid='#{emptied.uid}'] .block-children")
    end

    # A block on an older version of its module: it keeps a variable the
    # module no longer defines (`Brando.Content.StaleBlocks`), written past
    # the changeset as a module save leaves it. The pending version holds it;
    # the restore cannot carry it (`Brando.Drafts.Modules`), so it stays in
    # the form as the translation has it.
    defp make_stale(block) do
      Repo.insert!(%Brando.Content.Var{
        block_id: block.id,
        type: :string,
        key: "old",
        label: %{"en" => "Old"},
        value: "left over",
        sequence: 0
      })

      block
    end

    defp add_stale_block(c, source, text, sequence),
      do: source |> TranslationFixtures.add_block(c.module, c.current_user, text, sequence) |> make_stale()

    defp add_stale_child_container(c, source) do
      container = add_container(c, source, ["Første barn", "Gammelt barn"])
      [_, stale] = Repo.preload(container, :children).children |> Enum.sort_by(& &1.sequence)
      make_stale(stale)
      container
    end

    defp child_texts(entry) do
      for %{block: %{type: :container} = container} <- entry.entry_blocks,
          child <- Enum.sort_by(container.children, &{&1.sequence, &1.id}),
          do: hd(child.refs).data.data.text
    end

    test "a stale block the source kept stays and saves", %{conn: conn} = c do
      c = pair(c, &add_stale_block(c, &1, "Gammelt avsnitt", 1))
      translate(c.target, ["First paragraph", "Old paragraph"])
      version = source_saved(c)

      conn |> open_version(c.target.id, version) |> save()

      saved = assert_follows_source(c, version)
      assert {saved.year, texts(saved)} == {2024, ["First paragraph", "Old paragraph"]}
      [_, %{block: stale}] = saved.entry_blocks
      assert Enum.map(Repo.preload(stale, :vars, force: true).vars, & &1.key) == ["old"]
    end

    test "a stale block the source kept stays while another is dropped and added", %{conn: conn} = c do
      c = pair(c, &add_stale_block(c, &1, "Gammelt avsnitt", 1))
      translate(c.target, ["First paragraph", "Old paragraph"])

      [first, _stale] = load(c.source.id).entry_blocks
      drop_block(first)
      TranslationFixtures.add_block(c.source, c.module, c.current_user, "Nytt avsnitt", 2)
      version = source_saved(c)

      conn |> open_version(c.target.id, version) |> save()

      saved = assert_follows_source(c, version)
      assert texts(saved) == ["Old paragraph", "Nytt avsnitt"]
    end

    test "a stale child the source kept stays and saves", %{conn: conn} = c do
      c = pair(c, &add_stale_child_container(c, &1))
      version = source_saved(c)

      conn |> open_version(c.target.id, version) |> save()

      saved = assert_follows_source(c, version)
      assert child_texts(saved) == ["Første barn", "Gammelt barn"]
    end

    test "a stale child the source kept stays while a sibling is dropped and another added", %{conn: conn} = c do
      c = pair(c, &add_stale_child_container(c, &1))
      [_, %{block: container}] = load(c.source.id).entry_blocks
      [first_child, _] = Repo.preload(container, :children).children |> Enum.sort_by(& &1.sequence)
      Repo.delete!(first_child)
      add_child(c, container, "Tredje barn", 2)
      version = source_saved(c)

      conn |> open_version(c.target.id, version) |> save()

      saved = assert_follows_source(c, version)
      assert child_texts(saved) == ["Gammelt barn", "Tredje barn"]
    end

    # A stale multi module block, its entries below it.
    defp add_stale_multi_block(c, source) do
      {:ok, multi} =
        Brando.Content.create_module(
          Factory.params_for(:module,
            name: %{"en" => "List"},
            namespace: %{"en" => "Content"},
            help_text: %{},
            code: "<ul>{{ content }}</ul>",
            multi: true,
            refs: [],
            vars: []
          ),
          c.current_user
        )

      entries =
        for {text, i} <- Enum.with_index(["Første punkt", "Andre punkt"]),
            do: c |> module_block(text, i) |> Map.put("type", "module_entry")

      params = %{
        "uid" => Brando.Utils.generate_uid(),
        "type" => "module",
        "multi" => true,
        "module_id" => multi.id,
        "creator_id" => c.current_user.id,
        "source" => to_string(Article.Blocks),
        "children" => entries
      }

      block = %Block{} |> Block.recursive_block_changeset(params, c.current_user) |> Repo.insert!()
      struct(Article.Blocks, %{entry_id: source.id, block_id: block.id, sequence: 1}) |> Repo.insert!()
      make_stale(block)
    end

    # A stale block holding a region slot, a block in the slot.
    defp add_stale_slot_block(c, source) do
      block = add_stale_block(c, source, "Med område", 1)

      uid = Brando.Utils.generate_uid()

      slot =
        Repo.insert!(%Block{
          uid: uid,
          sync_uid: uid,
          type: :slot,
          slot_kind: :region,
          slot_name: "sidebar",
          slot_module_set: "all",
          source: Article.Blocks,
          creator_id: c.current_user.id,
          parent_id: block.id
        })

      add_child(c, slot, "I området", 0)
      block
    end

    # The texts of a block's descendants, depth first, as saved.
    defp subtree_texts(block) do
      block
      |> Repo.preload([children: :refs], force: true)
      |> Map.fetch!(:children)
      |> Enum.sort_by(&{&1.sequence, &1.id})
      |> Enum.flat_map(fn child ->
        Enum.map(child.refs, & &1.data.data.text) ++ subtree_texts(child)
      end)
    end

    defp stale_subtree(entry),
      do: entry.entry_blocks |> Enum.find(&(&1.block.vars != [])) |> then(&subtree_texts(&1.block))

    defp add_stale_owner(c, source, :multi), do: add_stale_multi_block(c, source)
    defp add_stale_owner(c, source, :slot), do: add_stale_slot_block(c, source)

    defp drop_first_and_add(c) do
      [first | _] = load(c.source.id).entry_blocks
      drop_block(first)
      TranslationFixtures.add_block(c.source, c.module, c.current_user, "Nytt avsnitt", 2)
    end

    for {name, build, texts} <- [
          {"a stale multi block keeps its entries", :multi, ["Første punkt", "Andre punkt"]},
          {"a stale block keeps the blocks in its slot", :slot, ["I området"]}
        ] do
      test name, %{conn: conn} = c do
        c = pair(c, &add_stale_owner(c, &1, unquote(build)))
        version = source_saved(c)

        conn |> open_version(c.target.id, version) |> save()

        saved = assert_follows_source(c, version)
        assert stale_subtree(saved) == unquote(texts)
      end

      test "#{name} while another is dropped and added", %{conn: conn} = c do
        c = pair(c, &add_stale_owner(c, &1, unquote(build)))
        drop_first_and_add(c)
        version = source_saved(c)

        conn |> open_version(c.target.id, version) |> save()

        saved = assert_follows_source(c, version)
        assert stale_subtree(saved) == unquote(texts)
      end
    end

    defp change_year(c, year) do
      {:ok, _} = SyncTest.update_article(c.source.id, %{year: year}, c.current_user)
      Translations.get_pending_version(Article, c.target.id)
    end

    defp module_block(c, text, sequence) do
      %{
        "uid" => Brando.Utils.generate_uid(),
        "type" => "module",
        "module_id" => c.module.id,
        "creator_id" => c.current_user.id,
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

    # A source with the setup's block and what `build` adds, and its
    # translation, translated.
    defp pair(c, build) do
      slug = "kilde-#{System.unique_integer([:positive])}"

      {:ok, source} =
        SyncTest.create_article(
          %{title: "Kilde", slug: slug, language: "no", status: "published", year: 2020},
          c.current_user
        )

      TranslationFixtures.add_block(source, c.module, c.current_user, "Første avsnitt", 0)
      build.(source)
      {:ok, target} = Translations.create_target(Article, source.id, :en, c.current_user, mark_translate: false)
      %{c | source: source, target: target}
    end

    defp add_container(c, source, texts, sequence \\ 1) do
      params = %{
        "uid" => Brando.Utils.generate_uid(),
        "type" => "container",
        "creator_id" => c.current_user.id,
        "source" => to_string(Article.Blocks),
        "children" => texts |> Enum.with_index() |> Enum.map(fn {text, i} -> module_block(c, text, i) end)
      }

      container = %Block{} |> Block.recursive_block_changeset(params, c.current_user) |> Repo.insert!()
      struct(Article.Blocks, %{entry_id: source.id, block_id: container.id, sequence: sequence}) |> Repo.insert!()
      container
    end

    defp add_child(c, container, text, sequence) do
      params = Map.put(module_block(c, text, sequence), "parent_id", container.id)
      %Block{} |> Block.recursive_block_changeset(params, c.current_user) |> Repo.insert!()
    end

    defp add_table_block(c, source, row_ids) do
      template = Repo.insert!(%Brando.Content.TableTemplate{uid: Brando.Utils.generate_uid(), name: "Rows"})

      Repo.insert!(%Brando.Content.Var{
        type: :string,
        key: "cell",
        label: %{"en" => "Cell"},
        table_template_id: template.id
      })

      {:ok, module} =
        Brando.Content.create_module(
          Factory.params_for(:module,
            name: %{"en" => "Table"},
            namespace: %{"en" => "Content"},
            help_text: %{},
            code: "<table></table>",
            refs: [],
            vars: [],
            table_template_id: template.id
          ),
          c.current_user
        )

      params = %{
        "uid" => Brando.Utils.generate_uid(),
        "type" => "module",
        "module_id" => module.id,
        "creator_id" => c.current_user.id,
        "source" => to_string(Article.Blocks)
      }

      block = %Block{} |> Block.recursive_block_changeset(params, c.current_user) |> Repo.insert!()
      struct(Article.Blocks, %{entry_id: source.id, block_id: block.id, sequence: 1}) |> Repo.insert!()
      row_ids |> Enum.with_index() |> Enum.each(fn {id, i} -> insert_row(block, id, i) end)
      block
    end

    defp insert_row(block, sync_uid, sequence) do
      Repo.insert!(%Brando.Content.TableRow{
        block_id: block.id,
        sync_uid: sync_uid,
        sequence: sequence,
        vars: [%Brando.Content.Var{type: :string, key: "cell", label: %{"en" => "Cell"}, value: sync_uid, sequence: 0}]
      })
    end
  end
end
