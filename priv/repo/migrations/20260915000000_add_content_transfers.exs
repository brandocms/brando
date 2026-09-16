defmodule Brando.Repo.Migrations.Brando174AddContentTransfers do
  use Ecto.Migration

  def up do
    create table(:content_transfer_receipts, primary_key: false, prefix: "public") do
      add :id, :uuid, primary_key: true
      add :package_id, :text, null: false
      add :fingerprint, :text, null: false
      add :scope, :text, null: false
      add :actor_id, references(:users, prefix: "public", on_delete: :nilify_all)
      add :before, :map, null: false
      add :after, :map, null: false
      add :mappings, :map, null: false
      add :refresh, {:array, :map}, default: [], null: false
      add :restored_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:content_transfer_receipts, [:scope, :actor_id, :inserted_at], prefix: "public")

    # Historical migration 107 inserts definitions before UID columns exist.
    # Current changesets, definition imports and copy helpers supply UIDs.
    # Fill only NULLs; existing lineage and version history must stay intact.
    execute """
    DO $$
    DECLARE definition_schema text; definition_table text;
    BEGIN
      FOR definition_schema IN
        SELECT nspname FROM pg_namespace
        WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'
      LOOP
        FOREACH definition_table IN ARRAY ARRAY['content_modules', 'content_table_templates']
        LOOP
          IF to_regclass(format('%I.%I', definition_schema, definition_table)) IS NOT NULL THEN
            EXECUTE format('UPDATE %I.%I SET uid = replace(gen_random_uuid()::text, ''-'', '''') WHERE uid IS NULL', definition_schema, definition_table);
            EXECUTE format('ALTER TABLE %I.%I ALTER COLUMN uid SET NOT NULL', definition_schema, definition_table);
          END IF;
        END LOOP;
      END LOOP;
    END $$;
    """
  end

  def down do
    execute """
    DO $$
    DECLARE definition_schema text; definition_table text;
    BEGIN
      FOR definition_schema IN
        SELECT nspname FROM pg_namespace
        WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'
      LOOP
        FOREACH definition_table IN ARRAY ARRAY['content_modules', 'content_table_templates']
        LOOP
          IF to_regclass(format('%I.%I', definition_schema, definition_table)) IS NOT NULL THEN
            EXECUTE format('ALTER TABLE %I.%I ALTER COLUMN uid DROP NOT NULL', definition_schema, definition_table);
          END IF;
        END LOOP;
      END LOOP;
    END $$;
    """

    drop table(:content_transfer_receipts, prefix: "public")
  end
end
