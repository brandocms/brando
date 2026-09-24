defmodule Brando.Repo.Migrations.Brando182AddSynchronizedTranslations do
  use Ecto.Migration

  @moduledoc """
  Storage for `trait :translatable, mode: :synchronized`.

  `sync_uid` pairs a block or table row with its counterpart in the other
  language versions of a translation group. Blocks fall back to their own
  `uid`, so they are backfilled with it; table rows had no identity at all.

  The group tables are content: their ids are entry ids of this schema, so
  they live beside the entries and travel with them between environments.
  """

  def up do
    alter table(:content_blocks) do
      add_if_not_exists :sync_uid, :text
    end

    alter table(:content_table_rows) do
      add_if_not_exists :sync_uid, :text
    end

    execute "UPDATE content_blocks SET sync_uid = uid WHERE sync_uid IS NULL"
    execute "UPDATE content_table_rows SET sync_uid = md5(random()::text || id::text) WHERE sync_uid IS NULL"

    create_if_not_exists index(:content_blocks, [:sync_uid])
    create_if_not_exists index(:content_table_rows, [:sync_uid])

    create table(:translation_groups) do
      add :entry_type, :text, null: false
      add :source_generation, :bigint, null: false, default: 0
      timestamps()
    end

    create table(:translation_group_members) do
      add :group_id, references(:translation_groups, on_delete: :delete_all), null: false
      add :entry_type, :text, null: false
      add :entry_id, :bigint, null: false
      add :language, :text, null: false
      add :role, :text, null: false
      add :synchronized, :boolean, null: false, default: true
      add :detached_at, :utc_datetime
      add :last_synced_generation, :bigint, null: false, default: 0
      add :baseline, :map, null: false, default: %{}
      timestamps()
    end

    # An entry belongs to at most one group, and a group has one source.
    create unique_index(:translation_group_members, [:entry_type, :entry_id])
    create unique_index(:translation_group_members, [:group_id, :language])

    create unique_index(:translation_group_members, [:group_id],
             where: "role = 'source'",
             name: :translation_group_members_one_source_index
           )

    create table(:translation_pending_versions) do
      add :member_id, references(:translation_group_members, on_delete: :delete_all), null: false
      add :source_generation, :bigint, null: false
      add :source_fingerprint, :text, null: false
      add :base_fingerprint, :text, null: false
      add :schema_version, :integer, null: false, default: 0
      add :payload, :binary, null: false
      add :notes, {:array, :map}, null: false, default: []
      add :status, :text, null: false
      add :applied_at, :utc_datetime
      timestamps()
    end

    create unique_index(:translation_pending_versions, [:member_id],
             where: "status = 'pending'",
             name: :translation_pending_versions_one_pending_index
           )

    create table(:translation_work_items) do
      add :pending_version_id, references(:translation_pending_versions, on_delete: :delete_all), null: false
      add :path, :text, null: false
      add :kind, :text, null: false
      add :source_digest, :text
      add :minor, :boolean, null: false, default: false
      add :resolved_at, :utc_datetime
      add :resolved_generation, :bigint
      timestamps()
    end

    create index(:translation_work_items, [:pending_version_id])
  end

  def down do
    drop table(:translation_work_items)
    drop table(:translation_pending_versions)
    drop table(:translation_group_members)
    drop table(:translation_groups)

    alter table(:content_table_rows) do
      remove :sync_uid
    end

    alter table(:content_blocks) do
      remove :sync_uid
    end
  end
end
