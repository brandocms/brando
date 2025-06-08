defmodule Brando.Migrations.TransferRefMediaData do
  use Ecto.Migration
  import Ecto.Query
  alias Brando.Repo

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

    # Process refs with VideoBlock data
    # First, create video entries for file-based videos
    execute """
    INSERT INTO videos (
      url, source, remote_id, width, height,
      thumbnail_url, title, status,
      inserted_at, updated_at, creator_id
    )
    SELECT DISTINCT ON (r.data->'data'->>'url')
      r.data->'data'->>'url',
      (r.data->'data'->>'source')::text,
      r.data->'data'->>'remote_id',
      (r.data->'data'->>'width')::integer,
      (r.data->'data'->>'height')::integer,
      r.data->'data'->>'thumbnail_url',
      r.data->'data'->>'title',
      'ready',
      NOW(),
      NOW(),
      1 -- Default creator_id, should be adjusted based on your needs
    FROM content_refs r
    WHERE r.data->>'type' = 'video'
    AND r.data->'data'->>'url' IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM videos v
      WHERE v.url = r.data->'data'->>'url'
    )
    """

    # Update refs with video_id
    execute """
    UPDATE content_refs r
    SET video_id = v.id
    FROM videos v
    WHERE r.data->>'type' = 'video'
    AND v.url = r.data->'data'->>'url'
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
    # For galleries, we need to find or create the gallery and link it
    # This is complex as we need to match embedded images to gallery_objects
    # For now, we'll keep the gallery data but remove the images array
    execute """
    UPDATE content_refs
    SET data = jsonb_build_object(
      'type', 'gallery',
      'data', data->'data' - 'images'
    )
    WHERE data->>'type' = 'gallery'
    """

    # Process MediaBlock refs that contain template_picture or template_video
    execute """
    UPDATE content_refs r
    SET image_id = i.id
    FROM images i
    WHERE r.data->>'type' = 'media'
    AND r.data->'data'->'template_picture'->>'path' = i.path
    AND i.deleted_at IS NULL
    """

    execute """
    UPDATE content_refs r
    SET video_id = v.id
    FROM videos v
    WHERE r.data->>'type' = 'media'
    AND r.data->'data'->'template_video'->>'url' = v.url
    """

    # Clean up MediaBlock data
    execute """
    UPDATE content_refs
    SET data = jsonb_build_object(
      'type', 'media',
      'data', jsonb_build_object(
        'available_blocks', data->'data'->'available_blocks',
        'template_gallery', data->'data'->'template_gallery' - 'images',
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
        'url', v.url,
        'source', v.source,
        'remote_id', v.remote_id,
        'width', v.width,
        'height', v.height,
        'thumbnail_url', v.thumbnail_url
      ) || COALESCE(r.data->'data', '{}'::jsonb)
    )
    FROM videos_videos v
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
    DELETE FROM videos_videos v
    WHERE v.inserted_at >= (SELECT MAX(inserted_at) FROM content_refs WHERE video_id IS NOT NULL)
    AND NOT EXISTS (
      SELECT 1 FROM content_refs r
      WHERE r.video_id = v.id
      AND r.inserted_at < v.inserted_at
    )
    """
  end
end
