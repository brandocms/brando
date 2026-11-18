defmodule BrandoAdmin.IndependentTranslationGalleryTest do
  # A synchronized translation's gallery variable holds the source's gallery
  # (`LockedGalleryVarTest`). Made independent from its form, the translation
  # gets its own copy (`Brando.Translations.make_independent/3`), and the open
  # form takes it: choosing an image afterwards, and saving, change the
  # translation's gallery and leave the source's as it was.
  use Brando.LiveCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Galleries.{Gallery, GalleryObject}
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.Translations
  alias BrandoAdmin.Components.Form.Input.RenderVar

  @placements [:content, :config, :table_row]

  defp album_var(placement),
    do: %{"type" => "gallery", "key" => "album", "label" => %{"en" => "Album"}, "placement" => to_string(placement)}

  defp block_attrs(:table_row, gallery),
    do: %{"table_rows" => [%{"vars" => [Map.put(album_var(:content), "gallery_id", gallery.id)]}]}

  defp block_attrs(placement, gallery), do: %{"vars" => [Map.put(album_var(placement), "gallery_id", gallery.id)]}

  defp module_attrs(:table_row) do
    template = Repo.insert!(%Brando.Content.TableTemplate{uid: Brando.Utils.generate_uid(), name: "Albums"})

    Repo.insert!(%Brando.Content.Var{
      type: :gallery,
      key: "album",
      label: %{"en" => "Album"},
      table_template_id: template.id
    })

    [vars: [], table_template_id: template.id]
  end

  defp module_attrs(placement), do: [vars: [Map.put(album_var(placement), "sequence", 0)]]

  defp gallery(images) do
    Repo.insert!(%Gallery{
      config_target: "default",
      gallery_objects:
        for {image, sequence} <- Enum.with_index(images) do
          %GalleryObject{
            image_id: image.id,
            sequence: sequence,
            creator_id: image.creator_id,
            config: %{"alt" => "Bilde #{sequence}"}
          }
        end
    })
  end

  defp load(id) do
    {:ok, entry} = SyncTest.get_article(%{matches: %{id: id}, preload: Brando.Blueprint.preloads_for(Article)})
    entry
  end

  defp media(id) do
    Repo.all(from(o in GalleryObject, where: o.gallery_id == ^id, order_by: o.sequence, select: {o.image_id, o.config}))
  end

  defp save(view, form_id \\ "#article_form_form") do
    view |> form(form_id) |> render_submit(%{})
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form(form_id) |> render_submit(%{})
    assert_redirect(view, 3_000)
  end

  defp make_independent(view) do
    view |> element(~s(button[phx-click*="make_translation_independent"])) |> render_click()
    _ = :sys.get_state(view.pid)
    render(view)
  end

  describe "a gallery variable" do
    setup %{current_user: user} = c do
      [first, second, third] = for _ <- 1..3, do: Factory.insert(:image, creator: user, status: :processed)
      %{first: first, second: second, third: third, user: user, conn: c.conn}
    end

    for placement <- @placements do
      @tag placement: placement
      test "(#{placement}) gets its own gallery when the translation is made independent", c do
        placement = c.placement
        gallery = gallery([c.first, c.second])

        {:ok, module} =
          Brando.Content.create_module(
            Factory.params_for(
              :module,
              [name: %{"en" => "Album"}, namespace: %{"en" => "Content"}, help_text: %{}, code: "<div></div>", refs: []] ++
                module_attrs(placement)
            ),
            c.user
          )

        {:ok, source} =
          SyncTest.create_article(
            %{title: "Album", slug: "album", language: "no", status: "published", year: 2020},
            c.user
          )

        block =
          %Block{}
          |> Block.recursive_block_changeset(
            Map.merge(
              %{
                "uid" => Brando.Utils.generate_uid(),
                "type" => "module",
                "module_id" => module.id,
                "creator_id" => c.user.id,
                "source" => to_string(Article.Blocks)
              },
              block_attrs(placement, gallery)
            ),
            c.user
          )
          |> Repo.insert!()

        struct(Article.Blocks, %{entry_id: source.id, block_id: block.id, sequence: 0}) |> Repo.insert!()
        {:ok, target} = Translations.create_target(Article, source.id, :en, c.user)
        Translations.source_saved(load(source.id))

        stored = fn ->
          [%{block: block}] = load(target.id).entry_blocks
          [var] = block.vars ++ Enum.flat_map(block.table_rows, & &1.vars)
          var.gallery_id
        end

        open = fn ->
          {view, _html} = live_form(c.conn, "/admin/articles/update/#{target.id}", "article_form")
          await_selector(view, "[data-block-uid]")

          if placement == :config do
            [%{block: %{uid: uid}}] = load(target.id).entry_blocks
            view |> element(~s(button.menu-item[phx-click="open_block_config"][phx-value-uid="#{uid}"])) |> render_click()
          end

          await_selector(view, ~s([id$="-gallery-media"]))
          view
        end

        var_assigns = fn view ->
          {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
          Enum.find(components, &(&1.module == RenderVar and &1.assigns[:type] == :gallery)).assigns
        end

        # Saved with the source's changes, as an editor does: the variable
        # stores the source's gallery
        view = open.()
        await_selector(view, "input[name='translation_review[version_id]']")
        save(view)
        assert stored.() == gallery.id
        before = media(gallery.id)

        view = open.()
        make_independent(view)

        # Its own copy, with the same media, order and captions
        own = stored.()
        refute own == gallery.id
        assert media(own) == before
        # The open form takes it
        assert var_assigns.(view).gallery_id == own

        # Choosing an image changes the translation's gallery only
        view
        |> with_target(var_assigns.(view).myself.cid)
        |> render_click("select_image", %{"id" => to_string(c.third.id)})

        assert c.third.id in Enum.map(media(own), &elem(&1, 0))
        assert media(gallery.id) == before

        # And the save keeps it
        save(view)
        assert stored.() == own
        assert media(gallery.id) == before
      end
    end
  end

  describe "a page's own gallery variable" do
    test "gets its own gallery when the translation is made independent", %{conn: conn, current_user: user} do
      put_test_env(Brando.Pages.Page, translatable: [mode: :synchronized])
      [first, second, third] = for _ <- 1..3, do: Factory.insert(:image, creator: user, status: :processed)
      gallery = gallery([first, second])
      source = Factory.insert(:page, title: "Om oss", uri: "om-oss", language: :no, creator: user)

      Repo.insert!(%Brando.Content.Var{
        type: :gallery,
        key: "album",
        label: %{"en" => "Album"},
        page_id: source.id,
        gallery_id: gallery.id
      })

      {:ok, target} = Translations.create_target(Brando.Pages.Page, source.id, :en, user)
      {:ok, _} = Brando.Pages.update_page(source.id, %{title: "Om oss, endret"}, user)

      stored = fn ->
        Repo.one(from(v in Brando.Content.Var, where: v.page_id == ^target.id and v.key == "album", select: v.gallery_id))
      end

      open = fn ->
        {view, _html} = live_form(conn, "/admin/pages/update/#{target.id}")
        await_selector(view, "#page_form_form")
        view
      end

      var_assigns = fn view ->
        {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
        Enum.find(components, &(&1.module == RenderVar and &1.assigns[:type] == :gallery)).assigns
      end

      view = open.()
      await_selector(view, "input[name='translation_review[version_id]']")
      save(view, "#page_form_form")
      assert stored.() == gallery.id
      before = media(gallery.id)

      view = open.()
      make_independent(view)

      own = stored.()
      refute own == gallery.id
      assert media(own) == before
      assert var_assigns.(view).gallery_id == own

      view |> with_target(var_assigns.(view).myself.cid) |> render_click("select_image", %{"id" => to_string(third.id)})
      assert third.id in Enum.map(media(own), &elem(&1, 0))
      assert media(gallery.id) == before

      save(view, "#page_form_form")
      assert stored.() == own
      assert media(gallery.id) == before
    end
  end

  describe "Make source" do
    test "keeps the group on the gallery it shares: the others follow the new source", %{conn: conn, current_user: user} do
      [first, second] = for _ <- 1..2, do: Factory.insert(:image, creator: user, status: :processed)
      gallery = gallery([first, second])

      {:ok, module} =
        Brando.Content.create_module(
          Factory.params_for(
            :module,
            [name: %{"en" => "Album"}, namespace: %{"en" => "Content"}, help_text: %{}, code: "<div></div>", refs: []] ++
              module_attrs(:content)
          ),
          user
        )

      {:ok, source} =
        SyncTest.create_article(%{title: "Album", slug: "album", language: "no", status: "published", year: 2020}, user)

      block =
        %Block{}
        |> Block.recursive_block_changeset(
          Map.merge(
            %{
              "uid" => Brando.Utils.generate_uid(),
              "type" => "module",
              "module_id" => module.id,
              "creator_id" => user.id,
              "source" => to_string(Article.Blocks)
            },
            block_attrs(:content, gallery)
          ),
          user
        )
        |> Repo.insert!()

      struct(Article.Blocks, %{entry_id: source.id, block_id: block.id, sequence: 0}) |> Repo.insert!()
      {:ok, target} = Translations.create_target(Article, source.id, :en, user)
      Translations.source_saved(load(source.id))

      {view, _html} = live_form(conn, "/admin/articles/update/#{target.id}", "article_form")
      await_selector(view, "input[name='translation_review[version_id]']")
      save(view)

      {view, _html} = live_form(conn, "/admin/articles/update/#{target.id}", "article_form")
      await_selector(view, ~s([id$="-gallery-media"]))
      count = Repo.aggregate(Gallery, :count)

      view |> element(~s(button[phx-click*="make_translation_source"])) |> render_click()
      _ = :sys.get_state(view.pid)
      render(view)

      {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)

      assert Enum.find(components, &(&1.module == RenderVar and &1.assigns[:type] == :gallery)).assigns.gallery_id ==
               gallery.id

      assert Repo.aggregate(Gallery, :count) == count
    end
  end

  describe "a gallery variable whose source chose another gallery since the translation was saved" do
    test "keeps the media the form shows, in a gallery of its own", %{conn: conn, current_user: user} do
      [first, second, third] = for _ <- 1..3, do: Factory.insert(:image, creator: user, status: :processed)
      gallery = gallery([first, second])

      {:ok, module} =
        Brando.Content.create_module(
          Factory.params_for(
            :module,
            [name: %{"en" => "Album"}, namespace: %{"en" => "Content"}, help_text: %{}, code: "<div></div>", refs: []] ++
              module_attrs(:content)
          ),
          user
        )

      {:ok, source} =
        SyncTest.create_article(%{title: "Album", slug: "album", language: "no", status: "published", year: 2020}, user)

      block =
        %Block{}
        |> Block.recursive_block_changeset(
          Map.merge(
            %{
              "uid" => Brando.Utils.generate_uid(),
              "type" => "module",
              "module_id" => module.id,
              "creator_id" => user.id,
              "source" => to_string(Article.Blocks)
            },
            block_attrs(:content, gallery)
          ),
          user
        )
        |> Repo.insert!()

      struct(Article.Blocks, %{entry_id: source.id, block_id: block.id, sequence: 0}) |> Repo.insert!()
      {:ok, target} = Translations.create_target(Article, source.id, :en, user)
      Translations.source_saved(load(source.id))

      stored = fn id ->
        [%{block: block}] = load(id).entry_blocks
        hd(block.vars).gallery_id
      end

      {view, _html} = live_form(conn, "/admin/articles/update/#{target.id}", "article_form")
      await_selector(view, "input[name='translation_review[version_id]']")
      save(view)
      assert stored.(target.id) == gallery.id

      # The source's variable now holds another gallery; the translation's
      # pending version brings it into the form
      newer = gallery([third])
      [%{block: source_block}] = load(source.id).entry_blocks

      Repo.update_all(from(v in Brando.Content.Var, where: v.id == ^hd(source_block.vars).id),
        set: [gallery_id: newer.id]
      )

      Translations.source_saved(load(source.id))

      {view, _html} = live_form(conn, "/admin/articles/update/#{target.id}", "article_form")
      await_selector(view, "input[name='translation_review[version_id]']")
      await_selector(view, ~s([id$="-gallery-media"]))
      {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
      shown = Enum.find(components, &(&1.module == RenderVar and &1.assigns[:type] == :gallery)).assigns.gallery_id
      assert shown == newer.id
      make_independent(view)

      {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
      own = Enum.find(components, &(&1.module == RenderVar and &1.assigns[:type] == :gallery)).assigns.gallery_id
      # A copy of what the form shows, not the gallery the source holds now
      refute own in [gallery.id, newer.id]
      assert Enum.map(media(own), &elem(&1, 0)) == [third.id]

      save(view)
      assert stored.(target.id) == own
      assert stored.(source.id) == newer.id
      assert Enum.map(media(newer.id), &elem(&1, 0)) == [third.id]
    end
  end

  # A synchronized Article whose block has a gallery variable at `placement`,
  # and its translation, saved as an editor does: its variable stores the
  # source's gallery
  defp synchronized_album(conn, user, placement, gallery) do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(
          :module,
          [name: %{"en" => "Album"}, namespace: %{"en" => "Content"}, help_text: %{}, code: "<div></div>", refs: []] ++
            module_attrs(placement)
        ),
        user
      )

    {:ok, source} =
      SyncTest.create_article(%{title: "Album", slug: "album", language: "no", status: "published", year: 2020}, user)

    add_album_block(source, module, user, placement, gallery, 0)
    {:ok, target} = Translations.create_target(Article, source.id, :en, user)
    Translations.source_saved(load(source.id))

    {view, _html} = live_form(conn, "/admin/articles/update/#{target.id}", "article_form")
    await_selector(view, "input[name='translation_review[version_id]']")
    save(view)

    %{source: source, target: target, module: module}
  end

  defp add_album_block(article, module, user, placement, gallery, sequence) do
    block =
      %Block{}
      |> Block.recursive_block_changeset(
        Map.merge(
          %{
            "uid" => Brando.Utils.generate_uid(),
            "type" => "module",
            "module_id" => module.id,
            "creator_id" => user.id,
            "source" => to_string(Article.Blocks)
          },
          block_attrs(placement, gallery)
        ),
        user
      )
      |> Repo.insert!()

    struct(Article.Blocks, %{entry_id: article.id, block_id: block.id, sequence: sequence}) |> Repo.insert!()
  end

  defp gallery_ids(id) do
    for %{block: block} <- load(id).entry_blocks, var <- block.vars, do: var.gallery_id
  end

  defp gallery_var(view) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    Enum.find(components, &(&1.module == RenderVar and &1.assigns[:type] == :gallery)).assigns
  end

  describe "a gallery variable in a settings dialog that is closed at Make independent" do
    setup %{conn: conn, current_user: user} do
      [first, second, third] = for _ <- 1..3, do: Factory.insert(:image, creator: user, status: :processed)
      gallery = gallery([first, second])
      Map.merge(synchronized_album(conn, user, :config, gallery), %{gallery: gallery, third: third})
    end

    defp open_closed(c) do
      {view, _html} = live_form(c.conn, "/admin/articles/update/#{c.target.id}", "article_form")
      await_selector(view, "[data-block-uid]")
      view
    end

    defp open_dialog(view, c) do
      [%{block: %{uid: uid}}] = load(c.target.id).entry_blocks
      view |> element(~s(button.menu-item[phx-click="open_block_config"][phx-value-uid="#{uid}"])) |> render_click()
      await_selector(view, ~s([id$="-gallery-media"]))
      view
    end

    test "choosing an image once the dialog is open changes the translation's gallery only", c do
      before = media(c.gallery.id)
      view = open_closed(c)
      make_independent(view)
      [own] = gallery_ids(c.target.id)
      refute own == c.gallery.id

      view = open_dialog(view, c)
      view |> with_target(gallery_var(view).myself.cid) |> render_click("select_image", %{"id" => to_string(c.third.id)})

      assert media(c.gallery.id) == before
      assert c.third.id in Enum.map(media(own), &elem(&1, 0))

      save(view)
      assert gallery_ids(c.target.id) == [own]
    end

    test "a save without opening it leaves the translation on a gallery of its own", c do
      before = media(c.gallery.id)
      view = open_closed(c)
      make_independent(view)
      save(view)

      [own] = gallery_ids(c.target.id)
      refute own == c.gallery.id
      assert media(own) == before
      assert gallery_ids(c.source.id) == [c.gallery.id]
    end
  end

  describe "a gallery variable the translation has not saved yet" do
    test "gets a copy when the translation is made independent", %{conn: conn, current_user: user} do
      [first, second, third] = for _ <- 1..3, do: Factory.insert(:image, creator: user, status: :processed)
      gallery = gallery([first])
      c = synchronized_album(conn, user, :content, gallery)

      # The source adds a block with another gallery after the translation was saved
      added = gallery([second, third])
      add_album_block(c.source, c.module, user, :content, added, 1)
      Translations.source_saved(load(c.source.id))

      {view, _html} = live_form(conn, "/admin/articles/update/#{c.target.id}", "article_form")
      await_selector(view, "input[name='translation_review[version_id]']")
      await_selector(view, ~s([id$="-gallery-media"]))
      make_independent(view)
      save(view)

      [_, added_copy] = ids = gallery_ids(c.target.id)
      refute Enum.any?(ids, &(&1 in [gallery.id, added.id]))
      assert gallery_ids(c.source.id) == [gallery.id, added.id]
      assert Enum.map(media(added_copy), &elem(&1, 0)) == [second.id, third.id]
    end
  end

  describe "a gallery block that shows the source's gallery" do
    test "gets a copy, and the editor is told to open the translation again", %{conn: conn, current_user: user} do
      [first] = for _ <- 1..1, do: Factory.insert(:image, creator: user, status: :processed)
      c = synchronized_album(conn, user, :content, gallery([first]))
      slides = gallery([first])

      # As a source save leaves a gallery ref it added after the translation
      # was created (`Mutations.duplicate_refs/1` keeps its gallery)
      for id <- [c.source.id, c.target.id] do
        [%{block: block}] = load(id).entry_blocks

        Repo.insert!(%Brando.Content.Ref{
          block_id: block.id,
          name: "slides",
          uid: Brando.Utils.generate_uid(),
          gallery_id: slides.id,
          data: %Brando.Villain.Blocks.GalleryBlock{type: "gallery", data: %Brando.Villain.Blocks.GalleryBlock.Data{}}
        })
      end

      {view, _html} = live_form(conn, "/admin/articles/update/#{c.target.id}", "article_form")
      await_selector(view, "[data-block-uid]")
      Brando.endpoint().subscribe("user:#{user.id}")
      make_independent(view)

      notice =
        Gettext.dgettext(
          Brando.Gettext,
          "default",
          "Open the translation again before you change the media in its gallery blocks."
        )

      assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: ^notice}}, 2_000

      [%{block: block}] = load(c.target.id).entry_blocks
      refute hd(block.refs).gallery_id == slides.id
    end
  end
end
