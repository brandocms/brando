defmodule Brando.Repo.Migrations.Brando169AddBlockSlots do
  use Ecto.Migration

  def up do
    alter table(:content_blocks) do
      add :slot_name, :text
      add :slot_kind, :text
      add :slot_module_set, :text
    end

    create index(:content_blocks, [:parent_id, :slot_kind, :slot_name])

    execute """
    DO $$
    DECLARE tenant_schema text;
    BEGIN
      FOR tenant_schema IN
        SELECT nspname FROM pg_namespace
        WHERE nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'
      LOOP
        IF to_regclass(format('%I.content_blocks', tenant_schema)) IS NOT NULL THEN
          EXECUTE format('ALTER TABLE %I.content_blocks ADD COLUMN IF NOT EXISTS slot_name text, ADD COLUMN IF NOT EXISTS slot_kind text, ADD COLUMN IF NOT EXISTS slot_module_set text', tenant_schema);
          EXECUTE format('CREATE INDEX IF NOT EXISTS content_blocks_parent_id_slot_kind_slot_name_index ON %I.content_blocks (parent_id, slot_kind, slot_name)', tenant_schema);
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
          EXECUTE format('ALTER TABLE %I.content_blocks DROP COLUMN IF EXISTS slot_name, DROP COLUMN IF EXISTS slot_kind, DROP COLUMN IF EXISTS slot_module_set', tenant_schema);
        END IF;
      END LOOP;
    END $$;
    """

    drop_if_exists index(:content_blocks, [:parent_id, :slot_kind, :slot_name])

    alter table(:content_blocks) do
      remove :slot_name
      remove :slot_kind
      remove :slot_module_set
    end
  end
end
