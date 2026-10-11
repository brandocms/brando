defmodule Brando.Repo.Migrations.AddFragmentToBlock do
  use Ecto.Migration

  def up do
    # brando_108 adds the column on sites it migrated from Villain. Postgres
    # still adds the named foreign key when the column exists, so drop it first.
    execute "ALTER TABLE content_blocks DROP CONSTRAINT IF EXISTS content_blocks_fragment_id_fkey"

    alter table(:content_blocks) do
      add_if_not_exists :fragment_id, references(:pages_fragments, on_delete: :nilify_all)
    end
  end

  def down do
    alter table(:content_blocks) do
      remove :fragment_id
    end
  end
end
