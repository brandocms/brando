defmodule Brando.Translations.TreeRelationsTest do
  # Which `belongs_to` relations a synchronized translation points at the
  # related entry's version in its language: none of an application's own
  # relations to another schema, source-controlled or not.
  use Brando.ConnCase, async: false

  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.SyncCategoryTest.Article
  alias Brando.SyncCategoryTest.Category
  alias Brando.SyncCategoryTest.ControlledArticle
  alias Brando.Translations

  setup do
    user = Factory.insert(:random_user)
    category = Repo.insert!(%Category{title: "Nyheter", language: :no})
    %{user: user, category: category}
  end

  defp category!(language, attrs \\ []),
    do: Repo.insert!(struct(%Category{title: "Kategori", language: language}, attrs))

  defp article!(schema, c, attrs) do
    struct(schema, Keyword.merge([title: "Artikkel", language: :no, status: :published, creator_id: c.user.id], attrs))
    |> Repo.insert!()
  end

  defp payload(schema, entry), do: schema |> Translations.get_pending_version(entry.id) |> Translations.decode_payload()

  defp awaiting(schema, entry) do
    for %{kind: :awaiting_translation, path: path, resolved_at: nil} <-
          Translations.get_pending_version(schema, entry.id).work_items,
        do: path
  end

  describe "a relation that is not source-controlled" do
    test "is each language's own, even to a schema with language links", c do
      category_en = category!(:en)
      :ok = Category.Alternate.add(c.category.id, category_en.id)
      source = article!(Article, c, category_id: c.category.id)

      assert Brando.Translations.Sync.tree_relations(Article) == []

      {:ok, en} = Translations.create_target(Article, source.id, :en, c.user)
      assert en.category_id == c.category.id

      # The editor's choice for the translation stays through a source save
      chosen = category!(:en, title: "Chosen")
      Repo.update!(Ecto.Changeset.change(Repo.get!(Article, en.id), category_id: chosen.id))
      Translations.source_saved(Repo.get!(Article, source.id))

      assert payload(Article, en).category_id == chosen.id
    end

    test "a required one is copied as it is when its entry has no version in the language", c do
      source = article!(Article, c, category_id: c.category.id)

      assert {:ok, en} = Translations.create_target(Article, source.id, :en, c.user)
      assert en.category_id == c.category.id
    end
  end

  # As on main: an application's `source_controlled_fields` copy a relation to
  # another schema as it is. Only a relation to the schema itself and one the
  # trait declares `always_source_controlled` (`Fragment.page`, see
  # SynchronizedFragmentsTest) are mapped.
  describe "a relation an application lists in source_controlled_fields" do
    test "is copied from the source as it is, even when the entry has a version in the language", c do
      category_en = category!(:en)
      :ok = Category.Alternate.add(c.category.id, category_en.id)
      page = Factory.insert(:page, uri: "om", title: "Om oss", language: :no, creator: c.user)
      page_en = Factory.insert(:page, uri: "about", title: "About", language: :en, creator: c.user)
      :ok = Page.Alternate.add(page.id, page_en.id)
      source = article!(ControlledArticle, c, category_id: c.category.id, page_id: page.id)

      assert Brando.Translations.Sync.tree_relations(ControlledArticle) == []

      {:ok, en} = Translations.create_target(ControlledArticle, source.id, :en, c.user)

      assert {en.category_id, en.page_id} == {c.category.id, page.id}

      assert {payload(ControlledArticle, en).category_id, payload(ControlledArticle, en).page_id} ==
               {c.category.id, page.id}

      assert awaiting(ControlledArticle, en) == []
    end

    test "is copied as it is when its entry has no version in the language, with nothing awaited", c do
      source = article!(ControlledArticle, c, category_id: c.category.id)

      assert {:ok, en} = Translations.create_target(ControlledArticle, source.id, :en, c.user)
      assert en.category_id == c.category.id
      assert awaiting(ControlledArticle, en) == []

      # The source's change reaches the translation as it is
      other = category!(:no, title: "Annen")
      Repo.update!(Ecto.Changeset.change(Repo.get!(ControlledArticle, source.id), category_id: other.id))
      Translations.source_saved(Repo.get!(ControlledArticle, source.id))

      assert payload(ControlledArticle, en).category_id == other.id
      assert awaiting(ControlledArticle, en) == []
    end
  end
end
