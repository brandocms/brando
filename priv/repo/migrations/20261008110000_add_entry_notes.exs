defmodule BrandoIntegration.Repo.Migrations.AddEntryNotes do
  use Ecto.Migration

  # Mirrors the brando_203 upgrade migration for the test schema.
  @moduledoc """
  Editors' notes on entries (`Brando.Notes`): a thread anchored to the entry,
  a block, a field or a text range, and the users each note mentions.
  """

  def change do
    create table(:entry_notes) do
      add :entry_type, :string, null: false
      add :entry_id, :integer, null: false
      add :parent_id, references(:entry_notes, on_delete: :delete_all)
      add :block_uid, :string
      add :field_path, :string
      add :range, :map
      add :anchor_label, :text
      add :body, :text, null: false
      add :author_id, references(:users, prefix: "public", on_delete: :nilify_all)
      add :resolved_at, :utc_datetime_usec
      add :resolved_by_id, references(:users, prefix: "public", on_delete: :nilify_all)
      add :detached_at, :utc_datetime_usec
      add :text_removed_at, :utc_datetime_usec
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:entry_notes, [:entry_type, :entry_id])
    create index(:entry_notes, [:parent_id])

    create table(:note_mentions) do
      add :note_id, references(:entry_notes, on_delete: :delete_all), null: false
      add :user_id, references(:users, prefix: "public", on_delete: :delete_all), null: false
      add :emailed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:note_mentions, [:note_id, :user_id])
    create index(:note_mentions, [:user_id, :emailed_at])
  end
end
