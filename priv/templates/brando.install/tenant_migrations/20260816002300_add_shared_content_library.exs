defmodule Brando.Repo.TenantMigrations.AddSharedContentLibrary do
  use Ecto.Migration

  def up do
    case prefix() do
      tenant_prefix when is_binary(tenant_prefix) -> execute(upgrade_sql(tenant_prefix))
      nil -> :ok
    end
  end

  def down, do: :ok

  defp upgrade_sql(tenant_prefix) do
    unless Regex.match?(~r/^tenant_[a-z0-9-]+_[a-z0-9-]+$/, tenant_prefix) do
      raise ArgumentError, "invalid tenant migration prefix: #{inspect(tenant_prefix)}"
    end

    """
    DO $$
    DECLARE tenant_schema text := '#{tenant_prefix}';
    BEGIN
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
    END $$;
    """
  end
end
