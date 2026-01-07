defmodule Brando.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def up do
    # CRITICAL PRIORITY INDEXES
    # These provide the highest performance impact based on production query analysis
    
    # Gallery object lookups (very common pattern)
    create_if_not_exists index(:galleries_gallery_objects, [:gallery_id], 
      name: :idx_galleries_gallery_objects_gallery_id
    )
    
    # Revisions table optimization (currently slowest query at 47.8ms)
    # Query pattern: ORDER BY revision DESC, so we need DESC in the index
    execute "CREATE INDEX IF NOT EXISTS idx_revisions_entry_lookup_desc ON revisions (entry_id, entry_type, revision DESC)"
    
    # Content identifiers - schema and status filtering
    create_if_not_exists index(:content_identifiers, [:schema, :status], 
      name: :idx_content_identifiers_schema_status
    )
    
    # HIGH PRIORITY INDEXES
    # Significant performance impact for specific use cases
    
    # Content template-block relationships
    create_if_not_exists index(:content_templates_blocks, [:entry_id], 
      name: :idx_content_templates_blocks_entry_id
    )
    
    create_if_not_exists index(:pages_fragments_blocks, [:entry_id], 
      name: :idx_pages_fragments_blocks_entry_id
    )
    
    # Content blocks parent-child lookups with sequence ordering
    # Query pattern: ORDER BY sequence, so we optimize for that
    create_if_not_exists index(:content_blocks, [:parent_id, :sequence], 
      name: :idx_content_blocks_parent_id_sequence
    )
    
    # Images status filtering for processed images (partial index)
    execute "CREATE INDEX IF NOT EXISTS idx_images_status_processed ON images (status) WHERE status = 'processed'"
    
    # MEDIUM PRIORITY INDEXES
    # Query-specific optimizations for better sorting and complex queries
    
    # Sequence ordering indexes for consistent sorting
    create_if_not_exists index(:content_vars, [:sequence], 
      name: :idx_content_vars_sequence
    )
    
    create_if_not_exists index(:content_table_rows, [:sequence], 
      name: :idx_content_table_rows_sequence
    )
    
    create_if_not_exists index(:galleries_gallery_objects, [:sequence], 
      name: :idx_galleries_gallery_objects_sequence
    )
    
    # Multi-column indexes for complex queries with sequence ordering
    create_if_not_exists index(:content_vars, [:module_id, :sequence], 
      name: :idx_content_vars_module_id_sequence
    )
    
    create_if_not_exists index(:content_vars, [:block_id, :sequence], 
      name: :idx_content_vars_block_id_sequence
    )
    
    # Module queries with deleted_at filtering and sequence ordering (partial index)
    execute "CREATE INDEX IF NOT EXISTS idx_content_modules_deleted_at_sequence ON content_modules (deleted_at, sequence) WHERE deleted_at IS NULL"
  end

  def down do
    # Remove indexes in reverse order
    execute "DROP INDEX IF EXISTS idx_content_modules_deleted_at_sequence"
    
    drop_if_exists index(:content_vars, [:block_id, :sequence], 
      name: :idx_content_vars_block_id_sequence
    )
    
    drop_if_exists index(:content_vars, [:module_id, :sequence], 
      name: :idx_content_vars_module_id_sequence
    )
    
    drop_if_exists index(:galleries_gallery_objects, [:sequence], 
      name: :idx_galleries_gallery_objects_sequence
    )
    
    drop_if_exists index(:content_table_rows, [:sequence], 
      name: :idx_content_table_rows_sequence
    )
    
    drop_if_exists index(:content_vars, [:sequence], 
      name: :idx_content_vars_sequence
    )
    
    execute "DROP INDEX IF EXISTS idx_images_status_processed"
    
    drop_if_exists index(:content_blocks, [:parent_id, :sequence], 
      name: :idx_content_blocks_parent_id_sequence
    )
    
    drop_if_exists index(:pages_fragments_blocks, [:entry_id], 
      name: :idx_pages_fragments_blocks_entry_id
    )
    
    drop_if_exists index(:content_templates_blocks, [:entry_id], 
      name: :idx_content_templates_blocks_entry_id
    )
    
    drop_if_exists index(:content_identifiers, [:schema, :status], 
      name: :idx_content_identifiers_schema_status
    )
    
    execute "DROP INDEX IF EXISTS idx_revisions_entry_lookup_desc"
    
    drop_if_exists index(:galleries_gallery_objects, [:gallery_id], 
      name: :idx_galleries_gallery_objects_gallery_id
    )
  end
end