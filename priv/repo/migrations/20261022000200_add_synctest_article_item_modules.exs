defmodule BrandoIntegration.Repo.Migrations.AddSynctestArticleItemModules do
  use Ecto.Migration

  # A multi-select inside a subform row of the synchronized-translation test
  # article (EntrySavedElsewhereTest).
  def change do
    create table(:synctest_article_item_modules) do
      add :item_id, references(:synctest_article_items, on_delete: :delete_all)
      add :module_id, references(:content_modules, on_delete: :delete_all)
      add :sequence, :integer
    end
  end
end
