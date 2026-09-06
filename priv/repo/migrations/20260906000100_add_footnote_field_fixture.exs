defmodule BrandoIntegration.Repo.Migrations.AddFootnoteFieldFixture do
  use Ecto.Migration

  def change do
    alter table(:projects_projects) do
      add :rendered_introduction_notes, :text
      add :rendered_introduction_notes_at, :utc_datetime
    end

    create table(:projects_projects_introduction_notes) do
      add :entry_id, references(:projects_projects, on_delete: :delete_all)
      add :block_id, references(:content_blocks, on_delete: :delete_all)
      add :sequence, :integer
    end

    create unique_index(:projects_projects_introduction_notes, [:entry_id, :block_id])
  end
end
