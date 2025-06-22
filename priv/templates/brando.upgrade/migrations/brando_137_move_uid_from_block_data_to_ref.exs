defmodule Brando.Migrations.MoveUidFromBlockDataToRef do
  use Ecto.Migration

  def change do
    # Add uid column to content_refs table
    alter table(:content_refs) do
      add :uid, :string
    end

    # Create unique index on uid
    create unique_index(:content_refs, [:uid])

    # Data migration to move UIDs from block data to ref.uid
    execute(
      """
      UPDATE content_refs
      SET uid = (data->>'uid')
      WHERE data->>'uid' IS NOT NULL;
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

    # Make uid column not null after data migration
    alter table(:content_refs) do
      modify :uid, :string, null: false
    end
  end
end
