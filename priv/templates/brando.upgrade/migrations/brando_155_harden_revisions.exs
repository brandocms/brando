defmodule Brando.Repo.Migrations.HardenRevisions do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE revisions ADD COLUMN IF NOT EXISTS schema_version integer NOT NULL DEFAULT 0"
    execute "ALTER TABLE revisions ADD COLUMN IF NOT EXISTS scheduled boolean NOT NULL DEFAULT false"

    execute "UPDATE revisions SET active = false WHERE active IS NULL"
    execute "UPDATE revisions SET protected = false WHERE protected IS NULL"
    execute "UPDATE revisions SET schema_version = 0 WHERE schema_version IS NULL"
    execute "ALTER TABLE revisions ALTER COLUMN active SET DEFAULT false"
    execute "ALTER TABLE revisions ALTER COLUMN active SET NOT NULL"
    execute "ALTER TABLE revisions ALTER COLUMN protected SET DEFAULT false"
    execute "ALTER TABLE revisions ALTER COLUMN protected SET NOT NULL"
    execute "ALTER TABLE revisions ALTER COLUMN schema_version SET DEFAULT 0"
    execute "ALTER TABLE revisions ALTER COLUMN schema_version SET NOT NULL"

    execute """
    WITH ranked AS (
      SELECT ctid,
             row_number() OVER (
               PARTITION BY entry_type, entry_id
               ORDER BY revision DESC
             ) AS row_number
      FROM revisions
      WHERE active = true
    )
    UPDATE revisions
    SET active = false
    WHERE ctid IN (SELECT ctid FROM ranked WHERE row_number > 1)
    """

    create_if_not_exists unique_index(:revisions, [:entry_type, :entry_id],
                           name: :revisions_one_active_per_entry_index,
                           where: "active = true"
                         )
  end

  def down do
    drop_if_exists index(:revisions, [:entry_type, :entry_id], name: :revisions_one_active_per_entry_index)

    execute "ALTER TABLE revisions DROP COLUMN IF EXISTS scheduled"
  end
end
