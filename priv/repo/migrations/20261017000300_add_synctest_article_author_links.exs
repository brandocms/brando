defmodule BrandoIntegration.Repo.Migrations.AddSynctestArticleAuthorLinks do
  use Ecto.Migration

  # What duplicating the synchronized-translation test article copies
  # (TranslationsTest: duplication): rows a one-to-one subform owns, with a
  # gallery and a block field of their own, and the article's related entries.
  def change do
    create table(:synctest_article_author_links) do
      add :label, :text
      add :author_id, references(:synctest_article_authors, on_delete: :delete_all)
      add :gallery_id, references(:galleries, on_delete: :nilify_all)
      add :rendered_blocks, :text
      add :rendered_blocks_at, :utc_datetime
    end

    create table(:synctest_article_author_links_blocks) do
      add :entry_id, references(:synctest_article_author_links, on_delete: :delete_all)
      add :block_id, references(:content_blocks, on_delete: :delete_all)
      add :sequence, :integer
    end

    create unique_index(:synctest_article_author_links_blocks, [:entry_id, :block_id])

    create table(:synctest_article_author_links_related_entries_identifiers) do
      add :parent_id, references(:synctest_article_author_links, on_delete: :delete_all)
      add :identifier_id, references(:content_identifiers, on_delete: :delete_all)
      add :sequence, :integer
      timestamps()
    end

    create unique_index(:synctest_article_author_links_related_entries_identifiers, [:parent_id, :identifier_id],
             name: :synctest_article_author_links_related_entries_identifiers_uniq
           )

    create table(:synctest_articles_related_entries_identifiers) do
      add :parent_id, references(:synctest_articles, on_delete: :delete_all)
      add :identifier_id, references(:content_identifiers, on_delete: :delete_all)
      add :sequence, :integer
      timestamps()
    end

    create unique_index(:synctest_articles_related_entries_identifiers, [:parent_id, :identifier_id])
  end
end
