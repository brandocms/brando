defmodule Brando.Migrations.TransferRefGalleryData do
  use Ecto.Migration
  import Ecto.Query
  alias Brando.Repo

  def up do
    # Process refs with GalleryBlock data
    # We need to create galleries and gallery_objects for each gallery ref

    # Create a temporary function to process gallery refs
    execute """
    CREATE OR REPLACE FUNCTION process_gallery_ref(ref_id integer, ref_data jsonb)
    RETURNS integer AS $$
    DECLARE
      new_gallery_id integer;
      img_data jsonb;
      img_path text;
      img_id integer;
      seq integer := 0;
    BEGIN
      -- Create a new gallery
      INSERT INTO galleries (
        status,
        creator_id,
        inserted_at,
        updated_at
      ) VALUES (
        'published',
        1, -- Default creator, adjust as needed
        NOW(),
        NOW()
      ) RETURNING id INTO new_gallery_id;

      -- Process each image in the gallery
      FOR img_data IN SELECT * FROM jsonb_array_elements(ref_data->'images')
      LOOP
        img_path := img_data->>'path';

        -- Find the image in the images table
        SELECT id INTO img_id
        FROM images
        WHERE path = img_path
        AND deleted_at IS NULL
        LIMIT 1;

        -- If image found, create gallery_object
        IF img_id IS NOT NULL THEN
          INSERT INTO galleries_gallery_objects (
            gallery_id,
            image_id,
            sequence,
            inserted_at,
            updated_at
          ) VALUES (
            new_gallery_id,
            img_id,
            seq,
            NOW(),
            NOW()
          );

          seq := seq + 1;
        END IF;
      END LOOP;

      RETURN new_gallery_id;
    END;
    $$ LANGUAGE plpgsql;
    """

    # Process each gallery ref to create galleries and link images
    execute """
    UPDATE content_refs
    SET gallery_id = process_gallery_ref(id, data->'data')
    WHERE data->>'type' = 'gallery'
    AND data->'data'->'images' IS NOT NULL
    AND jsonb_array_length(data->'data'->'images') > 0
    """

    # Clean up galleries that ended up with no images (in case all images were missing)
    execute """
    DELETE FROM galleries g
    WHERE NOT EXISTS (
      SELECT 1 FROM galleries_gallery_objects go
      WHERE go.gallery_id = g.id
    )
    AND EXISTS (
      SELECT 1 FROM content_refs r
      WHERE r.gallery_id = g.id
    )
    """

    # Clear gallery_id for refs where gallery was deleted
    execute """
    UPDATE content_refs r
    SET gallery_id = NULL
    WHERE gallery_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM galleries g
      WHERE g.id = r.gallery_id
    )
    """

    # Log refs that couldn't be processed
    execute """
    INSERT INTO system_logs (level, message, metadata, inserted_at, updated_at)
    SELECT
      'warning',
      'Gallery ref could not be processed - no images found',
      jsonb_build_object(
        'ref_id', id,
        'ref_name', name,
        'image_count', jsonb_array_length(data->'data'->'images'),
        'module_id', module_id,
        'block_id', block_id
      ),
      NOW(),
      NOW()
    FROM content_refs
    WHERE data->>'type' = 'gallery'
    AND gallery_id IS NULL
    """

    # Clean up the function
    execute "DROP FUNCTION process_gallery_ref(integer, jsonb)"
  end

  def down do
    # Delete the gallery_objects for galleries created by this migration
    execute """
    DELETE FROM galleries_gallery_objects
    WHERE gallery_id IN (
      SELECT gallery_id FROM content_refs
      WHERE data->>'type' = 'gallery'
      AND gallery_id IS NOT NULL
    )
    """

    # Delete the galleries created by this migration
    execute """
    DELETE FROM galleries
    WHERE id IN (
      SELECT gallery_id FROM content_refs
      WHERE data->>'type' = 'gallery'
      AND gallery_id IS NOT NULL
    )
    """

    # Clear gallery references
    execute """
    UPDATE content_refs
    SET gallery_id = NULL
    WHERE data->>'type' = 'gallery'
    """
  end
end
