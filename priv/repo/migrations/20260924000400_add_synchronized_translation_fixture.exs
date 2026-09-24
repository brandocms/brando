defmodule BrandoIntegration.Repo.Migrations.AddSynchronizedTranslationFixture do
  use Ecto.Migration

  @moduledoc "Tables for `Brando.SyncTest.Article`, the synchronized-translation test Blueprint."

  def change do
    create table(:synctest_articles) do
      add :title, :text
      add :slug, :text
      add :subtitle, :text
      add :year, :integer
      add :featured, :boolean, default: false
      add :language, :text
      add :status, :integer
      add :cover_id, references(:images, on_delete: :nilify_all)
      add :creator_id, references(:users)
      add :updated_by_id, references(:users, on_delete: :nilify_all)
      add :edited_at, :utc_datetime
      add :rendered_blocks, :text
      add :rendered_blocks_at, :utc_datetime
      timestamps()
    end

    create table(:synctest_article_items) do
      add :uid, :text
      add :label, :text
      add :link, :text
      add :sequence, :integer
      add :article_id, references(:synctest_articles, on_delete: :delete_all)
    end

    create table(:synctest_articles_blocks) do
      add :entry_id, references(:synctest_articles, on_delete: :delete_all)
      add :block_id, references(:content_blocks, on_delete: :delete_all)
      add :sequence, :integer
    end

    create unique_index(:synctest_articles_blocks, [:entry_id, :block_id])

    create table(:synctest_articles_alternates) do
      add :entry_id, references(:synctest_articles, on_delete: :delete_all)
      add :linked_entry_id, references(:synctest_articles, on_delete: :delete_all)
      timestamps()
    end

    create unique_index(:synctest_articles_alternates, [:entry_id, :linked_entry_id])
  end
end
