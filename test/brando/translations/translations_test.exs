defmodule Brando.TranslationsTest do
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Factory
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.TranslationFixtures
  alias Brando.Translations
  alias Brando.Translations.PendingVersion

  setup do
    user = Factory.insert(:random_user)

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
        %{
          title: "Tittel",
          slug: "tittel",
          language: "no",
          status: "published",
          year: 2020,
          items: [%{label: "Første punkt", link: "/a"}]
        },
        user
      )

    TranslationFixtures.add_block(source, module, user, "Første avsnitt", 0)
    TranslationFixtures.add_block(source, module, user, "Andre avsnitt", 1)

    %{user: user, module: module, source: source}
  end

  defp add_raw_block(article, c, params, sequence) do
    params =
      Map.merge(
        %{
          "uid" => Brando.Utils.generate_uid(),
          "type" => "module",
          "module_id" => c.module.id,
          "creator_id" => c.user.id,
          "source" => to_string(Article.Blocks)
        },
        params
      )

    block = %Block{} |> Block.recursive_block_changeset(params, c.user) |> Repo.insert!()
    struct(Article.Blocks, %{entry_id: article.id, block_id: block.id, sequence: sequence}) |> Repo.insert!()
    block
  end

  defp identifier_id!(entry) do
    case Brando.Content.get_identifier(Article, entry) do
      {:ok, identifier} -> identifier.id
      _ -> entry |> then(&Brando.Content.create_identifier(Article, &1)) |> elem(1) |> Map.fetch!(:id)
    end
  end

  # An editor's save of a translation, as the admin form makes it: the editor
  # reports the save with `target_saved/3`, so the mutation queues no
  # recompute of its own.
  defp editor_save(id, params, user) do
    id
    |> load()
    |> Article.changeset(params, user)
    |> SyncTest.update_article(user, editor_review: true)
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
    target = load(target.id)

    target.entry_blocks
    |> Enum.zip(texts)
    |> Enum.each(fn {join, text} -> set_text(join.block, text) end)
  end

  defp pending(entry) do
    case Translations.get_pending_version(Article, entry.id) do
      nil -> nil
      version -> %{version | work_items: Enum.sort_by(version.work_items, & &1.path)}
    end
  end

  test "a new block gets its uid as sync_uid", c do
    for join <- load(c.source.id).entry_blocks do
      assert join.block.sync_uid == join.block.uid
    end
  end

  test "an ordinary duplicate gets fresh block identities", c do
    {:ok, copy} = SyncTest.duplicate_article(c.source.id, c.user, change_fields: [slug: "copy"])
    source_ids = Enum.map(load(c.source.id).entry_blocks, & &1.block.sync_uid)

    for join <- load(copy.id).entry_blocks do
      refute join.block.sync_uid in source_ids
    end
  end

  test "create_target makes a linked, unpublished copy that keeps sync identities", c do
    assert {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)

    source = load(c.source.id)
    target = load(target.id)

    assert target.language == :en
    assert target.status == :draft
    assert target.slug == "tittel-en"
    # The context's duplicate marks copies; a translation starts from the source's text
    assert target.title == "Tittel"

    assert Enum.map(target.entry_blocks, & &1.block.sync_uid) == Enum.map(source.entry_blocks, & &1.block.sync_uid)
    assert Enum.map(target.entry_blocks, & &1.block.uid) != Enum.map(source.entry_blocks, & &1.block.uid)
    assert Enum.map(target.items, & &1.uid) == Enum.map(source.items, & &1.uid)
    assert [%{id: source_id}] = target.alternate_entries
    assert source_id == source.id

    assert %{role: :source} = Translations.get_member(Article, source.id)
    assert %{role: :target, synchronized: true, language: "en"} = Translations.get_member(Article, target.id)

    assert {:error, :language_exists} = Translations.create_target(Article, c.source.id, :en, c.user)
    assert {:error, :not_source} = Translations.create_target(Article, target.id, :no, c.user)
  end

  test "a language held by an independent alternate is not translated again", c do
    {:ok, english} =
      SyncTest.create_article(%{title: "Title", slug: "title", language: "en", status: "published"}, c.user)

    :ok = Article.Alternate.add(c.source.id, english.id)

    assert {:error, :language_exists} = Translations.create_target(Article, c.source.id, :en, c.user)
    # Refused before the source is enrolled: no group is left behind
    assert Translations.get_member(Article, c.source.id) == nil

    assert {:ok, _} = SyncTest.delete_article(english.id, c.user)
    assert {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
    assert target.language == :en
  end

  test "a shared update that no longer applies is not carried to the next version", c do
    {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)

    {:ok, _} = SyncTest.update_article(c.source.id, %{year: 2024}, c.user)
    assert Enum.any?(pending(target).work_items, &(&1.kind == :shared_update and &1.path == "year"))

    # The source goes back to the translation's value before it was saved
    {:ok, _} = SyncTest.update_article(c.source.id, %{year: 2020}, c.user)
    # Nothing is left to do, so there is no pending version at all
    assert pending(target) == nil
  end

  test "a content transfer that updates a source queues its translations' sync", c do
    {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
    Translations.target_saved(Article, target.id)

    # A transfer writes past the Blueprint's after-save
    Repo.update_all(from(a in Article, where: a.id == ^c.source.id), set: [year: 2031])

    receipt =
      Repo.insert!(%Brando.Content.Transfer.Receipt{
        id: Ecto.UUID.generate(),
        package_id: "test",
        fingerprint: "test",
        scope: "public",
        actor_id: c.user.id,
        before: %{},
        after: %{"field" => %{"schema" => to_string(Article), "id" => c.source.id}},
        mappings: %{}
      })

    Brando.Content.Transfer.refresh_receipt(receipt, c.user)

    assert Enum.any?(pending(target).work_items, &(&1.kind == :shared_update and &1.path == "year"))
    assert Translations.decode_payload(pending(target)).year == 2031
  end

  test "saving the source records pending work without touching the translation", c do
    {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
    translate(target, ["First paragraph", "Second paragraph"])

    [first, _second] = Enum.map(load(c.source.id).entry_blocks, & &1.block)
    set_text(first, "Første avsnitt, endret")
    TranslationFixtures.add_block(c.source, c.module, c.user, "Tredje avsnitt", 2)

    Translations.source_saved(load(c.source.id))

    assert texts(load(target.id)) == ["First paragraph", "Second paragraph"]

    version = pending(target)
    assert %PendingVersion{status: :pending, source_generation: 1} = version

    assert [{:review, first_path}, {:translate, third_path}] =
             Enum.map(version.work_items, &{&1.kind, &1.path}) |> Enum.sort()

    assert first_path =~ ~r"^entry_blocks/.+/refs/body/text$"
    assert third_path =~ ~r"^entry_blocks/.+/refs/body/text$"

    payload = Translations.decode_payload(version)
    assert texts(payload) == ["First paragraph", "Second paragraph", "Tredje avsnitt"]
  end

  test "a later save supersedes the pending version and carries its open work", c do
    {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
    translate(target, ["First paragraph", "Second paragraph"])

    TranslationFixtures.add_block(c.source, c.module, c.user, "Tredje avsnitt", 2)
    Translations.source_saved(load(c.source.id))
    first = pending(target)

    {:ok, _} = SyncTest.update_article(c.source.id, %{year: 2024}, c.user)
    second = pending(target)

    assert second.id != first.id
    assert Repo.get!(PendingVersion, first.id).status == :superseded
    assert Enum.any?(second.work_items, &(&1.kind == :translate))
    assert Enum.any?(second.work_items, &(&1.kind == :shared_update and &1.path == "year"))
    assert Translations.decode_payload(second).year == 2024
    assert load(target.id).year == 2020
  end

  test "a save with nothing new records nothing", c do
    {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
    Translations.source_saved(load(c.source.id))

    assert pending(target) == nil
  end

  describe "saving a translation" do
    # The source changes block 1's text and the shared year: the target gets a
    # review item for block 1 and a shared update for the year.
    defp reviewed_change(c) do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
      translate(target, ["First paragraph", "Second paragraph"])
      [first, _] = Enum.map(load(c.source.id).entry_blocks, & &1.block)
      set_text(first, "Første avsnitt, endret")
      {:ok, _} = SyncTest.update_article(c.source.id, %{year: 2024}, c.user)
      version = pending(target)
      review_path = Enum.find(version.work_items, &(&1.kind == :review)).path
      %{target: target, version: version, review_path: review_path}
    end

    defp open_items(target) do
      case pending(target) do
        nil -> []
        version -> for item <- version.work_items, is_nil(item.resolved_at), do: {item.kind, item.path}
      end
    end

    test "resolves the work the editor completed and applies the version", c do
      %{target: target, version: version} = reviewed_change(c)

      # The editor rewrote block 1 and saved the pending year.
      [first, _] = Enum.map(load(target.id).entry_blocks, & &1.block)
      set_text(first, "First paragraph, revised")
      {:ok, _} = editor_save(target.id, %{year: 2024}, c.user)

      assert {:ok, %{open: 0, stale: false}} =
               Translations.target_saved(Article, target.id, %{version_id: version.id, acknowledged: []})

      assert Repo.get!(PendingVersion, version.id).status == :applied
      assert open_items(target) == []
      assert texts(load(target.id)) == ["First paragraph, revised", "Second paragraph"]
    end

    test "unchanged text stays open until the editor acknowledges it", c do
      %{target: target, version: version, review_path: path} = reviewed_change(c)
      {:ok, _} = editor_save(target.id, %{year: 2024}, c.user)

      assert {:ok, %{open: 1}} = Translations.target_saved(Article, target.id, %{version_id: version.id})
      assert open_items(target) == [{:review, path}]

      assert {:ok, %{open: 0}} =
               Translations.target_saved(Article, target.id, %{
                 version_id: pending(target).id,
                 acknowledged: [path]
               })
    end

    test "saving other fields does not clear the work", c do
      %{target: target, review_path: path} = reviewed_change(c)
      {:ok, _} = editor_save(target.id, %{subtitle: "Unrelated"}, c.user)

      # No reviewed version: an ordinary save, e.g. outside the editor.
      assert {:ok, %{open: 2}} = Translations.target_saved(Article, target.id)
      assert Enum.sort(open_items(target)) == Enum.sort([{:review, path}, {:shared_update, "year"}])
      assert Translations.decode_payload(pending(target)).subtitle == "Unrelated"
    end

    test "work raised by a newer source save stays open, and the save is reported as stale", c do
      %{target: target, version: version, review_path: path} = reviewed_change(c)

      # The source changes block 1 again while the editor works on the version.
      [first, _] = Enum.map(load(c.source.id).entry_blocks, & &1.block)
      set_text(first, "Første avsnitt, endret igjen")
      Translations.source_saved(load(c.source.id))

      [block, _] = Enum.map(load(target.id).entry_blocks, & &1.block)
      set_text(block, "First paragraph, revised")
      {:ok, _} = editor_save(target.id, %{year: 2024}, c.user)

      assert {:ok, %{stale: true}} =
               Translations.target_saved(Article, target.id, %{version_id: version.id, acknowledged: [path]})

      # The review of the first change is done; the second is not.
      assert open_items(target) == [{:review, path}]
      assert pending(target).source_generation == 2
    end

    test "the editor never applies a pending version computed against older content", c do
      %{target: target} = reviewed_change(c)
      before = pending(target)

      # Unchanged: the editor gets the same version, not a recompute
      assert Translations.editor_state(Article, target.id).pending.id == before.id

      # Changed outside the form before the background recompute has run, as a
      # published revision or scheduled release does
      Repo.update_all(from(a in Article, where: a.id == ^target.id), set: [subtitle: "Published revision"])

      %{pending: fresh} = Translations.editor_state(Article, target.id)
      assert fresh.id != before.id
      assert Translations.decode_payload(fresh).subtitle == "Published revision"
    end

    test "an editor's save queues no recompute of its own", c do
      %{target: target, version: version} = reviewed_change(c)

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _} = editor_save(target.id, %{subtitle: "Edited"}, c.user)
        refute_enqueued(worker: Brando.Worker.TranslationSync)
      end)

      assert pending(target).id == version.id
    end

    test "a saved translation is recomputed in the background", c do
      %{target: target} = reviewed_change(c)
      {:ok, _} = SyncTest.update_article(target.id, %{subtitle: "Saved elsewhere"}, c.user)

      assert Translations.decode_payload(pending(target)).subtitle == "Saved elsewhere"
      assert length(open_items(target)) == 2
    end

    test "a save may change text, but not what the source controls", c do
      {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
      target = load(target.id)
      check = &Translations.check_target_save(Article, target.id, &1)

      assert {:ok, _} = check.(Article.changeset(target, %{title: "Title", subtitle: "Own"}, c.user))

      assert {:error, {:source_controlled, ["year"]}} = check.(Article.changeset(target, %{year: 1999}, c.user))

      # Whatever produced it, a save without a block or a subform row changes
      # the structure.
      [first, _second] = target.entry_blocks
      without_block = Ecto.Changeset.change(%{target | entry_blocks: [first]})
      assert {:error, {:source_controlled, ["entry_blocks" | _]}} = check.(without_block)
      assert {:error, {:source_controlled, ["items" | _]}} = check.(Ecto.Changeset.change(%{target | items: []}))

      # The source itself, and entries outside a group, are not restricted.
      source = load(c.source.id)

      assert {:ok, _} =
               Translations.check_target_save(Article, source.id, Article.changeset(source, %{year: 1}, c.user))
    end

    test "the editor state names the source and the pending version", c do
      %{target: target, version: version} = reviewed_change(c)

      assert %{member: %{role: :target}, source: %{id: source_id, language: "no"}, pending: %{id: id}} =
               Translations.editor_state(Article, target.id)

      assert {source_id, id} == {c.source.id, version.id}
      assert %{member: %{role: :source}, pending: nil} = Translations.editor_state(Article, c.source.id)
    end
  end

  describe "listing status" do
    test "a structural update without text work is still pending", c do
      {:ok, en} = Translations.create_target(Article, c.source.id, :en, c.user)
      [_, second] = load(c.source.id).entry_blocks
      Repo.delete!(second)
      Translations.source_saved(load(c.source.id))

      assert [_, %{pending: true, counts: counts}] = Translations.listing_status(Article, [en])[en.id]
      assert counts == %{}
    end

    test "counts each language's open work in one batch", c do
      {:ok, en} = Translations.create_target(Article, c.source.id, :en, c.user)
      translate(en, ["First paragraph", "Second paragraph"])
      [first, _] = Enum.map(load(c.source.id).entry_blocks, & &1.block)
      set_text(first, "Første avsnitt, endret")
      TranslationFixtures.add_block(c.source, c.module, c.user, "Tredje avsnitt", 2)
      Translations.source_saved(load(c.source.id))

      {:ok, loner} =
        SyncTest.create_article(%{title: "Alene", slug: "alene", language: "no", status: "draft"}, c.user)

      status = Translations.listing_status(Article, [c.source, en, loner])

      assert [
               %{language: "no", role: :source, pending: false},
               %{language: "en", role: :target, pending: true, counts: %{translate: 1, review: 1}}
             ] = status[c.source.id]

      assert status[en.id] == status[c.source.id]
      refute Map.has_key?(status, loner.id)

      # Resolved work is not counted.
      en_block = hd(load(en.id).entry_blocks).block
      set_text(en_block, "First paragraph, revised")
      version = Translations.get_pending_version(Article, en.id)
      Translations.target_saved(Article, en.id, %{version_id: version.id})
      assert [_, %{counts: %{translate: 1} = counts}] = Translations.listing_status(Article, [c.source])[c.source.id]
      refute Map.has_key?(counts, :review)

      # An independent translation has no work.
      {:ok, _} = Translations.make_independent(Article, en.id, c.user)
      assert [_, %{synchronized: false, pending: false}] = Translations.listing_status(Article, [en])[en.id]
    end
  end

  test "make_independent stops synchronization and keeps content and links", c do
    {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
    TranslationFixtures.add_block(c.source, c.module, c.user, "Tredje avsnitt", 2)
    Translations.source_saved(load(c.source.id))
    version = pending(target)

    assert {:ok, %{synchronized: false, detached_at: %DateTime{}}} =
             Translations.make_independent(Article, target.id, c.user)

    assert Repo.get!(PendingVersion, version.id).status == :superseded
    assert [_] = load(target.id).alternate_entries
    assert length(load(target.id).entry_blocks) == 2

    TranslationFixtures.add_block(c.source, c.module, c.user, "Fjerde avsnitt", 3)
    Translations.source_saved(load(c.source.id))
    assert pending(target) == nil

    assert {:error, :is_source} = Translations.make_independent(Article, c.source.id, c.user)
  end

  test "the source cannot be deleted while it has synchronized translations", c do
    {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)

    assert {:error, :group_has_synchronized_members} = SyncTest.delete_article(c.source.id, c.user)

    {:ok, _} = Translations.make_independent(Article, target.id, c.user)
    assert {:ok, _} = SyncTest.delete_article(c.source.id, c.user)
  end

  test "transfer_source hands the role to a translation", c do
    {:ok, en} = Translations.create_target(Article, c.source.id, :en, c.user)
    translate(en, ["First paragraph", "Second paragraph"])

    assert {:ok, %{role: :source}} = Translations.transfer_source(Article, en.id, c.user)
    assert %{role: :target, synchronized: true} = Translations.get_member(Article, c.source.id)

    # The switch raises no work by itself, although the texts differ.
    Translations.source_saved(load(en.id))
    assert pending(c.source) == nil

    # The former source no longer drives the group…
    TranslationFixtures.add_block(c.source, c.module, c.user, "Tredje avsnitt", 2)
    Translations.source_saved(load(c.source.id))
    assert pending(en) == nil

    # …the new one does, and removes the block the old source added.
    TranslationFixtures.add_block(en, c.module, c.user, "Third paragraph", 2)
    Translations.source_saved(load(en.id))

    payload = c.source |> pending() |> Translations.decode_payload()
    assert texts(payload) == ["Første avsnitt", "Andre avsnitt", "Third paragraph"]
  end

  test "create_target refuses a language the schema does not know", c do
    assert {:error, :unknown_language} = Translations.create_target(Article, c.source.id, :de, c.user)
  end

  test "independent schemas are ignored", c do
    page = Factory.insert(:page, creator: c.user)

    assert :ok = Translations.source_saved(page)
    assert :ok = Translations.guard_delete(Brando.Pages.Page, page)
    assert {:error, :not_synchronized} = Translations.enroll_source(Brando.Pages.Page, page.id, c.user)
  end

  describe "duplication" do
    test "subform rows are copied, not moved", c do
      {:ok, copy} = SyncTest.duplicate_article(c.source.id, c.user, change_fields: [slug: "copy"])

      assert [original] = load(c.source.id).items
      assert [copied] = load(copy.id).items
      assert copied.id != original.id
      assert {copied.uid, copied.label} == {original.uid, original.label}
    end

    test "a one-to-one subform row is copied, not moved", c do
      image = Factory.insert(:image, creator_id: c.user.id)

      Repo.insert!(%SyncTest.ArticleAuthor{
        article_id: c.source.id,
        name: "Example Author",
        portrait_id: image.id,
        links: [%SyncTest.ArticleAuthorLink{label: "Example Hotel"}]
      })

      {:ok, copy} = SyncTest.duplicate_article(c.source.id, c.user, change_fields: [slug: "copy"])
      {:ok, translation} = Translations.create_target(Article, c.source.id, :en, c.user)

      original = load(c.source.id).author
      assert {original.name, original.portrait_id} == {"Example Author", image.id}
      # The row's own rows stay with it, and the copies get theirs
      assert [%{label: "Example Hotel"} = original_link] = original.links

      for entry <- [copy, translation] do
        copied = load(entry.id).author
        assert copied.id != original.id
        assert {copied.name, copied.portrait_id} == {"Example Author", image.id}
        assert [%{label: "Example Hotel"} = copied_link] = copied.links
        assert copied_link.id != original_link.id
      end
    end

    test "a copied subform row gets its own blocks and gallery, and keeps its related entries", c do
      alias SyncTest.ArticleAuthorLink

      image = Factory.insert(:image, creator_id: c.user.id)
      gallery = Factory.insert(:gallery, gallery_objects: [Factory.build(:gallery_object, image: image, creator: c.user)])

      {:ok, hotel} =
        SyncTest.create_article(
          %{title: "Example Hotel", slug: "example-hotel", language: "no", status: "published"},
          c.user
        )

      {:ok, hotel_en} = Translations.create_target(Article, hotel.id, :en, c.user)
      identifier = Repo.get_by!(Brando.Content.Identifier, schema: Article, entry_id: hotel.id)

      author =
        Repo.insert!(%SyncTest.ArticleAuthor{
          article_id: c.source.id,
          name: "Example Author",
          links: [%ArticleAuthorLink{label: "Example Hotel", gallery_id: gallery.id, rendered_blocks: "<p>Lobby</p>"}]
        })

      [link] = author.links
      Repo.insert!(%ArticleAuthorLink.RelatedEntriesIdentifier{parent_id: link.id, identifier_id: identifier.id})

      block =
        %Block{}
        |> Block.recursive_block_changeset(
          %{
            "uid" => Brando.Utils.generate_uid(),
            "type" => "module",
            "module_id" => c.module.id,
            "creator_id" => c.user.id,
            "source" => to_string(ArticleAuthorLink.Blocks),
            "refs" => [
              %{
                "uid" => Brando.Utils.generate_uid(),
                "name" => "body",
                "data" => %{"type" => "text", "data" => %{"text" => "Lobby"}}
              }
            ]
          },
          c.user
        )
        |> Repo.insert!()

      Repo.insert!(%ArticleAuthorLink.Blocks{entry_id: link.id, block_id: block.id, sequence: 0})

      {:ok, copy} = SyncTest.duplicate_article(c.source.id, c.user, change_fields: [slug: "copy"])
      {:ok, translation} = Translations.create_target(Article, c.source.id, :en, c.user)

      load_link = fn id ->
        [link] = load(id).author.links
        Repo.preload(link, [:related_entries, entry_blocks: [block: :refs]])
      end

      original = load_link.(c.source.id)
      assert original.gallery_id == gallery.id
      assert [%{block_id: block_id}] = original.entry_blocks
      assert block_id == block.id
      assert [%{identifier_id: identifier_id}] = original.related_entries
      assert identifier_id == identifier.id

      for entry <- [copy, translation] do
        copied = load_link.(entry.id)
        assert copied.id != original.id
        assert copied.gallery_id not in [nil, gallery.id]
        assert copied.rendered_blocks == "<p>Lobby</p>"
        assert [%{block: copied_block}] = copied.entry_blocks
        assert copied_block.id != block.id
        # A translation's blocks keep their sync identity, a duplicate's don't
        assert copied_block.sync_uid == if(entry.id == translation.id, do: block.uid)
        assert [%{data: %{data: %{text: "Lobby"}}}] = copied_block.refs
        # The translation's link points at the English version
        identifier_en = Repo.get_by(Brando.Content.Identifier, schema: Article, entry_id: hotel_en.id)
        expected_id = if entry.id == translation.id, do: identifier_en && identifier_en.id, else: identifier_id
        assert [%{identifier_id: ^expected_id} = copied_entry] = copied.related_entries
        assert copied_entry.id != hd(original.related_entries).id
      end
    end

    test "a context's own change for related entries wins over the language mapping", c do
      {:ok, other} =
        SyncTest.create_article(
          %{title: "Example Hotel", slug: "example-hotel", language: "no", status: "published"},
          c.user
        )

      identifier = Repo.get_by!(Brando.Content.Identifier, schema: Article, entry_id: other.id)
      Repo.insert!(%Article.RelatedEntriesIdentifier{parent_id: c.source.id, identifier_id: identifier.id, sequence: 0})

      {:ok, copy} =
        SyncTest.duplicate_article(c.source.id, c.user,
          change_fields: [slug: "copy", related_entries: fn _entry, rows -> rows end],
          map_entries: fn _rows -> [] end
        )

      identifier_id = identifier.id
      assert [%{identifier_id: ^identifier_id}] = load(copy.id).related_entries
    end

    test "related entries are linked from the copy as well", c do
      {:ok, other} =
        SyncTest.create_article(
          %{title: "Example Hotel", slug: "example-hotel", language: "no", status: "published"},
          c.user
        )

      identifier = Repo.get_by!(Brando.Content.Identifier, schema: Article, entry_id: other.id)
      inserted_at = ~N[2020-01-01 00:00:00]

      Repo.insert!(%Article.RelatedEntriesIdentifier{
        parent_id: c.source.id,
        identifier_id: identifier.id,
        sequence: 0,
        inserted_at: inserted_at,
        updated_at: inserted_at
      })

      {:ok, copy} = SyncTest.duplicate_article(c.source.id, c.user, change_fields: [slug: "copy"])

      assert [original] = load(c.source.id).related_entries
      assert [copied] = load(copy.id).related_entries
      assert copied.id != original.id
      assert {original.identifier_id, copied.identifier_id} == {identifier.id, identifier.id}
      # The copy's link is a new row, from now
      assert copied.inserted_at != inserted_at
    end

    test "a translation of an entry related to itself links itself", c do
      identifier = Repo.get_by!(Brando.Content.Identifier, schema: Article, entry_id: c.source.id)
      Repo.insert!(%Article.RelatedEntriesIdentifier{parent_id: c.source.id, identifier_id: identifier.id, sequence: 0})

      {:ok, en} = Translations.create_target(Article, c.source.id, :en, c.user)

      en_identifier = Repo.get_by(Brando.Content.Identifier, schema: Article, entry_id: en.id)
      assert en_identifier
      assert [%{identifier_id: identifier_id}] = load(en.id).related_entries
      assert identifier_id == en_identifier.id
      assert [%{identifier_id: source_identifier_id}] = load(c.source.id).related_entries
      assert source_identifier_id == identifier.id
    end

    test "a translation links the related entries' versions in its language", c do
      create = fn title, slug ->
        {:ok, article} =
          SyncTest.create_article(%{title: title, slug: slug, language: "no", status: "published"}, c.user)

        article
      end

      identifier_of = fn article -> Repo.get_by!(Brando.Content.Identifier, schema: Article, entry_id: article.id) end

      translated = create.("Example Hotel", "example-hotel")
      untranslated = create.("Example Hotel Annex", "example-hotel-annex")
      {:ok, translated_en} = Translations.create_target(Article, translated.id, :en, c.user)

      for {article, sequence} <- [{translated, 0}, {untranslated, 1}] do
        Repo.insert!(%Article.RelatedEntriesIdentifier{
          parent_id: c.source.id,
          identifier_id: identifier_of.(article).id,
          sequence: sequence
        })
      end

      {:ok, en} = Translations.create_target(Article, c.source.id, :en, c.user)

      # One with no English version yet is left out
      assert [%{identifier_id: identifier_id}] = load(en.id).related_entries
      assert identifier_id == identifier_of.(translated_en).id
      assert length(load(c.source.id).related_entries) == 2
    end

    test "a translation whose URI the language already uses gets a free one", c do
      alias Brando.Pages.Page

      put_test_env(Page, translatable: [mode: :synchronized])
      Factory.insert(:page, title: "Indeks", uri: "index", language: :no)
      Factory.insert(:page, title: "Indeks 2", uri: "index-2", language: :no)
      about = Factory.insert(:page, title: "About", uri: "about", language: :en)
      index = Factory.insert(:page, title: "Index", uri: "index", language: :en)

      assert {:ok, no_index} = Translations.create_target(Page, index.id, :no, c.user)
      assert {no_index.uri, no_index.language} == {"index-3", :no}

      # A language that has the URI free keeps it.
      assert {:ok, no_about} = Translations.create_target(Page, about.id, :no, c.user)
      assert no_about.uri == "about"
    end

    test "alternates are not taken from the original", c do
      {:ok, en} = Translations.create_target(Article, c.source.id, :en, c.user)
      {:ok, copy} = SyncTest.duplicate_article(en.id, c.user, change_fields: [slug: "copy"])

      assert load(copy.id).alternate_entries == []
      assert [_] = load(en.id).alternate_entries
    end

    test "a translation gets its own copy of each gallery", c do
      image = Factory.insert(:image, creator_id: c.user.id)
      gallery = Factory.insert(:gallery, gallery_objects: [Factory.build(:gallery_object, image: image, creator: c.user)])

      add_raw_block(
        c.source,
        c,
        %{
          "refs" => [
            %{
              "uid" => Brando.Utils.generate_uid(),
              "name" => "gallery",
              "gallery_id" => gallery.id,
              "data" => %{"type" => "gallery", "data" => %{}}
            }
          ]
        },
        2
      )

      {:ok, en} = Translations.create_target(Article, c.source.id, :en, c.user)

      gallery_ref = fn entry ->
        entry.entry_blocks |> Enum.flat_map(& &1.block.refs) |> Enum.find(&(&1.name == "gallery"))
      end

      assert gallery_ref.(load(c.source.id)).gallery_id == gallery.id

      copied = gallery_ref.(load(en.id))
      assert copied.gallery_id != gallery.id
      assert Enum.map(copied.gallery.gallery_objects, & &1.image_id) == [image.id]

      # The source gallery gains an image: the pending version carries it into
      # the translation's own gallery, which is not touched yet.
      second = Factory.insert(:image, creator_id: c.user.id)
      Factory.insert(:gallery_object, gallery_id: gallery.id, image: second, sequence: 1, creator: c.user)
      Translations.source_saved(load(c.source.id))

      version = pending(en)
      assert Enum.any?(version.work_items, &(&1.kind == :shared_update and &1.path =~ ~r"/refs/gallery/gallery$"))

      pending_ref = version |> Translations.decode_payload() |> gallery_ref.()
      assert pending_ref.gallery_id == copied.gallery_id
      assert Enum.map(pending_ref.gallery.gallery_objects, & &1.image_id) == [image.id, second.id]
      assert Enum.map(gallery_ref.(load(en.id)).gallery.gallery_objects, & &1.image_id) == [image.id]
    end
  end

  describe "copying a batch to a language" do
    setup c do
      article = fn title, slug ->
        {:ok, article} =
          SyncTest.create_article(%{title: title, slug: slug, language: "no", status: "published"}, c.user)

        article
      end

      hotel = article.("Example Hotel", "example-hotel")
      annex = article.("Example Hotel Annex", "example-hotel-annex")

      # The hotel links the annex, and so does its author's link
      link_to(Article.RelatedEntriesIdentifier, hotel.id, annex)

      author =
        Repo.insert!(%SyncTest.ArticleAuthor{
          article_id: hotel.id,
          name: "Example Author",
          links: [%SyncTest.ArticleAuthorLink{label: "Example Hotel"}]
        })

      link_to(SyncTest.ArticleAuthorLink.RelatedEntriesIdentifier, hd(author.links).id, annex)
      %{hotel: hotel, annex: annex}
    end

    defp link_to(join, parent_id, entry) do
      Repo.insert!(struct(join, parent_id: parent_id, identifier_id: identifier_id(entry)))
    end

    # A translation gets its identifier when something first links to it
    defp identifier_id(entry) do
      case Repo.get_by(Brando.Content.Identifier, schema: Article, entry_id: entry.id) do
        nil -> elem(Brando.Content.create_identifier(Article, entry), 1).id
        identifier -> identifier.id
      end
    end

    defp copy_batch(c, ids) do
      opts = [change_fields: [{:language, :en} | Translations.free_unique_values(Article)], delete_fields: []]
      Translations.copy_batch_to_language(Article, ids, "en", c.user, opts)
    end

    defp english_copy(entry) do
      [copy_id] = Repo.all(from a in Article, where: a.language == :en and a.title == ^entry.title, select: a.id)
      copy = load(copy_id)

      case copy.author do
        %{links: [link]} -> {copy, Repo.preload(link, :related_entries)}
        nil -> {copy, nil}
      end
    end

    test "links an entry copied with it, though its duplicate returns the copy bare", c do
      Process.put({:synctest_duplicate, c.hotel.id}, :bare)

      assert %{failed: [], dropped_links: 0} = copy_batch(c, [c.hotel.id, c.annex.id])

      {annex_en, _link} = english_copy(c.annex)
      {hotel_en, link} = english_copy(c.hotel)
      annex_en_id = identifier_id(annex_en)
      assert [%{identifier_id: ^annex_en_id}] = hotel_en.related_entries
      assert [%{identifier_id: ^annex_en_id}] = link.related_entries
    end

    test "leaves out and counts links to an entry whose copy failed", c do
      Process.put({:synctest_duplicate, c.annex.id}, :error)

      assert %{failed: [{annex_id, {:error, :synctest_failed}}], dropped_links: 2} =
               copy_batch(c, [c.hotel.id, c.annex.id])

      assert annex_id == c.annex.id
      {hotel_en, link} = english_copy(c.hotel)
      assert {hotel_en.related_entries, link.related_entries} == {[], []}
    end

    test "leaves no link in the source's language when a later copy raises", c do
      Process.put({:synctest_duplicate, c.annex.id}, :raise)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert_raise RuntimeError, fn -> copy_batch(c, [c.hotel.id, c.annex.id]) end
        end)

      # The links taken out are counted in the log, as the toast never shows
      assert log =~ "2 link(s) were left out of the copies made"

      {hotel_en, link} = english_copy(c.hotel)
      assert {hotel_en.related_entries, link.related_entries} == {[], []}
    end

    test "keeps a link to an entry of the batch already in the language", c do
      {:ok, annex_en} = Translations.create_target(Article, c.annex.id, :en, c.user)
      link_to(Article.RelatedEntriesIdentifier, c.hotel.id, annex_en)

      assert %{failed: [], dropped_links: 0} = copy_batch(c, [c.hotel.id, annex_en.id])

      [hotel_en_id] = Repo.all(from a in Article, where: a.language == :en and a.title == ^c.hotel.title, select: a.id)
      annex_en_id = identifier_id(annex_en)
      assert annex_en_id in Enum.map(load(hotel_en_id).related_entries, & &1.identifier_id)
    end

    @tag capture_log: true
    test "puts the copies' links right before a throw goes on", c do
      Process.put({:synctest_duplicate, c.annex.id}, :throw)

      assert catch_throw(copy_batch(c, [c.hotel.id, c.annex.id])) == :synctest_thrown

      {hotel_en, link} = english_copy(c.hotel)
      assert {hotel_en.related_entries, link.related_entries} == {[], []}
    end

    # The fixture with UUID keys has no context to duplicate it with: the
    # batch gets as far as asking for one.
    @tag capture_log: true
    test "takes the ids of a schema with UUID keys as they are", c do
      people =
        for name <- ["Example Guest", "Example Host"] do
          Repo.insert!(%Brando.Persons.Person{
            name: name,
            email: "#{name}@example.com",
            language: :no,
            creator_id: c.user.id
          })
        end

      ids = Enum.map(people, & &1.id)
      opts = [change_fields: [language: :en], delete_fields: []]

      error =
        assert_raise UndefinedFunctionError, fn ->
          Translations.copy_batch_to_language(Brando.Persons.Person, ids, "en", c.user, opts)
        end

      assert error.function == :duplicate_person
    end

    test "links an entry related to itself to its own copy", c do
      link_to(Article.RelatedEntriesIdentifier, c.hotel.id, c.hotel)

      assert %{failed: [], dropped_links: 0} = copy_batch(c, [c.hotel.id, c.annex.id])

      {hotel_en, _link} = english_copy(c.hotel)
      {annex_en, _link} = english_copy(c.annex)

      assert hotel_en.related_entries |> Enum.map(& &1.identifier_id) |> Enum.sort() ==
               Enum.sort([identifier_id(annex_en), identifier_id(hotel_en)])
    end
  end

  describe "a parent in the same schema" do
    setup c do
      {:ok, parent} =
        SyncTest.create_article(%{title: "Forelder", slug: "forelder", language: "no", status: "published"}, c.user)

      source = c.source |> Ecto.Changeset.change(parent_id: parent.id) |> Repo.update!()
      %{parent: parent, source: source}
    end

    test "waits for the parent's translation, then follows it", c do
      {:ok, en} = Translations.create_target(Article, c.source.id, :en, c.user)

      version = pending(en)
      assert Enum.any?(version.work_items, &(&1.kind == :awaiting_translation and &1.path == "parent/#{c.parent.id}"))
      # The copy kept the source's parent; the pending version doesn't point it elsewhere yet
      assert Translations.decode_payload(version).parent_id == c.parent.id

      {:ok, parent_en} = Translations.create_target(Article, c.parent.id, :en, c.user)

      version = pending(en)
      refute Enum.any?(version.work_items, &(&1.kind == :awaiting_translation))
      assert Translations.decode_payload(version).parent_id == parent_en.id
    end

    test "only the awaited entry's translation re-syncs a waiting parent", c do
      {:ok, en} = Translations.create_target(Article, c.source.id, :en, c.user)
      waiting = pending(en)

      {:ok, unrelated} =
        SyncTest.create_article(%{title: "Annen", slug: "annen", language: "no", status: "published"}, c.user)

      {:ok, _} = Translations.create_target(Article, unrelated.id, :en, c.user)
      assert pending(en).id == waiting.id
    end

    test "maps at once when the parent is already translated", c do
      {:ok, parent_en} = Translations.create_target(Article, c.parent.id, :en, c.user)
      {:ok, en} = Translations.create_target(Article, c.source.id, :en, c.user)

      assert Translations.decode_payload(pending(en)).parent_id == parent_en.id
      assert Translations.entry_map(c.source, Article, "en") == %{c.parent.id => parent_en.id}
    end
  end

  describe "links to other content" do
    setup c do
      {:ok, other} =
        SyncTest.create_article(%{title: "Annen", slug: "annen", language: "no", status: "published"}, c.user)

      identifier_id = identifier_id!(other)
      add_raw_block(c.source, c, %{"block_identifiers" => [%{"identifier_id" => identifier_id}]}, 2)
      %{other: other, identifier_id: identifier_id}
    end

    defp linked_ids(entry) do
      entry.entry_blocks |> List.last() |> Map.get(:block) |> Map.get(:block_identifiers) |> Enum.map(& &1.identifier_id)
    end

    test "a link awaits the translation of what it points at, then follows it", c do
      {:ok, en} = Translations.create_target(Article, c.source.id, :en, c.user)

      version = pending(en)
      assert [%{path: path}] = Enum.filter(version.work_items, &(&1.kind == :awaiting_translation))
      assert path =~ ~r"^entry_blocks/.+/identifiers/#{c.identifier_id}$"
      # Still linked, to the Norwegian article, until it is translated
      assert linked_ids(Translations.decode_payload(version)) == [c.identifier_id]

      # Translating the linked article fills the link in.
      {:ok, other_en} = Translations.create_target(Article, c.other.id, :en, c.user)
      {:ok, other_en_identifier} = Brando.Content.get_identifier(Article, other_en)

      version = pending(en)
      refute Enum.any?(version.work_items, &(&1.kind == :awaiting_translation))
      assert linked_ids(Translations.decode_payload(version)) == [other_en_identifier.id]
    end

    test "a link maps even when its identifier predates the schema's translations", c do
      # Identifiers made before a schema became translatable have no language
      Repo.update_all(from(i in Brando.Content.Identifier, where: i.id == ^c.identifier_id), set: [language: nil])

      {:ok, other_en} = Translations.create_target(Article, c.other.id, :en, c.user)
      mapped = Translations.identifier_map(load(c.source.id), Article, "en")[c.identifier_id]
      {:ok, other_en_identifier} = Brando.Content.get_identifier(Article, other_en)

      assert mapped == other_en_identifier.id
    end

    test "a link to content already translated is mapped at once", c do
      {:ok, other_en} = Translations.create_target(Article, c.other.id, :en, c.user)
      {:ok, en} = Translations.create_target(Article, c.source.id, :en, c.user)

      # Nothing changed in the source: the copy's link moved, it was not updated
      version = pending(en)
      assert Enum.map(version.work_items, & &1.kind) == [:relinked]
      assert linked_ids(Translations.decode_payload(version)) == [identifier_id!(other_en)]
    end
  end

  describe "trait validation" do
    alias Brando.Exception.BlueprintError
    alias Brando.Trait.Translatable

    test "accepts the defaults and a synchronized config" do
      assert Translatable.validate(Article, []) == true
      assert Translatable.validate(Article, mode: :synchronized, source_controlled_fields: [:year, :cover]) == true
    end

    test "rejects unknown modes, fields and synchronized without alternates" do
      assert_raise BlueprintError, ~r/mode must be one of/, fn -> Translatable.validate(Article, mode: :shared) end

      assert_raise BlueprintError, ~r/are not attributes/, fn ->
        Translatable.validate(Article, mode: :synchronized, source_controlled_fields: [:nope])
      end

      assert_raise BlueprintError, ~r/requires alternates/, fn ->
        Translatable.validate(Article, mode: :synchronized, alternates: false)
      end

      assert_raise BlueprintError, ~r/requires mode: :synchronized/, fn ->
        Translatable.validate(Article, source_controlled_fields: [:year])
      end
    end

    test "Page is independent unless configured, and reads its config at runtime, per site" do
      alias Brando.Pages.Page
      alias Brando.Translations.Sync

      assert Page.__translatable_config__().mode == :independent

      synchronized = [mode: :synchronized, source_controlled_fields: [:template, :is_homepage]]
      put_test_env(Page, translatable: synchronized, translatable_sites: %{"acme" => [mode: :independent]})

      assert %{mode: :synchronized, source_controlled_fields: [:template, :is_homepage]} =
               Page.__translatable_config__()

      assert Sync.tree_relations(Page) == [:parent]
      assert Brando.Translations.synchronized?(Page)

      put_test_env(:tenancy_mode, :multi)

      Brando.Tenant.with_prefix("tenant_acme_production", fn ->
        assert Page.__translatable_config__().mode == :independent
      end)

      Brando.Tenant.with_prefix("tenant_other_production", fn ->
        assert Page.__translatable_config__().mode == :synchronized
      end)
    end

    test "runtime configs are checked at boot" do
      put_test_env(Brando.Pages.Page, translatable: [mode: :synchronized, source_controlled_fields: [:template]])
      assert Translatable.check_runtime_config!() == :ok

      put_test_env(Brando.Pages.Page, translatable: [mode: :synchronized, source_controlled_fields: [:nope]])
      assert_raise BlueprintError, ~r/are not attributes/, fn -> Translatable.check_runtime_config!() end

      put_test_env(Brando.Pages.Page, translatable_sites: %{"acme" => [mode: :shared]})
      assert_raise BlueprintError, ~r/mode must be one of/, fn -> Translatable.check_runtime_config!() end

      put_test_env(Brando.Pages.Page, [])
      put_test_env(Article, translatable: [mode: :synchronized])

      assert_raise BlueprintError, ~r/does not declare trait :translatable, runtime_config: true/, fn ->
        Translatable.check_runtime_config!()
      end
    end

    test "language_controlled_fields takes assets, only in synchronized mode and not both ways" do
      assert Translatable.validate(Article, mode: :synchronized, language_controlled_fields: [:cover]) == true
      assert %{language_controlled_fields: [:cover]} = Translatable.config(language_controlled_fields: [:cover])

      assert_raise BlueprintError, ~r/are not image, file, video or gallery assets/, fn ->
        Translatable.validate(Article, mode: :synchronized, language_controlled_fields: [:year])
      end

      assert_raise BlueprintError, ~r/language_controlled_fields requires mode: :synchronized/, fn ->
        Translatable.validate(Article, language_controlled_fields: [:cover])
      end

      assert_raise BlueprintError, ~r/cannot be both/, fn ->
        Translatable.validate(Article,
          mode: :synchronized,
          source_controlled_fields: [:cover],
          language_controlled_fields: [:cover]
        )
      end
    end

    test "accepts subform fields and module variables, and keeps the flat form" do
      selectors = [:year, {:module, "hero-banner", [:layout, "theme"]}, items: [:link]]
      assert Translatable.validate(Article, mode: :synchronized, source_controlled_fields: selectors) == true

      assert %{
               source_controlled_fields: [:year],
               source_controlled_subform_fields: %{items: [:link]},
               source_controlled_module_vars: %{"hero-banner" => ["layout", "theme"]}
             } = Translatable.config(mode: :synchronized, source_controlled_fields: selectors)
    end

    test "rejects selectors that do not address an owned subform input or a module" do
      validate = &Translatable.validate(Article, mode: :synchronized, source_controlled_fields: &1)

      assert_raise BlueprintError, ~r/not an owned subform/, fn -> validate.(alternates: [:entry_id]) end
      assert_raise BlueprintError, ~r/not an owned subform/, fn -> validate.(nope: [:label]) end
      assert_raise BlueprintError, ~r/identify rows/, fn -> validate.(items: [:uid]) end
      assert_raise BlueprintError, ~r/identify rows/, fn -> validate.(items: [:article_id]) end
      assert_raise BlueprintError, ~r/are not inputs of the :items subform/, fn -> validate.(items: [:nope]) end
      assert_raise BlueprintError, ~r/more than once/, fn -> validate.([{:items, [:link]}, {:items, [:label]}]) end
      assert_raise BlueprintError, ~r/more than once/, fn -> validate.([{:module, "a", [:x]}, {:module, "a", [:y]}]) end
      assert_raise BlueprintError, ~r/must list field names/, fn -> validate.(["year"]) end
      assert_raise BlueprintError, ~r/must list field names/, fn -> validate.([{:module, "", [:x]}]) end
      assert_raise BlueprintError, ~r/must list field names/, fn -> validate.(items: []) end
    end

    test "check_config reports module selectors that match no module or variable", c do
      config = %{
        Article.__translatable_config__()
        | source_controlled_fields: [:year]
      }

      config =
        Map.put(config, :source_controlled_module_vars, %{
          c.module.uid => ["body_style"],
          "gone" => ["layout"]
        })

      assert Enum.sort(Translations.check_config(Article, config)) ==
               Enum.sort([{:unknown_module, "gone"}, {:unknown_var, c.module.uid, "body_style"}])
    end
  end
end
