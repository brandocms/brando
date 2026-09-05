defmodule Brando.Repo.Migrations.AddModuleMigrationTracking do
  use Ecto.Migration

  @moduledoc """
  Mirrors `brando_167_add_module_migration_tracking.exs` for the test/e2e schema.
  """

  def up do
    alter table(:content_modules) do
      add :uid, :text
    end

    alter table(:content_blocks) do
      add :module_version, :integer
    end

    execute "UPDATE content_modules SET uid = replace(gen_random_uuid()::text, '-', '') WHERE uid IS NULL"

    execute """
    UPDATE content_blocks b
    SET module_version = m.version
    FROM content_modules m
    WHERE b.module_id = m.id AND b.module_version IS NULL
    """

    create unique_index(:content_modules, [:uid])
    create index(:content_blocks, [:module_id, :module_version])
  end

  def down do
    drop_if_exists index(:content_blocks, [:module_id, :module_version])
    drop_if_exists unique_index(:content_modules, [:uid])

    alter table(:content_blocks) do
      remove :module_version
    end

    alter table(:content_modules) do
      remove :uid
    end
  end
end
