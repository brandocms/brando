defmodule Brando.Migrations.Videos.ChangeVideos do
  use Ecto.Migration

  def up do
    alter table(:videos) do
      # Add new fields
      add :type, :string
      add :title, :text
      add :caption, :text
      add :aspect_ratio, :string
      # Add source_url for external videos
      add :source_url, :text
    end

    flush()

    # The videos brando_95 made of embedded video fields, as brando_133 types
    # and addresses the videos of video refs: the provider's own type, or an
    # external file, and the url, or for an embed with only a remote id the
    # provider's URL built from it
    execute """
    UPDATE videos SET
      type = CASE source
        WHEN 'vimeo' THEN 'vimeo'
        WHEN 'youtube' THEN 'youtube'
        ELSE 'external_file'
      END,
      source_url = CASE
        WHEN source = 'vimeo' AND url IS NULL AND remote_id IS NOT NULL
        THEN 'https://vimeo.com/' || SPLIT_PART(remote_id, '?', 1)
        WHEN source = 'youtube' AND url IS NULL AND remote_id IS NOT NULL
        THEN 'https://www.youtube.com/watch?v=' || SPLIT_PART(remote_id, '?', 1)
        ELSE COALESCE(url, remote_id)
      END,
      -- The provider's id alone: the players add their own query to it
      remote_id = CASE
        WHEN source IN ('vimeo', 'youtube') THEN SPLIT_PART(remote_id, '?', 1)
        ELSE remote_id
      END
    WHERE type IS NULL AND COALESCE(url, remote_id) IS NOT NULL
    """

    alter table(:videos) do
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
