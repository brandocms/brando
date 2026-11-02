defmodule BrandoIntegration.Repo.Migrations.AddSynctestArticleAuthorRelatedEntries do
  use Ecto.Migration

  # An `:entries` input in a one-to-one subform (EntriesInputSubformRowsTest)
  def change do
    create table(:synctest_article_authors_related_entries_identifiers) do
      add :parent_id, references(:synctest_article_authors, on_delete: :delete_all)
      add :identifier_id, references(:content_identifiers, on_delete: :delete_all)
      add :sequence, :integer
      timestamps()
    end

    create unique_index(:synctest_article_authors_related_entries_identifiers, [:parent_id, :identifier_id],
             name: :synctest_article_authors_related_entries_identifiers_uniq
           )
  end
end
