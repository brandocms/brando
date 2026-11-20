defmodule BrandoIntegration.Repo.Migrations.AddQuotesToSynctestArticles do
  use Ecto.Migration

  # An embeds_many subform with a text on the synchronized-translation test
  # article (TranslationAIFillTest).
  def change do
    alter table(:synctest_articles) do
      add :quotes, :jsonb
    end
  end
end
