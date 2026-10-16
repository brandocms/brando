defmodule BrandoIntegration.Repo.Migrations.AddMediaToSynctestArticleItems do
  use Ecto.Migration

  # Image and video fields inside a subform row of the synchronized-translation test
  # article (SubformRelationTest).
  def change do
    alter table(:synctest_article_items) do
      add :cover_id, references(:images, on_delete: :nilify_all)
      add :clip_id, references(:videos, on_delete: :nilify_all)
    end
  end
end
