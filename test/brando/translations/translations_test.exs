defmodule Brando.TranslationsTest do
  use Brando.ConnCase, async: false

  alias Brando.Content.Block
  alias Brando.Factory
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
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

    add_block(source, module, user, "Første avsnitt", 0)
    add_block(source, module, user, "Andre avsnitt", 1)

    %{user: user, module: module, source: source}
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

  test "saving the source records pending work without touching the translation", c do
    {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
    translate(target, ["First paragraph", "Second paragraph"])

    [first, _second] = Enum.map(load(c.source.id).entry_blocks, & &1.block)
    set_text(first, "Første avsnitt, endret")
    add_block(c.source, c.module, c.user, "Tredje avsnitt", 2)

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

    add_block(c.source, c.module, c.user, "Tredje avsnitt", 2)
    Translations.source_saved(load(c.source.id))
    first = pending(target)

    {:ok, _} = SyncTest.update_article(c.source.id, %{year: 2024}, c.user)
    Translations.source_saved(load(c.source.id))
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

  test "make_independent stops synchronization and keeps content and links", c do
    {:ok, target} = Translations.create_target(Article, c.source.id, :en, c.user)
    add_block(c.source, c.module, c.user, "Tredje avsnitt", 2)
    Translations.source_saved(load(c.source.id))
    version = pending(target)

    assert {:ok, %{synchronized: false, detached_at: %DateTime{}}} =
             Translations.make_independent(Article, target.id, c.user)

    assert Repo.get!(PendingVersion, version.id).status == :superseded
    assert [_] = load(target.id).alternate_entries
    assert length(load(target.id).entry_blocks) == 2

    add_block(c.source, c.module, c.user, "Fjerde avsnitt", 3)
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
    add_block(c.source, c.module, c.user, "Tredje avsnitt", 2)
    Translations.source_saved(load(c.source.id))
    assert pending(en) == nil

    # …the new one does, and removes the block the old source added.
    add_block(en, c.module, c.user, "Third paragraph", 2)
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
      assert linked_ids(Translations.decode_payload(version)) == []

      # Translating the linked article fills the link in.
      {:ok, other_en} = Translations.create_target(Article, c.other.id, :en, c.user)
      {:ok, other_en_identifier} = Brando.Content.get_identifier(Article, other_en)

      version = pending(en)
      refute Enum.any?(version.work_items, &(&1.kind == :awaiting_translation))
      assert linked_ids(Translations.decode_payload(version)) == [other_en_identifier.id]
    end

    test "a link to content already translated is mapped at once", c do
      {:ok, other_en} = Translations.create_target(Article, c.other.id, :en, c.user)
      {:ok, en} = Translations.create_target(Article, c.source.id, :en, c.user)

      version = pending(en)
      assert Enum.map(version.work_items, & &1.kind) == [:shared_update]
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
  end
end
