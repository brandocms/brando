defmodule BrandoIntegration.Repo.Migrations.AddSynctestArticleItemRelatedEntries do
  use Ecto.Migration

  # An `:entries` input in a subform row of the synchronized-translation test
  # article (EntriesInputMaskingTest).
  def change do
    create table(:synctest_article_items_related_entries_identifiers) do
      add :parent_id, references(:synctest_article_items, on_delete: :delete_all)
      add :identifier_id, references(:content_identifiers, on_delete: :delete_all)
      add :sequence, :integer
      timestamps()
    end

    create unique_index(:synctest_article_items_related_entries_identifiers, [:parent_id, :identifier_id],
             name: :synctest_article_items_related_entries_identifiers_uniq
           )
  end
end
