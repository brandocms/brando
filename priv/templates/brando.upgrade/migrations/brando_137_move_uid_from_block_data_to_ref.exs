defmodule Brando.Migrations.MoveUidFromBlockDataToRef do
  use Ecto.Migration

  def change do
    # Add uid column to content_refs table
    alter table(:content_refs) do
      add :uid, :string
    end

    # Data migration to move UIDs from block data to ref.uid
    # Handle duplicates by appending a suffix
    execute(
      """
      WITH duplicate_uids AS (
        SELECT data->>'uid' as uid, COUNT(*) as count
        FROM content_refs
        WHERE data->>'uid' IS NOT NULL
        GROUP BY data->>'uid'
        HAVING COUNT(*) > 1
      ),
      numbered_refs AS (
        SELECT 
          id,
          data->>'uid' as original_uid,
          ROW_NUMBER() OVER (PARTITION BY data->>'uid' ORDER BY id) as row_num
        FROM content_refs
        WHERE data->>'uid' IS NOT NULL
      )
      UPDATE content_refs
      SET uid = CASE
        WHEN nr.row_num = 1 THEN nr.original_uid
        ELSE nr.original_uid || '_' || nr.row_num
      END
      FROM numbered_refs nr
      WHERE content_refs.id = nr.id
        AND nr.original_uid IN (SELECT uid FROM duplicate_uids);
      """,
      """
      -- No rollback for data migration
      """
    )

    # Update non-duplicate UIDs
    execute(
      """
      UPDATE content_refs
      SET uid = (data->>'uid')
      WHERE data->>'uid' IS NOT NULL
        AND uid IS NULL;
      """,
      """
      -- No rollback for data migration
      """
    )

    # Generate UIDs for refs that don't have one (shouldn't happen in practice)
    execute(
      """
      UPDATE content_refs
      SET uid = gen_random_uuid()
      WHERE uid IS NULL;
      """,
      """
      -- No rollback for data migration
      """
    )

    # Create unique index on uid after data migration
    create unique_index(:content_refs, [:uid])

    # Make uid column not null after data migration
    alter table(:content_refs) do
      modify :uid, :string, null: false
    end
  end
end
