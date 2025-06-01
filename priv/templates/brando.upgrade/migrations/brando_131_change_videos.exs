defmodule Brando.Migrations.Videos.ChangeVideos do
  use Ecto.Migration

  def up do
    alter table(:videos) do
      # Add new fields
      add :type, :string
      add :title, :text
      add :caption, :text
      add :aspect_ratio, :string
      
      # Remove old fields that are being replaced
      remove :url
      remove :source
      remove :thumbnail_url
      remove :cdn
      
      # Rename cover_image_id to thumbnail_id for consistency
      remove :cover_image_id
      add :thumbnail_id, references(:images, on_delete: :nilify_all)
      
      # Add new file reference
      add :file_id, references(:files, on_delete: :nilify_all)
      
      # Add source_url for external videos
      add :source_url, :text
    end
    
    # Add index for type field for better query performance
    create index(:videos, [:type])
  end

  def down do
    drop index(:videos, [:type])
    
    alter table(:videos) do
      # Remove new fields
      remove :type
      remove :title
      remove :caption
      remove :aspect_ratio
      remove :source_url
      remove :file_id
      
      # Restore old fields
      add :url, :text
      add :source, :text
      add :thumbnail_url, :text
      add :cdn, :boolean
      
      # Restore cover_image_id
      remove :thumbnail_id
      add :cover_image_id, references(:images, on_delete: :nilify_all)
    end
  end
end