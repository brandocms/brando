defmodule Brando.Repo.Migrations.Brando245AddUidsToPalettesAndContainers do
  use Ecto.Migration

  @moduledoc """
  In every site environment, `content_palettes.uid` and
  `content_containers.uid` identify a palette and a container in definition
  files (`mix brando.modules export`), as `uid` does a module.

  Existing rows get one derived from what stays the same between two
  environments seeded alike: `palette-<namespace>-<key>` and
  `container-<namespace>-<name>`, lower-cased, with anything but letters and
  digits as `-`. A first export from either environment then adopts the
  other's rows instead of creating copies. A row whose uid is taken, by a
  module, table template, palette or container (one bundle holds all four
  kinds, and refuses a uid twice), gets `-2`, `-3`, … in id order, rows in
  the trash after the others. Rows that have a uid keep it, so the
  migration can run again.
  """

  def up do
    for prefix <- prefixes() do
      for table <- ~w(content_palettes content_containers)a do
        alter table(table, prefix: prefix) do
          add_if_not_exists :uid, :text
        end
      end

      flush()

      backfill(prefix, "content_palettes", "'palette-' || namespace || '-' || key")
      backfill(prefix, "content_containers", "'container-' || namespace || '-' || name")

      create_if_not_exists unique_index(:content_palettes, [:uid], prefix: prefix)
      create_if_not_exists unique_index(:content_containers, [:uid], prefix: prefix)
    end
  end

  def down do
    for prefix <- prefixes(), table <- ~w(content_palettes content_containers)a do
      drop_if_exists unique_index(table, [:uid], prefix: prefix)

      alter table(table, prefix: prefix) do
        remove_if_exists :uid, :text
      end
    end
  end

  # Each row without a uid gets its derived one, numbered from the second row
  # that derives it, and past any uid a definition of any kind has
  defp backfill(prefix, table, derived) do
    execute("""
    DO $$
    DECLARE
      row record;
      base text;
      candidate text;
      n integer;
    BEGIN
      FOR row IN
        SELECT id, trim(both '-' from regexp_replace(lower(coalesce(#{derived}, '')), '[^[:alnum:]]+', '-', 'g')) AS derived
        FROM "#{prefix}".#{table}
        WHERE uid IS NULL
        ORDER BY deleted_at IS NOT NULL, id
      LOOP
        base := CASE WHEN row.derived IN ('', 'palette', 'container') THEN row.derived || '-' || row.id ELSE row.derived END;
        candidate := base;
        n := 1;

        WHILE EXISTS (
          SELECT 1 FROM "#{prefix}".content_modules WHERE uid = candidate
          UNION ALL SELECT 1 FROM "#{prefix}".content_table_templates WHERE uid = candidate
          UNION ALL SELECT 1 FROM "#{prefix}".content_palettes WHERE uid = candidate
          UNION ALL SELECT 1 FROM "#{prefix}".content_containers WHERE uid = candidate
        ) LOOP
          n := n + 1;
          candidate := base || '-' || n;
        END LOOP;

        UPDATE "#{prefix}".#{table} SET uid = candidate WHERE id = row.id;
      END LOOP;
    END $$;
    """)
  end

  # Every site environment, or only the one named by the migrator's prefix:
  # `Brando.Environments.ArchiveUpgrade` runs this again in an archive
  # restored from before it ran.
  defp prefixes do
    case prefix() do
      "tenant_" <> _ = environment ->
        [environment]

      _ ->
        %{rows: rows} =
          repo().query!(
            "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
          )

        Enum.map(rows, &hd/1)
    end
  end
end
