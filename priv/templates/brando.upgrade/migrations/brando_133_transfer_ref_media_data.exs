defmodule Brando.Migrations.TransferRefMediaData do
  use Ecto.Migration

  def up do
    # Process refs with PictureBlock data to extract image_id
    execute """
    UPDATE content_refs r
    SET image_id = i.id
    FROM images i
    WHERE r.data->>'type' = 'picture'
    AND i.path = r.data->'data'->>'path'
    AND i.deleted_at IS NULL
    """

    # Process refs with VideoBlock data
    # First, create video entries using the new video schema
    # IMPORTANT: Do this BEFORE cleaning up the ref data
    # Use COALESCE to handle both url and remote_id as the video source
    execute """
    INSERT INTO videos (
      source_url, type, title, caption, aspect_ratio,
      width, height, remote_id,
      inserted_at, updated_at, creator_id
    )
    SELECT DISTINCT ON (COALESCE(r.data->'data'->>'url', r.data->'data'->>'remote_id'))
      CASE 
        -- For vimeo videos without url, construct the vimeo.com URL from remote_id
        WHEN r.data->'data'->>'source' = 'vimeo' 
             AND r.data->'data'->>'url' IS NULL 
             AND r.data->'data'->>'remote_id' IS NOT NULL
        THEN 'https://vimeo.com/' || SPLIT_PART(r.data->'data'->>'remote_id', '?', 1)
        -- For youtube videos without url, construct the youtube.com URL from remote_id  
        WHEN r.data->'data'->>'source' = 'youtube' 
             AND r.data->'data'->>'url' IS NULL 
             AND r.data->'data'->>'remote_id' IS NOT NULL
        THEN 'https://www.youtube.com/watch?v=' || SPLIT_PART(r.data->'data'->>'remote_id', '?', 1)
        -- Otherwise use the existing logic
        ELSE COALESCE(r.data->'data'->>'url', r.data->'data'->>'remote_id')
      END,
      CASE
        WHEN r.data->'data'->>'source' = 'file' THEN 'external_file'
        WHEN r.data->'data'->>'source' = 'youtube' THEN 'youtube'
        WHEN r.data->'data'->>'source' = 'vimeo' THEN 'vimeo'
        ELSE 'external_file'
      END,
      r.data->'data'->>'title',
      r.data->'data'->>'title', -- Use title as caption for now
      r.data->'data'->>'aspect_ratio',
      (r.data->'data'->>'width')::integer,
      (r.data->'data'->>'height')::integer,
      -- Store clean remote_id based on video type and data availability
      CASE 
        -- For vimeo/youtube, extract clean video ID from remote_id (remove query params)
        WHEN r.data->'data'->>'source' IN ('vimeo', 'youtube') AND r.data->'data'->>'remote_id' IS NOT NULL
        THEN SPLIT_PART(r.data->'data'->>'remote_id', '?', 1)
        -- For file type, never store remote_id (it's always the same as source_url)
        ELSE NULL
      END,
      NOW(),
      NOW(),
      1 -- Default creator_id, should be adjusted based on your needs
    FROM content_refs r
    WHERE r.data->>'type' = 'video'
    AND COALESCE(r.data->'data'->>'url', r.data->'data'->>'remote_id') IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM videos v
      WHERE v.source_url = COALESCE(r.data->'data'->>'url', r.data->'data'->>'remote_id')
    )
    """

    # Update refs with video_id using new schema
    # IMPORTANT: Do this BEFORE cleaning up the ref data
    execute """
    UPDATE content_refs r
    SET video_id = v.id
    FROM videos v
    WHERE r.data->>'type' = 'video'
    AND v.source_url = COALESCE(r.data->'data'->>'url', r.data->'data'->>'remote_id')
    """

    # Process MediaBlock refs that contain template_video
    # IMPORTANT: Do this BEFORE cleaning up the MediaBlock data
    # Use COALESCE to handle both url and remote_id as the video source
    execute """
    INSERT INTO videos (
      source_url, type, title, caption, aspect_ratio,
      width, height, remote_id,
      inserted_at, updated_at, creator_id
    )
    SELECT DISTINCT ON (COALESCE(r.data->'data'->'template_video'->>'url', r.data->'data'->'template_video'->>'remote_id'))
      CASE 
        -- For vimeo videos without url, construct the vimeo.com URL from remote_id
        WHEN r.data->'data'->'template_video'->>'source' = 'vimeo' 
             AND r.data->'data'->'template_video'->>'url' IS NULL 
             AND r.data->'data'->'template_video'->>'remote_id' IS NOT NULL
        THEN 'https://vimeo.com/' || SPLIT_PART(r.data->'data'->'template_video'->>'remote_id', '?', 1)
        -- For youtube videos without url, construct the youtube.com URL from remote_id  
        WHEN r.data->'data'->'template_video'->>'source' = 'youtube' 
             AND r.data->'data'->'template_video'->>'url' IS NULL 
             AND r.data->'data'->'template_video'->>'remote_id' IS NOT NULL
        THEN 'https://www.youtube.com/watch?v=' || SPLIT_PART(r.data->'data'->'template_video'->>'remote_id', '?', 1)
        -- Otherwise use the existing logic
        ELSE COALESCE(r.data->'data'->'template_video'->>'url', r.data->'data'->'template_video'->>'remote_id')
      END,
      CASE
        WHEN r.data->'data'->'template_video'->>'source' = 'file' THEN 'external_file'
        WHEN r.data->'data'->'template_video'->>'source' = 'youtube' THEN 'youtube'
        WHEN r.data->'data'->'template_video'->>'source' = 'vimeo' THEN 'vimeo'
        ELSE 'external_file'
      END,
      r.data->'data'->'template_video'->>'title',
      r.data->'data'->'template_video'->>'title',
      r.data->'data'->'template_video'->>'aspect_ratio',
      (r.data->'data'->'template_video'->>'width')::integer,
      (r.data->'data'->'template_video'->>'height')::integer,
      -- Store clean remote_id based on video type and data availability
      CASE 
        -- For vimeo/youtube, extract clean video ID from remote_id (remove query params)
        WHEN r.data->'data'->'template_video'->>'source' IN ('vimeo', 'youtube') AND r.data->'data'->'template_video'->>'remote_id' IS NOT NULL
        THEN SPLIT_PART(r.data->'data'->'template_video'->>'remote_id', '?', 1)
        -- For file type, never store remote_id (it's always the same as source_url)
        ELSE NULL
      END,
      NOW(),
      NOW(),
      1
    FROM content_refs r
    WHERE r.data->>'type' = 'media'
    AND COALESCE(r.data->'data'->'template_video'->>'url', r.data->'data'->'template_video'->>'remote_id') IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM videos v
      WHERE v.source_url = COALESCE(r.data->'data'->'template_video'->>'url', r.data->'data'->'template_video'->>'remote_id')
    )
    """

    # Link MediaBlock refs to videos
    execute """
    UPDATE content_refs r
    SET video_id = v.id
    FROM videos v
    WHERE r.data->>'type' = 'media'
    AND v.source_url = COALESCE(r.data->'data'->'template_video'->>'url', r.data->'data'->'template_video'->>'remote_id')
    """

    # Process MediaBlock refs that contain template_picture
    execute """
    UPDATE content_refs r
    SET image_id = i.id
    FROM images i
    WHERE r.data->>'type' = 'media'
    AND r.data->'data'->'template_picture'->>'path' = i.path
    AND i.deleted_at IS NULL
    """

    # NOW clean up the ref data - do this AFTER creating videos and linking refs

    # Clean up PictureBlock data - keep only override fields
    # Based on the updated schema, we keep: title, credits, alt, picture_class,
    # img_class, link, srcset, media_queries, lazyload, moonwalk, placeholder, fetchpriority
    execute """
    UPDATE content_refs
    SET data = jsonb_build_object(
      'type', 'picture',
      'data', jsonb_strip_nulls(
        jsonb_build_object(
          'title', data->'data'->>'title',
          'credits', data->'data'->>'credits',
          'alt', data->'data'->>'alt',
          'picture_class', data->'data'->>'picture_class',
          'img_class', data->'data'->>'img_class',
          'link', data->'data'->>'link',
          'srcset', data->'data'->>'srcset',
          'media_queries', data->'data'->>'media_queries',
          'lazyload', data->'data'->'lazyload',
          'moonwalk', data->'data'->'moonwalk',
          'placeholder', data->'data'->>'placeholder',
          'fetchpriority', data->'data'->>'fetchpriority'
        )
      )
    )
    WHERE data->>'type' = 'picture'
    """

    # Clean up VideoBlock data - keep only override fields
    # Based on the updated schema, we keep: title, poster, autoplay, opacity,
    # preload, play_button, controls, cover, aspect_ratio, cover_image
    execute """
    UPDATE content_refs
    SET data = jsonb_build_object(
      'type', 'video',
      'data', jsonb_strip_nulls(
        jsonb_build_object(
          'title', data->'data'->>'title',
          'poster', data->'data'->>'poster',
          'autoplay', data->'data'->'autoplay',
          'opacity', data->'data'->'opacity',
          'preload', data->'data'->'preload',
          'play_button', data->'data'->'play_button',
          'controls', data->'data'->'controls',
          'cover', data->'data'->>'cover',
          'aspect_ratio', data->'data'->>'aspect_ratio',
          'cover_image', data->'data'->'cover_image'
        )
      )
    )
    WHERE data->>'type' = 'video'
    """

    # Process refs with GalleryBlock data
    # First, create galleries from gallery refs
    execute """
    INSERT INTO galleries (
      config_target, creator_id,
      inserted_at, updated_at
    )
    SELECT DISTINCT ON (r.data->>'uid')
      'default',
      COALESCE(b.creator_id, 1),
      NOW(),
      NOW()
    FROM content_refs r
    LEFT JOIN content_blocks b ON r.block_id = b.id
    WHERE r.data->>'type' = 'gallery'
    AND r.data->'data' IS NOT NULL
    AND r.data->>'uid' IS NOT NULL
    AND r.data->'data'->'images' IS NOT NULL
    AND jsonb_array_length(r.data->'data'->'images') > 0
    """

    # Create gallery_objects for each image in the gallery
    # We need to match each ref to its corresponding gallery by order
    execute """
    INSERT INTO galleries_gallery_objects (
      gallery_id, image_id, sequence, creator_id,
      inserted_at, updated_at
    )
    WITH ref_galleries AS (
      SELECT 
        r.id as ref_id,
        ROW_NUMBER() OVER (ORDER BY r.id) as ref_order
      FROM content_refs r
      WHERE r.data->>'type' = 'gallery'
      AND r.data->'data' IS NOT NULL
      AND r.data->>'uid' IS NOT NULL
      AND r.data->'data'->'images' IS NOT NULL
      AND jsonb_array_length(r.data->'data'->'images') > 0
    ),
    gallery_ids AS (
      SELECT 
        id,
        ROW_NUMBER() OVER (ORDER BY id) as gallery_order
      FROM galleries
      WHERE config_target = 'default'
    )
    SELECT 
      gi.id,
      i.id,
      (row_number() OVER (PARTITION BY gi.id ORDER BY img_ord)) - 1,
      COALESCE(b.creator_id, 1),
      NOW(),
      NOW()
    FROM content_refs r
    CROSS JOIN LATERAL jsonb_array_elements(r.data->'data'->'images') WITH ORDINALITY AS imgs(img_data, img_ord)
    INNER JOIN ref_galleries rg ON r.id = rg.ref_id
    INNER JOIN gallery_ids gi ON rg.ref_order = gi.gallery_order
    INNER JOIN images i ON i.path = imgs.img_data->>'path' AND i.deleted_at IS NULL
    LEFT JOIN content_blocks b ON r.block_id = b.id
    WHERE r.data->>'type' = 'gallery'
    """

    # Update refs with gallery_id - we need a way to link each ref to its specific gallery
    # Since we can't use config_target anymore, we'll need to match by the gallery creation order
    execute """
    WITH gallery_mapping AS (
      SELECT 
        r.id as ref_id,
        ROW_NUMBER() OVER (ORDER BY r.id) as gallery_order
      FROM content_refs r
      WHERE r.data->>'type' = 'gallery'
      AND r.data->'data' IS NOT NULL
      AND r.data->>'uid' IS NOT NULL
      AND r.data->'data'->'images' IS NOT NULL
      AND jsonb_array_length(r.data->'data'->'images') > 0
    ),
    gallery_ids AS (
      SELECT 
        id,
        ROW_NUMBER() OVER (ORDER BY id) as gallery_order
      FROM galleries
      WHERE config_target = 'default'
    )
    UPDATE content_refs r
    SET gallery_id = gi.id
    FROM gallery_mapping gm
    JOIN gallery_ids gi ON gm.gallery_order = gi.gallery_order
    WHERE r.id = gm.ref_id
    """

    # Clean up gallery data - remove the images array
    execute """
    UPDATE content_refs
    SET data = jsonb_build_object(
      'type', 'gallery',
      'data', (data->'data')::jsonb - 'images'
    )
    WHERE data->>'type' = 'gallery'
    """

    # Clean up MediaBlock data
    execute """
    UPDATE content_refs
    SET data = jsonb_build_object(
      'type', 'media',
      'data', jsonb_build_object(
        'available_blocks', data->'data'->'available_blocks',
        'template_gallery',
          CASE
            WHEN data->'data'->'template_gallery' IS NOT NULL
            AND jsonb_typeof(data->'data'->'template_gallery') = 'object' THEN
              (data->'data'->'template_gallery')::jsonb - 'images'
            ELSE data->'data'->'template_gallery'
          END,
        'template_picture',
          CASE
            WHEN data->'data'->>'template_picture' IS NOT NULL THEN
              jsonb_strip_nulls(
                jsonb_build_object(
                  'title', data->'data'->'template_picture'->>'title',
                  'credits', data->'data'->'template_picture'->>'credits',
                  'alt', data->'data'->'template_picture'->>'alt',
                  'picture_class', data->'data'->'template_picture'->>'picture_class',
                  'img_class', data->'data'->'template_picture'->>'img_class',
                  'link', data->'data'->'template_picture'->>'link',
                  'srcset', data->'data'->'template_picture'->>'srcset',
                  'media_queries', data->'data'->'template_picture'->>'media_queries',
                  'lazyload', data->'data'->'template_picture'->'lazyload',
                  'moonwalk', data->'data'->'template_picture'->'moonwalk',
                  'placeholder', data->'data'->'template_picture'->>'placeholder',
                  'fetchpriority', data->'data'->'template_picture'->>'fetchpriority'
                )
              )
            ELSE NULL
          END,
        'template_video',
          CASE
            WHEN data->'data'->>'template_video' IS NOT NULL THEN
              jsonb_strip_nulls(
                jsonb_build_object(
                  'title', data->'data'->'template_video'->>'title',
                  'poster', data->'data'->'template_video'->>'poster',
                  'autoplay', data->'data'->'template_video'->'autoplay',
                  'opacity', data->'data'->'template_video'->'opacity',
                  'preload', data->'data'->'template_video'->'preload',
                  'play_button', data->'data'->'template_video'->'play_button',
                  'controls', data->'data'->'template_video'->'controls',
                  'cover', data->'data'->'template_video'->>'cover',
                  'aspect_ratio', data->'data'->'template_video'->>'aspect_ratio',
                  'cover_image', data->'data'->'template_video'->'cover_image'
                )
              )
            ELSE NULL
          END
      )
    )
    WHERE data->>'type' = 'media'
    """
  end

  def down do
    # Restore full image data from images table
    execute """
    UPDATE content_refs r
    SET data = jsonb_build_object(
      'type', 'picture',
      'data', jsonb_build_object(
        'path', i.path,
        'formats', to_jsonb(i.formats),
        'width', i.width,
        'height', i.height,
        'cdn', i.cdn,
        'config_target', i.config_target,
        'focal', i.focal,
        'sizes', i.sizes,
        'dominant_color', i.dominant_color
      ) || COALESCE(r.data->'data', '{}'::jsonb)
    )
    FROM images i
    WHERE r.image_id = i.id
    AND r.data->>'type' = 'picture'
    """

    # Restore full video data from videos table
    execute """
    UPDATE content_refs r
    SET data = jsonb_build_object(
      'type', 'video',
      'data', jsonb_build_object(
        'url', v.source_url,
        'source', CASE
          WHEN v.type = 'upload' THEN 'file'
          WHEN v.type = 'youtube' THEN 'youtube'
          WHEN v.type = 'vimeo' THEN 'vimeo'
          WHEN v.type = 'external_file' THEN 'external'
          ELSE v.type
        END,
        'remote_id', v.remote_id,
        'width', v.width,
        'height', v.height,
        'title', v.title,
        'aspect_ratio', v.aspect_ratio
      ) || COALESCE(r.data->'data', '{}'::jsonb)
    )
    FROM videos v
    WHERE r.video_id = v.id
    AND r.data->>'type' = 'video'
    """

    # Clear the foreign key references
    execute "UPDATE content_refs SET image_id = NULL WHERE image_id IS NOT NULL"
    execute "UPDATE content_refs SET video_id = NULL WHERE video_id IS NOT NULL"
    execute "UPDATE content_refs SET gallery_id = NULL WHERE gallery_id IS NOT NULL"

    # Delete videos that were created by this migration
    # (This is a simplified approach - in production you'd want to track which were created)
    execute """
    DELETE FROM videos v
    WHERE v.inserted_at >= (SELECT MAX(inserted_at) FROM content_refs WHERE video_id IS NOT NULL)
    AND NOT EXISTS (
      SELECT 1 FROM content_refs r
      WHERE r.video_id = v.id
      AND r.inserted_at < v.inserted_at
    )
    """
  end
end
