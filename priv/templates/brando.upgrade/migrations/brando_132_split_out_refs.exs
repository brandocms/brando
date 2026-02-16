defmodule Brando.Migrations.SplitOutRefs do
  use Ecto.Migration

  def up do
    # Create the refs table
    create table(:content_refs) do
      add :name, :text, null: false
      add :description, :text
      add :data, :jsonb
      add :sequence, :integer
      add :active, :boolean, default: true, null: false
      add :collapsed, :boolean, default: false, null: false

      # Foreign keys
      add :module_id, references(:content_modules, on_delete: :delete_all)
      add :block_id, references(:content_blocks, on_delete: :delete_all)
      add :gallery_id, references(:galleries, on_delete: :nilify_all)
      add :video_id, references(:videos, on_delete: :nilify_all)
      add :file_id, references(:files, on_delete: :nilify_all)
      add :image_id, references(:images, on_delete: :nilify_all)

      timestamps()
    end

    create index(:content_refs, [:module_id])
    create index(:content_refs, [:block_id])
    create index(:content_refs, [:gallery_id])
    create index(:content_refs, [:video_id])
    create index(:content_refs, [:file_id])
    create index(:content_refs, [:image_id])

    # Clean out invalid refs (entries with null names) before migrating
    execute """
    UPDATE content_modules
    SET refs = (
      SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb)
      FROM jsonb_array_elements(refs) AS elem
      WHERE elem->>'name' IS NOT NULL
    )
    WHERE refs IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(refs) AS elem
        WHERE elem->>'name' IS NULL
      )
    """

    execute """
    UPDATE content_blocks
    SET refs = (
      SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb)
      FROM jsonb_array_elements(refs) AS elem
      WHERE elem->>'name' IS NOT NULL
    )
    WHERE refs IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(refs) AS elem
        WHERE elem->>'name' IS NULL
      )
    """

    # Migrate data from embedded refs in modules
    # Since refs were embeds_many, they're stored as JSONB in the refs column
    execute """
    INSERT INTO content_refs (name, description, data, sequence, active, collapsed, module_id, inserted_at, updated_at)
    SELECT
      ref_data->>'name',
      ref_data->>'description',
      ref_data->'data',
      (row_number() OVER (PARTITION BY m.id ORDER BY ordinality)) - 1,
      COALESCE((ref_data->'data'->>'active')::boolean, true),
      COALESCE((ref_data->'data'->>'collapsed')::boolean, false),
      m.id,
      NOW(),
      NOW()
    FROM content_modules m
    CROSS JOIN LATERAL jsonb_array_elements(m.refs) WITH ORDINALITY AS t(ref_data, ordinality)
    WHERE m.refs IS NOT NULL AND jsonb_array_length(m.refs) > 0
      AND ref_data->>'name' IS NOT NULL
    """

    # Migrate data from embedded refs in blocks
    # Filter out refs with null names (stale/junk data)
    execute """
    INSERT INTO content_refs (name, description, data, sequence, active, collapsed, block_id, inserted_at, updated_at)
    SELECT
      ref_data->>'name',
      ref_data->>'description',
      ref_data->'data',
      (row_number() OVER (PARTITION BY b.id ORDER BY ordinality)) - 1,
      COALESCE((ref_data->'data'->>'active')::boolean, true),
      COALESCE((ref_data->'data'->>'collapsed')::boolean, false),
      b.id,
      NOW(),
      NOW()
    FROM content_blocks b
    CROSS JOIN LATERAL jsonb_array_elements(b.refs) WITH ORDINALITY AS t(ref_data, ordinality)
    WHERE b.refs IS NOT NULL AND jsonb_array_length(b.refs) > 0
      AND ref_data->>'name' IS NOT NULL
    """

    # Remove the refs column from modules and blocks since they now use has_many
    alter table(:content_modules) do
      remove :refs
    end

    alter table(:content_blocks) do
      remove :refs
    end
  end

  def down do
    # Re-add refs columns to modules and blocks
    alter table(:content_modules) do
      add :refs, :jsonb
    end

    alter table(:content_blocks) do
      add :refs, :jsonb
    end

    # Re-embed refs back into modules
    execute """
    UPDATE content_modules m
    SET refs = COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'name', r.name,
            'description', r.description,
            'data', r.data
          ) ORDER BY r.sequence
        )
        FROM content_refs r
        WHERE r.module_id = m.id
      ),
      '[]'::jsonb
    )
    WHERE EXISTS (SELECT 1 FROM content_refs WHERE module_id = m.id)
    """

    # Re-embed refs back into blocks
    execute """
    UPDATE content_blocks b
    SET refs = COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'name', r.name,
            'description', r.description,
            'data', r.data
          ) ORDER BY r.sequence
        )
        FROM content_refs r
        WHERE r.block_id = b.id
      ),
      '[]'::jsonb
    )
    WHERE EXISTS (SELECT 1 FROM content_refs WHERE block_id = b.id)
    """

    drop table(:content_refs)
  end
end