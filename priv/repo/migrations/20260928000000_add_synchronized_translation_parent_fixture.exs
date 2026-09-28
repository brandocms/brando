defmodule BrandoIntegration.Repo.Migrations.AddSynchronizedTranslationParentFixture do
  use Ecto.Migration

  @moduledoc "A parent for `Brando.SyncTest.Article`, to test tree relations in synchronized translations."

  def change do
    alter table(:synctest_articles) do
      add :parent_id, references(:synctest_articles, on_delete: :nilify_all)
    end
  end
end
