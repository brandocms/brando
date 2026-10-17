defmodule BrandoIntegration.Repo.Migrations.AddSynctestArticleAuthors do
  use Ecto.Migration

  # A one-to-one subform with an image field on the synchronized-translation
  # test article (SubformRelationTest).
  def change do
    create table(:synctest_article_authors) do
      add :name, :text
      add :portrait_id, references(:images, on_delete: :nilify_all)
      add :article_id, references(:synctest_articles, on_delete: :delete_all)
    end

    create unique_index(:synctest_article_authors, [:article_id])
  end
end
