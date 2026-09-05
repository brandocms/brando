defmodule Brando.Repo.Migrations.Brando168AddEntryDrafts do
  use Ecto.Migration

  def change do
    create table(:entry_drafts, primary_key: false, prefix: "public") do
      add :id, :uuid, primary_key: true
      add :scope, :text, null: false
      add :owner_id, references(:users, prefix: "public", on_delete: :delete_all), null: false
      add :entry_type, :text, null: false
      add :entry_id, :bigint
      add :form_name, :text, null: false
      add :generation, :bigint, null: false
      add :base_fingerprint, :text, null: false
      add :format_version, :integer, default: 1, null: false
      add :schema_version, :integer, default: 0, null: false
      add :payload, :map, null: false
      add :checksum, :text, null: false
      add :dismissed_at, :utc_datetime_usec
      add :attempted_at, :utc_datetime_usec
      add :resolved_at, :utc_datetime_usec
      add :discarded_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:entry_drafts, [:scope, :owner_id, :entry_type, :entry_id], prefix: "public")
    create index(:entry_drafts, [:expires_at], prefix: "public")
  end
end
