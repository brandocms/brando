defmodule Brando.Repo.Migrations.Brando203AddEntryNotes do
  use Ecto.Migration

  @moduledoc """
  In every site environment, the tables for editors' notes (`Brando.Notes`):

    * `entry_notes` holds a note or a reply on an entry. It belongs to the
      entry, not to a revision, and may anchor to a block (`block_uid`), a
      field (`field_path`) and a text range (`range`).
    * `note_mentions` holds the users a note mentions, and when each was
      emailed about it, so "mentions of me" is one query and mention emails
      can be batched.

  Users live in `public`, so their foreign keys name that schema.
  """

  def up do
    for prefix <- prefixes() do
      create table(:entry_notes, prefix: prefix) do
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

      create index(:entry_notes, [:entry_type, :entry_id], prefix: prefix)
      create index(:entry_notes, [:parent_id], prefix: prefix)

      create table(:note_mentions, prefix: prefix) do
        add :note_id, references(:entry_notes, on_delete: :delete_all), null: false
        add :user_id, references(:users, prefix: "public", on_delete: :delete_all), null: false
        add :emailed_at, :utc_datetime_usec

        timestamps(type: :utc_datetime_usec, updated_at: false)
      end

      create unique_index(:note_mentions, [:note_id, :user_id], prefix: prefix)
      create index(:note_mentions, [:user_id, :emailed_at], prefix: prefix)
    end
  end

  def down do
    for prefix <- prefixes() do
      drop table(:note_mentions, prefix: prefix)
      drop table(:entry_notes, prefix: prefix)
    end
  end

  # Every site environment, or only the one named by the migrator's prefix:
  # `Brando.Environments.ArchiveUpgrade` runs this again in an archive
  # restored from before it ran.
  defp prefixes do
    case prefix() do
      "tenant_" <> _ = environment ->
        [environment]

      _ ->
        %{rows: rows} =
          repo().query!(
            "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
          )

        Enum.map(rows, &hd/1)
    end
  end
end
