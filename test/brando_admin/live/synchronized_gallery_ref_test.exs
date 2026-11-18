defmodule BrandoAdmin.SynchronizedGalleryRefTest do
  # A gallery ref belongs to its translation: creating a translation copies
  # every gallery (`Mutations.clone_galleries/3`), and a ref that a source
  # save adds later gets a copy too. The pending version carries the source's
  # gallery as an unsaved copy (`Brando.Translations.Sync`), which the
  # translation's save inserts as its own. Its media then follow the source,
  # and Make independent has nothing of the source's left to copy, so the open
  # form can go on editing the gallery.
  use Brando.LiveCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Content.Ref
  alias Brando.Galleries.Gallery
  alias Brando.Galleries.GalleryObject
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.Translations
  alias BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock

  @notice "Open the translation again before you change the media in its gallery blocks."

  setup %{conn: conn, current_user: user} do
    [first, second, third] = for _ <- 1..3, do: Factory.insert(:image, creator: user, status: :processed)

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Slides"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: "{% ref refs.slides %}",
          refs: [%{name: "slides", uid: Brando.Utils.generate_uid(), data: %{type: "gallery", data: %{}}}],
          vars: []
        ),
        user
      )

    {:ok, source} =
      SyncTest.create_article(%{title: "Album", slug: "album", language: "no", status: "published", year: 2020}, user)

    {:ok, target} = Translations.create_target(Article, source.id, :en, user)

    # A source save adds a block with a gallery ref
    slides = gallery([first, second])
    add_slides_block(source, module, user, slides)
    Translations.source_saved(load(source.id))

    %{
      conn: conn,
      user: user,
      source: source,
      target: target,
      slides: slides,
      first: first,
      second: second,
      third: third
    }
  end

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

  defp add_slides_block(article, module, user, gallery) do
    block =
      %Block{}
      |> Block.recursive_block_changeset(
        %{
          "uid" => Brando.Utils.generate_uid(),
          "type" => "module",
          "module_id" => module.id,
          "creator_id" => user.id,
          "source" => to_string(Article.Blocks),
          "refs" => [
            %{
              "uid" => Brando.Utils.generate_uid(),
              "name" => "slides",
              "gallery_id" => gallery.id,
              "data" => %{"type" => "gallery", "data" => %{}}
            }
          ]
        },
        user
      )
      |> Repo.insert!()

    struct(Article.Blocks, %{entry_id: article.id, block_id: block.id, sequence: 0}) |> Repo.insert!()
  end

  defp load(id) do
    {:ok, entry} = SyncTest.get_article(%{matches: %{id: id}, preload: Brando.Blueprint.preloads_for(Article)})
    entry
  end

  defp ref_gallery_id(id) do
    [%{block: block}] = load(id).entry_blocks
    [ref] = block.refs
    ref.gallery_id
  end

  defp media(id) do
    Repo.all(from(o in GalleryObject, where: o.gallery_id == ^id, order_by: o.sequence, select: {o.image_id, o.config}))
  end

  defp open(c) do
    {view, _html} = live_form(c.conn, "/admin/articles/update/#{c.target.id}", "article_form")
    await_selector(view, "[data-block-uid]")
    view
  end

  defp save(view, form_id \\ "#article_form_form") do
    view |> form(form_id) |> render_submit(%{})
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form(form_id) |> render_submit(%{})
    assert_redirect(view, 3_000)
  end

  # Opened with the pending version and saved, as an editor does
  defp save_pending(c) do
    view = open(c)
    await_selector(view, "input[name='translation_review[version_id]']")
    save(view)
  end

  defp gallery_block(view) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    Enum.find(components, &(&1.module == GalleryBlock)).assigns
  end

  test "the translation's save gives the ref its own gallery, with the source's media", c do
    before = media(c.slides.id)
    save_pending(c)

    own = ref_gallery_id(c.target.id)
    refute own in [nil, c.slides.id]
    assert media(own) == before
    assert ref_gallery_id(c.source.id) == c.slides.id
    assert media(c.slides.id) == before
    assert Translations.shared_galleries(Article, c.target.id) == []
  end

  test "the translation's copy follows a later change to the source's gallery", c do
    save_pending(c)
    own = ref_gallery_id(c.target.id)

    # The source's gallery gains an image and loses one
    Repo.delete_all(from(o in GalleryObject, where: o.gallery_id == ^c.slides.id and o.image_id == ^c.first.id))

    Repo.insert!(%GalleryObject{
      gallery_id: c.slides.id,
      image_id: c.third.id,
      sequence: 2,
      creator_id: c.user.id
    })

    Translations.source_saved(load(c.source.id))
    save_pending(c)

    assert ref_gallery_id(c.target.id) == own
    assert Enum.map(media(own), &elem(&1, 0)) == [c.second.id, c.third.id]
    assert Enum.map(media(c.slides.id), &elem(&1, 0)) == [c.second.id, c.third.id]
  end

  test "Make independent needs no reopen, and the open form edits the translation's gallery", c do
    save_pending(c)
    own = ref_gallery_id(c.target.id)
    before = media(c.slides.id)

    view = open(c)
    Brando.endpoint().subscribe("user:#{c.user.id}")
    view |> element(~s(button[phx-click*="make_translation_independent"])) |> render_click()
    _ = :sys.get_state(view.pid)

    notice = Gettext.dgettext(Brando.Gettext, "default", @notice)
    refute_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: ^notice}}, 500
    assert ref_gallery_id(c.target.id) == own

    # Choosing an image in the gallery block, and saving, change the
    # translation's gallery only
    view
    |> with_target(gallery_block(view).myself.cid)
    |> render_click("select_image", %{"id" => to_string(c.third.id)})

    save(view)

    assert ref_gallery_id(c.target.id) == own
    assert Enum.map(media(own), &elem(&1, 0)) == [c.first.id, c.second.id, c.third.id]
    assert media(c.slides.id) == before
  end

  test "a ref of the translation without a gallery gets a copy when the source's has one", c do
    save_pending(c)
    [%{block: %{refs: [ref]}}] = load(c.target.id).entry_blocks
    Repo.update_all(from(r in Ref, where: r.id == ^ref.id), set: [gallery_id: nil])

    Translations.source_saved(load(c.source.id))
    save_pending(c)

    own = ref_gallery_id(c.target.id)
    refute own in [nil, c.slides.id]
    assert media(own) == media(c.slides.id)
  end

  test "a pending version stored with the source's gallery on a new ref saves a copy too", c do
    # As versions computed before `Sync` gave such a ref a copy hold it
    version = Repo.one!(from(v in Brando.Translations.PendingVersion, where: v.status == :pending))
    payload = Translations.decode_payload(version)
    [%{block: %{refs: [ref]} = block} = join] = payload.entry_blocks
    {:ok, slides} = Brando.Galleries.get_gallery(%{matches: %{id: c.slides.id}, preload: [gallery_objects: [:image]]})
    shared = %{ref | gallery_id: slides.id, gallery: slides}
    payload = %{payload | entry_blocks: [%{join | block: %{block | refs: [shared]}}]}

    Repo.update_all(from(v in Brando.Translations.PendingVersion, where: v.id == ^version.id),
      set: [payload: Brando.Utils.term_to_binary(payload)]
    )

    save_pending(c)

    own = ref_gallery_id(c.target.id)
    refute own in [nil, c.slides.id]
    assert media(own) == media(c.slides.id)
  end

  test "the copy of a gallery in the trash is not in the trash", c do
    # Trashed while the source's ref still shows it
    Repo.update_all(from(g in Gallery, where: g.id == ^c.slides.id), set: [deleted_at: DateTime.utc_now()])
    Translations.source_saved(load(c.source.id))
    save_pending(c)

    own = ref_gallery_id(c.target.id)
    refute own in [nil, c.slides.id]
    assert is_nil(Repo.get!(Gallery, own).deleted_at)
  end
end
