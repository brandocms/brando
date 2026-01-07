defmodule Brando.Migrations.ExtractVideoRefThumbnails do
  use Ecto.Migration

  def up do
    # Migration 133 preserved cover_image in the ref data - we need to extract it properly
    # Extract cover_image from video refs and create image entries
    # First handle direct VideoBlock refs
    execute """
    INSERT INTO images (
      path, width, height, formats, sizes, focal, cdn, 
      config_target, dominant_color, creator_id, 
      inserted_at, updated_at
    )
    SELECT DISTINCT ON (r.data->'data'->'cover_image'->>'path')
      r.data->'data'->'cover_image'->>'path',
      (r.data->'data'->'cover_image'->>'width')::integer,
      (r.data->'data'->'cover_image'->>'height')::integer,
      COALESCE(
        ARRAY(
          SELECT jsonb_array_elements_text(r.data->'data'->'cover_image'->'formats')
        ),
        ARRAY[]::text[]
      ),
      COALESCE(r.data->'data'->'cover_image'->'sizes', '{}'::jsonb),
      COALESCE(r.data->'data'->'cover_image'->'focal', 'false'::jsonb),
      COALESCE((r.data->'data'->'cover_image'->>'cdn')::boolean, false),
      COALESCE(r.data->'data'->'cover_image'->>'config_target', 'default'),
      r.data->'data'->'cover_image'->>'dominant_color',
      COALESCE(b.creator_id, 1),
      NOW(),
      NOW()
    FROM content_refs r
    LEFT JOIN content_blocks b ON r.block_id = b.id
    LEFT JOIN content_modules m ON r.module_id = m.id
    WHERE r.data->>'type' = 'video'
    AND r.data->'data'->'cover_image' IS NOT NULL
    AND r.data->'data'->'cover_image'->>'path' IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM images i 
      WHERE i.path = r.data->'data'->'cover_image'->>'path'
      AND i.deleted_at IS NULL
    )
    """

    # Update videos table with thumbnail_id for VideoBlock refs
    execute """
    UPDATE videos v
    SET thumbnail_id = i.id
    FROM content_refs r
    JOIN images i ON i.path = r.data->'data'->'cover_image'->>'path'
    WHERE r.video_id = v.id
    AND r.data->>'type' = 'video'
    AND r.data->'data'->'cover_image'->>'path' IS NOT NULL
    AND v.thumbnail_id IS NULL
    AND i.deleted_at IS NULL
    """

    # Handle MediaBlock refs with template_video cover_image
    execute """
    INSERT INTO images (
      path, width, height, formats, sizes, focal, cdn,
      config_target, dominant_color, creator_id,
      inserted_at, updated_at
    )
    SELECT DISTINCT ON (r.data->'data'->'template_video'->'cover_image'->>'path')
      r.data->'data'->'template_video'->'cover_image'->>'path',
      (r.data->'data'->'template_video'->'cover_image'->>'width')::integer,
      (r.data->'data'->'template_video'->'cover_image'->>'height')::integer,
      COALESCE(
        ARRAY(
          SELECT jsonb_array_elements_text(r.data->'data'->'template_video'->'cover_image'->'formats')
        ),
        ARRAY[]::text[]
      ),
      COALESCE(r.data->'data'->'template_video'->'cover_image'->'sizes', '{}'::jsonb),
      COALESCE(r.data->'data'->'template_video'->'cover_image'->'focal', 'false'::jsonb),
      COALESCE((r.data->'data'->'template_video'->'cover_image'->>'cdn')::boolean, false),
      COALESCE(r.data->'data'->'template_video'->'cover_image'->>'config_target', 'default'),
      r.data->'data'->'template_video'->'cover_image'->>'dominant_color',
      COALESCE(b.creator_id, 1),
      NOW(),
      NOW()
    FROM content_refs r
    LEFT JOIN content_blocks b ON r.block_id = b.id
    LEFT JOIN content_modules m ON r.module_id = m.id
    WHERE r.data->>'type' = 'media'
    AND r.data->'data'->'template_video'->'cover_image' IS NOT NULL
    AND r.data->'data'->'template_video'->'cover_image'->>'path' IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM images i
      WHERE i.path = r.data->'data'->'template_video'->'cover_image'->>'path'
      AND i.deleted_at IS NULL
    )
    """

    # Update videos table with thumbnail_id for MediaBlock refs
    execute """
    UPDATE videos v
    SET thumbnail_id = i.id
    FROM content_refs r
    JOIN images i ON i.path = r.data->'data'->'template_video'->'cover_image'->>'path'
    WHERE r.video_id = v.id
    AND r.data->>'type' = 'media'
    AND r.data->'data'->'template_video'->'cover_image'->>'path' IS NOT NULL
    AND v.thumbnail_id IS NULL
    AND i.deleted_at IS NULL
    """

    # Clean up the cover_image from ref data since it's now properly referenced
    # For VideoBlock refs
    execute """
    UPDATE content_refs
    SET data = jsonb_set(
      data,
      '{data}',
      (data->'data') - 'cover_image',
      false
    )
    WHERE data->>'type' = 'video'
    AND data->'data'->'cover_image' IS NOT NULL
    """

    # For MediaBlock refs with template_video
    execute """
    UPDATE content_refs
    SET data = jsonb_set(
      data,
      '{data,template_video}',
      (data->'data'->'template_video') - 'cover_image',
      false
    )
    WHERE data->>'type' = 'media'
    AND data->'data'->'template_video'->'cover_image' IS NOT NULL
    """
  end

  def down do
    # Restore cover_image data to VideoBlock refs
    execute """
    UPDATE content_refs r
    SET data = jsonb_set(
      data,
      '{data,cover_image}',
      jsonb_build_object(
        'path', i.path,
        'width', i.width,
        'height', i.height,
        'formats', to_jsonb(i.formats),
        'sizes', i.sizes,
        'focal', i.focal,
        'cdn', i.cdn,
        'config_target', i.config_target,
        'dominant_color', i.dominant_color
      ),
      true
    )
    FROM videos v
    JOIN images i ON v.thumbnail_id = i.id
    WHERE r.video_id = v.id
    AND r.data->>'type' = 'video'
    AND v.thumbnail_id IS NOT NULL
    """

    # Restore cover_image data to MediaBlock refs
    execute """
    UPDATE content_refs r
    SET data = jsonb_set(
      data,
      '{data,template_video,cover_image}',
      jsonb_build_object(
        'path', i.path,
        'width', i.width,
        'height', i.height,
        'formats', to_jsonb(i.formats),
        'sizes', i.sizes,
        'focal', i.focal,
        'cdn', i.cdn,
        'config_target', i.config_target,
        'dominant_color', i.dominant_color
      ),
      true
    )
    FROM videos v
    JOIN images i ON v.thumbnail_id = i.id
    WHERE r.video_id = v.id
    AND r.data->>'type' = 'media'
    AND v.thumbnail_id IS NOT NULL
    """

    # Remove thumbnail_id from videos that were set by this migration
    # Note: This is approximate since we can't track exactly which were set by this migration
    execute """
    UPDATE videos v
    SET thumbnail_id = NULL
    FROM content_refs r
    WHERE r.video_id = v.id
    AND (r.data->>'type' = 'video' OR r.data->>'type' = 'media')
    AND v.thumbnail_id IS NOT NULL
    """

    # Note: We don't delete the images since they might be used elsewhere
    # and we can't reliably track which ones were created by this migration
  end
end
