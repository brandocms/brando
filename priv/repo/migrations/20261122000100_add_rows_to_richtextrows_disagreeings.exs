defmodule BrandoIntegration.Repo.Migrations.AddRowsToRichtextrowsDisagreeings do
  use Ecto.Migration

  # Rows of each kind for Brando.RichTextRows.Disagreeing, whose forms
  # disagree on how a row's field is drawn. A moved identifier's links are
  # looked for in every Blueprint with rich text, rows included, so each
  # needs its column or table.
  def change do
    alter table(:richtextrows_disagreeings) do
      add :quotes, :jsonb
      add :feature, :jsonb
      add :notes, :jsonb
    end

    create table(:richtextrows_disagreeing_items) do
      add :text, :text
      add :sequence, :integer
      add :cover_id, references(:images, on_delete: :nilify_all)
      add :disagreeing_id, references(:richtextrows_disagreeings, on_delete: :delete_all)
    end
  end
end
