defmodule Brando.Migrations.TransferRefGalleryData do
  use Ecto.Migration

  def up do
    # Process refs with GalleryBlock data
    # We need to create galleries and gallery_objects for each gallery ref

    # Create a temporary function to process gallery refs
    execute """
    CREATE OR REPLACE FUNCTION process_gallery_ref(ref_id bigint, ref_data jsonb)
    RETURNS integer AS $$
    DECLARE
      new_gallery_id integer;
      img_data jsonb;
      img_path text;
      size_path text;
      size_dir text;
      size_stem text;
      img_id integer;
      obj_config jsonb;
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
        img_id := NULL;

        -- Prefer the identity implied by `sizes` over `path`.
        --
        -- Legacy gallery data can carry a stale `path` alongside correct
        -- `sizes` — a replaced image wrote one but not the other. The old
        -- renderer read `sizes`, so those entries displayed the image `sizes`
        -- names, and matching `path` here would silently swap them for a
        -- different picture. `sizes` is what the site actually showed.
        --
        -- The size file may have a converted extension (a .png source renders
        -- to .jpg), so match on the stem within the source directory.
        SELECT value INTO size_path
        FROM jsonb_each_text(
          CASE WHEN jsonb_typeof(img_data->'sizes') = 'object'
               THEN img_data->'sizes' ELSE '{}'::jsonb END
        )
        WHERE value IS NOT NULL AND value <> ''
        LIMIT 1;

        IF size_path IS NOT NULL THEN
          -- strip "/<size>/<file>" to get the source directory
          size_dir := regexp_replace(size_path, '/[^/]+/[^/]+$', '');
          size_stem := regexp_replace(regexp_replace(size_path, '^.*/', ''), '\.[^.]+$', '');

          SELECT id INTO img_id
          FROM images
          WHERE regexp_replace(path, '\.[^.]+$', '') = (size_dir || '/' || size_stem)
          AND deleted_at IS NULL
          LIMIT 1;
        END IF;

        -- Fall back to `path` when there are no sizes, or when the image the
        -- sizes name is gone.
        IF img_id IS NULL THEN
          SELECT id INTO img_id
          FROM images
          WHERE path = img_path
          AND deleted_at IS NULL
          LIMIT 1;
        END IF;

        -- If image found, create gallery_object
        IF img_id IS NOT NULL THEN
          -- Carry the per-placement metadata across. The same image can sit in
          -- several galleries, or twice in one, with a different caption each
          -- time, so this belongs on the object rather than on the image.
          -- An absent key means "not overridden", matching what the admin writes.
          obj_config := '{}'::jsonb;

          IF COALESCE(img_data->>'title', '') <> '' THEN
            obj_config := obj_config || jsonb_build_object('title', img_data->>'title');
          END IF;

          IF COALESCE(img_data->>'alt', '') <> '' THEN
            obj_config := obj_config || jsonb_build_object('alt', img_data->>'alt');
          END IF;

          IF COALESCE(img_data->>'credits', '') <> '' THEN
            obj_config := obj_config || jsonb_build_object('credits', img_data->>'credits');
          END IF;

          INSERT INTO galleries_gallery_objects (
            gallery_id,
            image_id,
            sequence,
            config,
            inserted_at,
            updated_at
          ) VALUES (
            new_gallery_id,
            img_id,
            seq,
            obj_config,
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

    # Note: Gallery refs that couldn't be processed will have gallery_id = NULL
    # You can check for these manually if needed:
    # -- SELECT * FROM content_refs WHERE data->>'type' = 'gallery' AND gallery_id IS NULL;

    # Clean up the function
    execute "DROP FUNCTION process_gallery_ref(bigint, jsonb)"
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
