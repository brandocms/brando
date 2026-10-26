defmodule BrandoIntegration.Repo.Migrations.AddMediaToSynctestArticles do
  use Ecto.Migration

  # A file, a video and a gallery beside the test article's image, for
  # media inputs a form locks (LockedMediaDeliveriesTest)
  def change do
    alter table(:synctest_articles) do
      add :pdf_id, references(:files, on_delete: :nilify_all)
      add :clip_id, references(:videos, on_delete: :nilify_all)
      add :photos_id, references(:galleries, on_delete: :nilify_all)
    end
  end
end
