defmodule Brando.Migrations.SplitOutRefs do
  use Ecto.Migration
  import Ecto.Query

  def up do
    # Create the refs table
    create table(:content_refs) do
      add :name, :text, null: false
      add :description, :text
      add :data, :jsonb
      add :sequence, :integer
      
      # Foreign keys
      add :module_id, references(:content_modules, on_delete: :delete_all)
      add :block_id, references(:content_blocks, on_delete: :delete_all)
      add :gallery_id, references(:images_galleries, on_delete: :nilify_all)
      add :video_id, references(:videos_videos, on_delete: :nilify_all)
      add :file_id, references(:files_files, on_delete: :nilify_all)
      add :image_id, references(:images_images, on_delete: :nilify_all)
      
      timestamps()
    end
    
    create index(:content_refs, [:module_id])
    create index(:content_refs, [:block_id])
    create index(:content_refs, [:gallery_id])
    create index(:content_refs, [:video_id])
    create index(:content_refs, [:file_id])
    create index(:content_refs, [:image_id])
    
    # Migrate data from embedded refs in modules
    execute """
    INSERT INTO content_refs (name, description, data, sequence, module_id, inserted_at, updated_at)
    SELECT 
      ref->>'name',
      ref->>'description',
      ref->'data',
      (row_number() OVER (PARTITION BY m.id ORDER BY ordinality)) - 1,
      m.id,
      NOW(),
      NOW()
    FROM content_modules m
    CROSS JOIN LATERAL jsonb_array_elements(m.data->'refs') WITH ORDINALITY AS ref
    WHERE m.data ? 'refs' AND jsonb_array_length(m.data->'refs') > 0
    """
    
    # Migrate data from embedded refs in blocks
    execute """
    INSERT INTO content_refs (name, description, data, sequence, block_id, inserted_at, updated_at)
    SELECT 
      ref->>'name',
      ref->>'description',
      ref->'data',
      (row_number() OVER (PARTITION BY b.id ORDER BY ordinality)) - 1,
      b.id,
      NOW(),
      NOW()
    FROM content_blocks b
    CROSS JOIN LATERAL jsonb_array_elements(b.data->'refs') WITH ORDINALITY AS ref
    WHERE b.data ? 'refs' AND jsonb_array_length(b.data->'refs') > 0
    """
    
    # Process refs to extract image_id, video_id, gallery_id references
    # This will need to be done in a separate data migration after analyzing the data structure
    
    # Remove refs from module and block data columns
    execute "UPDATE content_modules SET data = data - 'refs' WHERE data ? 'refs'"
    execute "UPDATE content_blocks SET data = data - 'refs' WHERE data ? 'refs'"
  end
  
  def down do
    # Re-embed refs back into modules
    execute """
    UPDATE content_modules m
    SET data = jsonb_set(
      COALESCE(m.data, '{}'::jsonb),
      '{refs}',
      COALESCE(
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
    )
    WHERE EXISTS (SELECT 1 FROM content_refs WHERE module_id = m.id)
    """
    
    # Re-embed refs back into blocks
    execute """
    UPDATE content_blocks b
    SET data = jsonb_set(
      COALESCE(b.data, '{}'::jsonb),
      '{refs}',
      COALESCE(
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
    )
    WHERE EXISTS (SELECT 1 FROM content_refs WHERE block_id = b.id)
    """
    
    drop table(:content_refs)
  end
end