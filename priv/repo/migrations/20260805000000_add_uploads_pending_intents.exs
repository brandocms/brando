defmodule Brando.Repo.Migrations.AddUploadsPendingIntents do
  use Ecto.Migration

  @moduledoc """
  Test/e2e mirror of `priv/templates/brando.upgrade/migrations/brando_157_*`.

  Keep the two in step: `e2e/priv/repo/migrations` is a symlink to this
  directory, so both unit and e2e runs get the table from here, while consuming
  applications get it from the upgrade template.
  """

  def change do
    create table(:uploads_pending_intents) do
      add :ref, :uuid, null: false
      add :key, :text, null: false
      add :resolved_target, :text, null: false
      add :asset_type, :text, null: false
      add :mime_type, :text
      add :filename, :text
      add :filesize, :bigint
      add :target, :jsonb, default: "{}"
      add :creator_id, references(:users, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:uploads_pending_intents, [:ref])
    create index(:uploads_pending_intents, [:inserted_at])
  end
end
