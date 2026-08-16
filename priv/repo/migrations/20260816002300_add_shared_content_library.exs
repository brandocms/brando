defmodule BrandoIntegration.Repo.Migrations.AddSharedContentLibrary do
  use Ecto.Migration

  def up do
    alter table(:content_modules) do
      add :version, :integer, null: false, default: 1
      add :version_note, :text
      add :source_module_id, :bigint
      add :source_version, :integer
      add :acknowledged_version, :integer
    end

    alter table(:content_containers) do
      add :version, :integer, null: false, default: 1
      add :version_note, :text
      add :source_container_id, :bigint
      add :source_version, :integer
      add :acknowledged_version, :integer
    end

    alter table(:content_palettes) do
      add :version, :integer, null: false, default: 1
      add :version_note, :text
      add :source_palette_id, :bigint
      add :source_version, :integer
      add :acknowledged_version, :integer
    end

    alter table(:content_blocks) do
      add :module_origin, :text, null: false, default: "local"
      add :container_origin, :text, null: false, default: "local"
      add :palette_origin, :text, null: false, default: "local"
    end

    execute "ALTER TABLE content_blocks DROP CONSTRAINT IF EXISTS content_blocks_module_id_fkey"
    execute "ALTER TABLE content_blocks DROP CONSTRAINT IF EXISTS content_blocks_container_id_fkey"
    execute "ALTER TABLE content_blocks DROP CONSTRAINT IF EXISTS content_blocks_palette_id_fkey"
    execute "ALTER TABLE content_containers DROP CONSTRAINT IF EXISTS content_containers_palette_id_fkey"

    create unique_index(:content_modules, [:source_module_id], where: "source_module_id IS NOT NULL")

    create unique_index(:content_containers, [:source_container_id], where: "source_container_id IS NOT NULL")

    create unique_index(:content_palettes, [:source_palette_id], where: "source_palette_id IS NOT NULL")
    create index(:content_blocks, [:module_origin, :module_id])
    create index(:content_blocks, [:container_origin, :container_id])
    create index(:content_blocks, [:palette_origin, :palette_id])

    create table(:site_enabled_modules, prefix: "public") do
      add :site_id, references(:sites, prefix: "public", on_delete: :delete_all), null: false
      add :module_id, references(:content_modules, prefix: "public", on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:site_enabled_modules, [:site_id, :module_id], prefix: "public")

    create table(:site_enabled_containers, prefix: "public") do
      add :site_id, references(:sites, prefix: "public", on_delete: :delete_all), null: false
      add :container_id, references(:content_containers, prefix: "public", on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:site_enabled_containers, [:site_id, :container_id], prefix: "public")

    create table(:site_enabled_palettes, prefix: "public") do
      add :site_id, references(:sites, prefix: "public", on_delete: :delete_all), null: false
      add :palette_id, references(:content_palettes, prefix: "public", on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:site_enabled_palettes, [:site_id, :palette_id], prefix: "public")

    execute tenant_upgrade_sql()
  end

  def down do
    drop table(:site_enabled_palettes, prefix: "public")
    drop table(:site_enabled_containers, prefix: "public")
    drop table(:site_enabled_modules, prefix: "public")

    drop_if_exists index(:content_blocks, [:palette_origin, :palette_id])
    drop_if_exists index(:content_blocks, [:container_origin, :container_id])
    drop_if_exists index(:content_blocks, [:module_origin, :module_id])
    drop_if_exists unique_index(:content_palettes, [:source_palette_id])
    drop_if_exists unique_index(:content_containers, [:source_container_id])
    drop_if_exists unique_index(:content_modules, [:source_module_id])

    alter table(:content_blocks) do
      remove :palette_origin
      remove :container_origin
      remove :module_origin
    end

    alter table(:content_palettes) do
      remove :acknowledged_version
      remove :source_version
      remove :source_palette_id
      remove :version_note
      remove :version
    end

    alter table(:content_containers) do
      remove :acknowledged_version
      remove :source_version
      remove :source_container_id
      remove :version_note
      remove :version
    end

    alter table(:content_modules) do
      remove :acknowledged_version
      remove :source_version
      remove :source_module_id
      remove :version_note
      remove :version
    end
  end

  defp tenant_upgrade_sql do
    """
    DO $$
    DECLARE tenant_schema text;
    BEGIN
      FOR tenant_schema IN
        SELECT nspname FROM pg_namespace
        WHERE nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'
      LOOP
        IF to_regclass(format('%I.content_modules', tenant_schema)) IS NOT NULL THEN
          EXECUTE format('ALTER TABLE %I.content_modules ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1, ADD COLUMN IF NOT EXISTS version_note text, ADD COLUMN IF NOT EXISTS source_module_id bigint, ADD COLUMN IF NOT EXISTS source_version integer, ADD COLUMN IF NOT EXISTS acknowledged_version integer', tenant_schema);
          EXECUTE format('ALTER TABLE %I.content_modules DROP CONSTRAINT IF EXISTS content_modules_parent_id_fkey', tenant_schema);
          EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS %I ON %I.content_modules (source_module_id) WHERE source_module_id IS NOT NULL', tenant_schema || '_content_modules_source_module_id_index', tenant_schema);
        END IF;

        IF to_regclass(format('%I.content_containers', tenant_schema)) IS NOT NULL THEN
          EXECUTE format('ALTER TABLE %I.content_containers ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1, ADD COLUMN IF NOT EXISTS version_note text, ADD COLUMN IF NOT EXISTS source_container_id bigint, ADD COLUMN IF NOT EXISTS source_version integer, ADD COLUMN IF NOT EXISTS acknowledged_version integer', tenant_schema);
          EXECUTE format('ALTER TABLE %I.content_containers DROP CONSTRAINT IF EXISTS content_containers_palette_id_fkey', tenant_schema);
          EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS %I ON %I.content_containers (source_container_id) WHERE source_container_id IS NOT NULL', tenant_schema || '_content_containers_source_container_id_index', tenant_schema);
        END IF;

        IF to_regclass(format('%I.content_palettes', tenant_schema)) IS NOT NULL THEN
          EXECUTE format('ALTER TABLE %I.content_palettes ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1, ADD COLUMN IF NOT EXISTS version_note text, ADD COLUMN IF NOT EXISTS source_palette_id bigint, ADD COLUMN IF NOT EXISTS source_version integer, ADD COLUMN IF NOT EXISTS acknowledged_version integer', tenant_schema);
          EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS %I ON %I.content_palettes (source_palette_id) WHERE source_palette_id IS NOT NULL', tenant_schema || '_content_palettes_source_palette_id_index', tenant_schema);
        END IF;

        IF to_regclass(format('%I.content_blocks', tenant_schema)) IS NOT NULL THEN
          EXECUTE format('ALTER TABLE %I.content_blocks ADD COLUMN IF NOT EXISTS module_origin text NOT NULL DEFAULT ''local'', ADD COLUMN IF NOT EXISTS container_origin text NOT NULL DEFAULT ''local'', ADD COLUMN IF NOT EXISTS palette_origin text NOT NULL DEFAULT ''local''', tenant_schema);
          EXECUTE format('ALTER TABLE %I.content_blocks DROP CONSTRAINT IF EXISTS content_blocks_module_id_fkey', tenant_schema);
          EXECUTE format('ALTER TABLE %I.content_blocks DROP CONSTRAINT IF EXISTS content_blocks_container_id_fkey', tenant_schema);
          EXECUTE format('ALTER TABLE %I.content_blocks DROP CONSTRAINT IF EXISTS content_blocks_palette_id_fkey', tenant_schema);
          EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I.content_blocks (module_origin, module_id)', tenant_schema || '_content_blocks_module_origin_module_id_index', tenant_schema);
          EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I.content_blocks (container_origin, container_id)', tenant_schema || '_content_blocks_container_origin_container_id_index', tenant_schema);
          EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I.content_blocks (palette_origin, palette_id)', tenant_schema || '_content_blocks_palette_origin_palette_id_index', tenant_schema);
        END IF;
      END LOOP;
    END $$;
    """
  end
end
