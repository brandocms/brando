defmodule Brando.Repo.Migrations.Brando172AddTableTemplateUids do
  use Ecto.Migration

  def up do
    alter table(:content_table_templates) do
      add :uid, :text
    end

    execute "UPDATE content_table_templates SET uid = replace(gen_random_uuid()::text, '-', '') WHERE uid IS NULL"
    create unique_index(:content_table_templates, [:uid])

    execute """
    DO $$
    DECLARE tenant_schema text;
    BEGIN
      FOR tenant_schema IN
        SELECT nspname FROM pg_namespace
        WHERE nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'
      LOOP
        IF to_regclass(format('%I.content_table_templates', tenant_schema)) IS NOT NULL THEN
          EXECUTE format('ALTER TABLE %I.content_table_templates ADD COLUMN IF NOT EXISTS uid text', tenant_schema);
          EXECUTE format('UPDATE %I.content_table_templates SET uid = replace(gen_random_uuid()::text, ''-'', '''') WHERE uid IS NULL', tenant_schema);
          EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS %I ON %I.content_table_templates (uid)', tenant_schema || '_table_templates_uid_index', tenant_schema);
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
        IF to_regclass(format('%I.content_table_templates', tenant_schema)) IS NOT NULL THEN
          EXECUTE format('ALTER TABLE %I.content_table_templates DROP COLUMN IF EXISTS uid', tenant_schema);
        END IF;
      END LOOP;
    END $$;
    """

    drop unique_index(:content_table_templates, [:uid])
    alter table(:content_table_templates), do: remove(:uid)
  end
end
