defmodule BrandoIntegration.Repo.Migrations.AddNotesBlockFieldToSynctestArticles do
  use Ecto.Migration

  # A second block field on the synchronized-translation test article, for
  # AI actions that read one block field by name (FieldActionsLiveTest).
  def change do
    alter table(:synctest_articles) do
      add :rendered_notes, :text
      add :rendered_notes_at, :utc_datetime
    end

    create table(:synctest_articles_notes) do
      add :entry_id, references(:synctest_articles, on_delete: :delete_all)
      add :block_id, references(:content_blocks, on_delete: :delete_all)
      add :sequence, :integer
    end

    create unique_index(:synctest_articles_notes, [:entry_id, :block_id])
  end
end
