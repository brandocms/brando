defmodule Brando.Translations.SharedGalleriesTest do
  # A synchronized translation shows the source's gallery records: its gallery
  # variables and assets point at them (`Brando.Translations.Sync`). Made
  # independent, it gets its own copy of each, so an edit there no longer
  # reaches the source and the other translations.
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Content.Ref
  alias Brando.Content.Var
  alias Brando.Factory
  alias Brando.Galleries
  alias Brando.Galleries.Gallery
  alias Brando.Galleries.GalleryObject
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.Translations

  setup do
    user = Factory.insert(:random_user)
    [first, second, third] = for _ <- 1..3, do: Factory.insert(:image, creator: user, status: :processed)

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Album"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: "<div></div>",
          refs: [%{name: "slides", uid: Brando.Utils.generate_uid(), data: %{type: "gallery", data: %{}}}],
          vars: [%{"type" => "gallery", "key" => "album", "label" => %{"en" => "Album"}, "sequence" => 0}]
        ),
        user
      )

    album = gallery([first, second], captions: true)
    slides = gallery([second, first])
    photos = gallery([first])

    {:ok, source} =
      SyncTest.create_article(
        %{title: "Album", slug: "album", language: "no", status: "published", year: 2020},
        user
      )

    Repo.update_all(from(a in Article, where: a.id == ^source.id), set: [photos_id: photos.id])

    block =
      %Block{}
      |> Block.recursive_block_changeset(
        %{
          "uid" => Brando.Utils.generate_uid(),
          "type" => "module",
          "module_id" => module.id,
          "creator_id" => user.id,
          "source" => to_string(Article.Blocks),
          "vars" => [%{"type" => "gallery", "key" => "album", "label" => %{"en" => "Album"}, "gallery_id" => album.id}],
          "refs" => [
            %{"uid" => Brando.Utils.generate_uid(), "name" => "slides", "data" => %{"type" => "gallery", "data" => %{}}}
          ]
        },
        user
      )
      |> Repo.insert!()

    Repo.update_all(from(r in Ref, where: r.block_id == ^block.id), set: [gallery_id: slides.id])
    struct(Article.Blocks, %{entry_id: source.id, block_id: block.id, sequence: 0}) |> Repo.insert!()

    {:ok, target} = Translations.create_target(Article, source.id, :en, user)

    %{user: user, source: source, target: target, album: album, slides: slides, photos: photos, third: third}
  end

  defp gallery(images, opts \\ []) do
    Repo.insert!(%Gallery{
      config_target: "default",
      gallery_objects:
        for {image, sequence} <- Enum.with_index(images) do
          config = if opts[:captions], do: %{"caption" => %{"no" => "Bilde #{sequence}"}}, else: %{}
          %GalleryObject{image_id: image.id, sequence: sequence, config: config, creator_id: image.creator_id}
        end
    })
  end

  defp load(id) do
    {:ok, entry} = SyncTest.get_article(%{matches: %{id: id}, preload: Brando.Blueprint.preloads_for(Article)})
    entry
  end

  defp block(entry), do: entry |> load_blocks() |> List.first()
  defp load_blocks(%{id: id}), do: Enum.map(load(id).entry_blocks, & &1.block)

  defp var_gallery_id(entry), do: block(entry).vars |> Enum.find(&(&1.key == "album")) |> Map.fetch!(:gallery_id)
  defp ref_gallery_id(entry), do: block(entry).refs |> Enum.find(&(&1.name == "slides")) |> Map.fetch!(:gallery_id)
  defp photos_id(%{id: id}), do: Repo.get!(Article, id).photos_id

  # Media and per-object config, in order
  defp contents(gallery_id) do
    Repo.all(
      from(o in GalleryObject,
        where: o.gallery_id == ^gallery_id,
        order_by: o.sequence,
        select: {o.image_id, o.video_id, o.config}
      )
    )
  end

  # What a saved synchronized translation can hold: the source's gallery for
  # its variable (`Sync` gives it the source's `gallery_id`, and the admin's
  # save writes it), for its gallery asset when it is saved from the pending
  # version outside the form (the form keeps the asset's own record), and for
  # a gallery ref a source save added after the translation was created.
  defp share_with_source(c) do
    Repo.update_all(from(a in Article, where: a.id == ^c.target.id), set: [photos_id: c.photos.id])

    for %Var{key: "album", id: id} <- block(c.target).vars,
        do: Repo.update_all(from(v in Var, where: v.id == ^id), set: [gallery_id: c.album.id])

    for %Ref{name: "slides", id: id} <- block(c.target).refs,
        do: Repo.update_all(from(r in Ref, where: r.id == ^id), set: [gallery_id: c.slides.id])

    assert var_gallery_id(c.target) == c.album.id
    assert ref_gallery_id(c.target) == c.slides.id
    assert photos_id(c.target) == c.photos.id
  end

  test "a source save points the translation's gallery variable and gallery asset at the source's galleries", c do
    Translations.source_saved(load(c.source.id))
    payload = c.target |> pending() |> Translations.decode_payload()

    [%{block: block}] = payload.entry_blocks
    assert Enum.find(block.vars, &(&1.key == "album")).gallery_id == c.album.id
    assert payload.photos_id == c.photos.id
  end

  describe "make_independent" do
    setup c do
      share_with_source(c)
      :ok
    end

    test "gives each shared gallery a copy with the same media, order and captions", c do
      {:ok, _} = Translations.make_independent(Article, c.target.id, c.user)

      for {gallery, now} <- [
            {c.album, var_gallery_id(c.target)},
            {c.slides, ref_gallery_id(c.target)},
            {c.photos, photos_id(c.target)}
          ] do
        refute now == gallery.id
        assert contents(now) == contents(gallery.id)
      end

      # The source keeps its galleries
      assert var_gallery_id(c.source) == c.album.id
      assert ref_gallery_id(c.source) == c.slides.id
      assert photos_id(c.source) == c.photos.id
      assert Translations.shared_galleries(Article, c.target.id) == []
    end

    test "editing the translation's gallery afterwards leaves the source's as it was", c do
      before = contents(c.album.id)
      {:ok, _} = Translations.make_independent(Article, c.target.id, c.user)
      {:ok, copy} = Galleries.get_gallery(%{matches: %{id: var_gallery_id(c.target)}, preload: [:gallery_objects]})

      objects =
        Enum.map(copy.gallery_objects, &Galleries.slim_gallery_object/1) ++
          [%{image_id: c.third.id, sequence: 2, creator_id: c.user.id}]

      {:ok, _} = Galleries.save_gallery(copy, %{gallery_objects: objects}, c.user)

      assert length(contents(copy.id)) == 3
      assert contents(c.album.id) == before
    end
  end

  test "each holder gets its own copy, two that showed one gallery included", c do
    share_with_source(c)
    # A second gallery variable of the translation shows the same gallery
    [%{id: block_id} | _] = load_blocks(c.target)

    Repo.insert!(%Var{
      type: :gallery,
      key: "extra",
      label: %{"en" => "Extra"},
      block_id: block_id,
      gallery_id: c.album.id
    })

    {:ok, _} = Translations.make_independent(Article, c.target.id, c.user)

    ids = for %Var{type: :gallery, gallery_id: id} <- block(c.target).vars, do: id
    assert length(ids) == 2
    assert length(Enum.uniq(ids)) == 2
    refute c.album.id in ids
  end

  test "a gallery in the trash does not stop make_independent", c do
    share_with_source(c)
    Repo.update_all(from(g in Gallery, where: g.id == ^c.slides.id), set: [deleted_at: DateTime.utc_now()])

    assert {:ok, _} = Translations.make_independent(Article, c.target.id, c.user)
    assert ref_gallery_id(c.target) == c.slides.id
    refute var_gallery_id(c.target) == c.album.id
  end

  test "a save of an independent translation that points back at the source's gallery gets a copy again", c do
    {:ok, _} = Translations.make_independent(Article, c.target.id, c.user)
    # A form opened before, or a restored revision, writes the source's gallery
    share_with_source(c)

    Translations.source_saved(load(c.target.id))

    refute var_gallery_id(c.target) == c.album.id
    refute photos_id(c.target) == c.photos.id
    assert contents(var_gallery_id(c.target)) == contents(c.album.id)
    assert var_gallery_id(c.source) == c.album.id
  end

  test "make_independent copies nothing for a translation whose galleries are already its own", c do
    # Never saved since it was created: the copy's galleries are its own
    count = Repo.aggregate(Gallery, :count)

    {:ok, _} = Translations.make_independent(Article, c.target.id, c.user)

    assert Repo.aggregate(Gallery, :count) == count
  end

  test "transfer_source keeps the group on one set of galleries: both follow the new source", c do
    share_with_source(c)
    count = Repo.aggregate(Gallery, :count)

    {:ok, _} = Translations.transfer_source(Article, c.target.id, c.user)

    assert Repo.aggregate(Gallery, :count) == count
    assert var_gallery_id(c.target) == c.album.id
  end

  test "split_shared_galleries repairs a translation made independent without copies", c do
    share_with_source(c)
    # As make_independent left it before it copied galleries
    Repo.update_all(
      from(m in Brando.Translations.Member, where: m.entry_id == ^c.target.id and m.entry_type == ^to_string(Article)),
      set: [synchronized: false]
    )

    assert c.target.id |> then(&Translations.shared_galleries(Article, &1)) |> Enum.map(&elem(&1, 3)) |> Enum.sort() ==
             Enum.sort([c.album.id, c.slides.id, c.photos.id])

    assert {:ok, copies} = Translations.split_shared_galleries(Article, c.target.id, c.user)
    assert length(copies) == 3
    assert Translations.shared_galleries(Article, c.target.id) == []
    assert contents(var_gallery_id(c.target)) == contents(c.album.id)
  end

  describe "the doctor's Translation galleries check" do
    alias Brando.Doctor.Checks.TranslationGalleries
    alias Brando.Doctor.Context
    alias Brando.Doctor.Result

    defp doctor, do: TranslationGalleries.run(Context.new(locale: "en", environments: [{nil, nil}]))

    test "passes while the translation follows the source, and after Make independent", c do
      share_with_source(c)
      assert %Result{status: :ok} = doctor()

      {:ok, _} = Translations.make_independent(Article, c.target.id, c.user)
      assert %Result{status: :ok} = doctor()
    end

    test "lists an independent translation that shares a gallery, until it is split", c do
      share_with_source(c)

      Repo.update_all(
        from(m in Brando.Translations.Member, where: m.entry_id == ^c.target.id and m.entry_type == ^to_string(Article)),
        set: [synchronized: false]
      )

      result = doctor()
      assert result.status == :warning
      assert result.summary == "1 independent translation shares a gallery with another language version"
      assert result.items == ["Brando.SyncTest.Article ##{c.target.id} (en)"]
      assert result.fix =~ "mix brando.translations.split_galleries"

      # As the mix task and the release run it
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert {:ok, 1} = Brando.Translations.SharedGalleries.repair()
        end)

      assert output =~ "Brando.SyncTest.Article ##{c.target.id} (en): 3 gallery copies"
      assert %Result{status: :ok} = doctor()
      assert contents(var_gallery_id(c.target)) == contents(c.album.id)
      assert {:ok, 0} = Brando.Translations.SharedGalleries.repair()
    end

    test "leaves out a member whose entry is gone", c do
      Repo.insert!(%Brando.Translations.Member{
        group_id: Translations.get_member(Article, c.source.id).group_id,
        entry_type: to_string(Article),
        entry_id: c.target.id + 10_000,
        language: "sv",
        role: :target,
        synchronized: false
      })

      assert %Result{status: :ok} = doctor()
    end
  end

  defp pending(entry) do
    member = Translations.get_member(Article, entry.id)
    Translations.current_pending_for_member(member.id)
  end
end
