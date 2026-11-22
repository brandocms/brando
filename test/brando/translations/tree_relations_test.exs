defmodule Brando.Translations.TreeRelationsTest do
  # Which `belongs_to` relations a synchronized translation points at the
  # related entry's version in its language: a source-controlled one to a
  # schema with language links. Any other stays as it is without the mapping.
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

  describe "a source-controlled relation to a schema with language links" do
    test "points at the entry's version in the translation's language", c do
      category_en = category!(:en)
      :ok = Category.Alternate.add(c.category.id, category_en.id)
      source = article!(ControlledArticle, c, category_id: c.category.id)

      {:ok, en} = Translations.create_target(ControlledArticle, source.id, :en, c.user)

      assert en.category_id == category_en.id
      assert payload(ControlledArticle, en).category_id == category_en.id
      assert awaiting(ControlledArticle, en) == []
    end

    test "a required one keeps the source's entry until a version exists, then follows it", c do
      source = article!(ControlledArticle, c, category_id: c.category.id)

      assert {:ok, en} = Translations.create_target(ControlledArticle, source.id, :en, c.user)
      assert en.category_id == c.category.id
      assert awaiting(ControlledArticle, en) == ["category/#{c.category.id}"]

      category_en = category!(:en)
      :ok = Category.Alternate.add(c.category.id, category_en.id)

      assert payload(ControlledArticle, en).category_id == category_en.id
      assert awaiting(ControlledArticle, en) == []
    end

    test "each relation is mapped on its own when two point at the same id in different schemas", c do
      page = Factory.insert(:page, uri: "om", title: "Om oss", language: :no, creator: c.user)
      page_en = Factory.insert(:page, uri: "about", title: "About", language: :en, creator: c.user)
      :ok = Page.Alternate.add(page.id, page_en.id)

      # A category with the page's id, and its English version
      category = category!(:no, id: page.id)
      category_en = category!(:en, id: page_en.id + 1000)
      :ok = Category.Alternate.add(category.id, category_en.id)

      source = article!(ControlledArticle, c, category_id: category.id, page_id: page.id)

      assert Translations.entry_map(source, ControlledArticle, "en") ==
               %{{:category, category.id} => category_en.id, {:page, page.id} => page_en.id}

      {:ok, en} = Translations.create_target(ControlledArticle, source.id, :en, c.user)
      assert {en.category_id, en.page_id} == {category_en.id, page_en.id}

      assert {payload(ControlledArticle, en).category_id, payload(ControlledArticle, en).page_id} ==
               {category_en.id, page_en.id}
    end
  end
end
