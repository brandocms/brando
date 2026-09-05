defmodule Brando.Repo.Migrations.Brando167AddModuleMigrationTracking do
  use Ecto.Migration

  @moduledoc """
  Migration tracking for module definitions (issue #2642).

  `content_modules.uid` is the module's lineage identity: it survives export and
  import, where the name and namespace cannot — both are i18n JSON maps, neither
  is unique, and both are editable.

  `content_blocks.module_version` records the newest module revision whose
  instance-data migration was successfully applied to that block. A block behind
  its module is stale: it keeps its own data and renders through the module's
  current code, and the editor is told so.

  Existing rows are backfilled as current, so upgrading does not flag the whole
  site as stale on day one.
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

    execute """
    DO $$
    DECLARE tenant_schema text;
    BEGIN
      FOR tenant_schema IN
        SELECT nspname FROM pg_namespace
        WHERE nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'
      LOOP
        IF to_regclass(format('%I.content_modules', tenant_schema)) IS NOT NULL THEN
          EXECUTE format('ALTER TABLE %I.content_modules ADD COLUMN IF NOT EXISTS uid text', tenant_schema);
          EXECUTE format('UPDATE %I.content_modules SET uid = replace(gen_random_uuid()::text, ''-'', '''') WHERE uid IS NULL', tenant_schema);
          EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS %I ON %I.content_modules (uid)', tenant_schema || '_content_modules_uid_index', tenant_schema);
        END IF;
        IF to_regclass(format('%I.content_blocks', tenant_schema)) IS NOT NULL THEN
          EXECUTE format('ALTER TABLE %I.content_blocks ADD COLUMN IF NOT EXISTS module_version integer', tenant_schema);
          EXECUTE format('UPDATE %I.content_blocks b SET module_version = m.version FROM %I.content_modules m WHERE b.module_id = m.id AND b.module_version IS NULL', tenant_schema, tenant_schema);
          EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I.content_blocks (module_id, module_version)', tenant_schema || '_content_blocks_module_id_module_version_index', tenant_schema);
        END IF;
      END LOOP;
    END $$;
    """
  end

  def down do
    execute """
    DO $$
    DECLARE tenant_schema text;
    BEGIN
      FOR tenant_schema IN
        SELECT nspname FROM pg_namespace
        WHERE nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'
      LOOP
        IF to_regclass(format('%I.content_blocks', tenant_schema)) IS NOT NULL THEN
          EXECUTE format('DROP INDEX IF EXISTS %I.%I', tenant_schema, tenant_schema || '_content_blocks_module_id_module_version_index');
          EXECUTE format('ALTER TABLE %I.content_blocks DROP COLUMN IF EXISTS module_version', tenant_schema);
        END IF;
        IF to_regclass(format('%I.content_modules', tenant_schema)) IS NOT NULL THEN
          EXECUTE format('DROP INDEX IF EXISTS %I.%I', tenant_schema, tenant_schema || '_content_modules_uid_index');
          EXECUTE format('ALTER TABLE %I.content_modules DROP COLUMN IF EXISTS uid', tenant_schema);
        END IF;
      END LOOP;
    END $$;
    """

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
