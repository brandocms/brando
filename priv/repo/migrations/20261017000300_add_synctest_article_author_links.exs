defmodule BrandoIntegration.Repo.Migrations.AddSynctestArticleAuthorLinks do
  use Ecto.Migration

  # Rows a one-to-one subform owns (TranslationsTest: duplication).
  def change do
    create table(:synctest_article_author_links) do
      add :label, :text
      add :author_id, references(:synctest_article_authors, on_delete: :delete_all)
    end
  end
end
