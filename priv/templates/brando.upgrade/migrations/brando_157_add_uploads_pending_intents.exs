defmodule Brando.Repo.Migrations.AddUploadsPendingIntents do
  use Ecto.Migration

  @moduledoc """
  Makes an authorized client-direct upload outlive the process that authorized it.

  Client-direct transports (files/videos → S3/Spaces) presign a PUT and wait for
  the browser to report `direct_complete`. The object key and resolved config
  target needed to finalize that callback lived only in the sticky
  `BrandoAdmin.UploadManager`'s `items` assign, which `mount/1` hard-assigns to
  `%{}` — so a manager that remounted mid-transfer answered the completion with
  a silent no-op and left an object in the bucket with no asset row and no way
  to find it again.

  Rows here are removed on finalize, error and cancel; survivors are abandoned
  transfers and are swept by `Brando.Worker.UploadIntentReaper`.

  Nothing to backfill: an intent is only meaningful between presign and
  finalize, so any that existed before this table did are already lost.
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
      timestamps()
    end

    # The manager's item ref is the only handle a `direct_complete` carries.
    create unique_index(:uploads_pending_intents, [:ref])
    # The reaper sweeps by age.
    create index(:uploads_pending_intents, [:inserted_at])
  end
end
