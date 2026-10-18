defmodule Brando.Migrations.TransferRefMediaData do
  use Ecto.Migration

  def up do
    # Postgres can't estimate how many refs the jsonb filters below select,
    # takes it for one, and joins every ref against every image in a nested
    # loop: minutes for 20,000 refs and 50,000 images, against a second with
    # hash joins. Until the gallery objects are made.
    execute "SET LOCAL enable_nestloop = off"

    # Link each picture ref to the image its legacy data shows (see
    # resolve_images/1). A picture whose image has no live row, because the
    # row was deleted or never made, was still shown by 0.53 from the ref's
    # own data: make the row from that data, then link the ref to it.
    # IMPORTANT: Do this BEFORE cleaning up the ref data
    execute link_pictures()
    execute insert_images(picture_items())
    execute link_pictures()

    # Process refs with VideoBlock data
    # First, create video entries using the new video schema
    # IMPORTANT: Do this BEFORE cleaning up the ref data
    # One video per source (video_source/1), with the first block's settings;
    # the link below matches on the same expression
    execute """
    INSERT INTO videos (
      source_url, type, title, caption, aspect_ratio,
      width, height, remote_id, config_target,
      inserted_at, updated_at, creator_id
    )
    SELECT DISTINCT ON (#{video_source("r.data->'data'")})
      #{video_source("r.data->'data'")},
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
      'default', -- config_target
      NOW(),
      NOW(),
      1 -- legacy refs carry no creator; credit the first user
    FROM content_refs r
    WHERE r.data->>'type' = 'video'
    AND COALESCE(r.data->'data'->>'url', r.data->'data'->>'remote_id') IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM videos v
      WHERE v.source_url = #{video_source("r.data->'data'")}
    )
    ORDER BY #{video_source("r.data->'data'")}, r.id
    """

    # Update refs with video_id using new schema
    # IMPORTANT: Do this BEFORE cleaning up the ref data
    execute """
    UPDATE content_refs r
    SET video_id = v.id
    FROM videos v
    WHERE r.data->>'type' = 'video'
    AND v.source_url = #{video_source("r.data->'data'")}
    """

    execute keep_own_shape("video", ["data"])

    # Process MediaBlock refs that contain template_video
    # IMPORTANT: Do this BEFORE cleaning up the MediaBlock data
    # Same as for video refs above
    execute """
    INSERT INTO videos (
      source_url, type, title, caption, aspect_ratio,
      width, height, remote_id, config_target,
      inserted_at, updated_at, creator_id
    )
    SELECT DISTINCT ON (#{video_source("r.data->'data'->'template_video'")})
      #{video_source("r.data->'data'->'template_video'")},
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
      'default', -- config_target
      NOW(),
      NOW(),
      1
    FROM content_refs r
    WHERE r.data->>'type' = 'media'
    AND COALESCE(r.data->'data'->'template_video'->>'url', r.data->'data'->'template_video'->>'remote_id') IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM videos v
      WHERE v.source_url = #{video_source("r.data->'data'->'template_video'")}
    )
    ORDER BY #{video_source("r.data->'data'->'template_video'")}, r.id
    """

    # Link MediaBlock refs to videos
    execute """
    UPDATE content_refs r
    SET video_id = v.id
    FROM videos v
    WHERE r.data->>'type' = 'media'
    AND v.source_url = #{video_source("r.data->'data'->'template_video'")}
    """

    execute keep_own_shape("media", ["data", "template_video"])

    # Process MediaBlock refs that contain template_picture
    execute """
    UPDATE content_refs r
    SET image_id = i.id
    FROM images i
    WHERE r.data->>'type' = 'media'
    AND i.path IN (#{path_candidates("r.data->'data'->'template_picture'->>'path'")})
    AND i.deleted_at IS NULL
    """

    # NOW clean up the ref data - do this AFTER creating videos and linking refs

    # Clean up PictureBlock data - keep only override fields
    # Based on the updated schema, we keep: title, credits, alt, picture_class,
    # img_class, link, srcset, media_queries, lazyload, moonwalk, placeholder, fetchpriority
    # NOTE: active and collapsed are now database columns, not in JSONB data
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
    AND (image_id IS NOT NULL OR #{legacy_path("data->'data'")} IS NULL)
    """

    # Clean up VideoBlock data - keep only override fields
    # Based on the updated schema, we keep: title, poster, autoplay, opacity,
    # preload, play_button, controls, cover, aspect_ratio, cover_image, loop, muted, playsinline, video_class, container_class
    # NOTE: active and collapsed are now database columns, not in JSONB data
    # NOTE: Set loop=true and muted=true if autoplay=true (required by browsers and makes UX sense)
    # NOTE: Brando before 0.54 rendered every file video with `loop` (blocks had
    # no such setting), so a missing `loop` becomes true. For `muted`, see
    # legacy_muted/1, and for `cover`, legacy_cover/1. The media block's
    # template_video below gets the same.
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
          'cover', #{legacy_cover("data->'data'")},
          'aspect_ratio', data->'data'->>'aspect_ratio',
          'cover_image', data->'data'->'cover_image',
          'loop', CASE WHEN data->'data'->'autoplay' = 'true'::jsonb THEN 'true'::jsonb ELSE COALESCE(data->'data'->'loop', 'true'::jsonb) END,
          'muted', #{legacy_muted("data->'data'")},
          'playsinline', 'true'::jsonb,
          'video_class', data->'data'->>'video_class',
          'container_class', data->'data'->>'container_class'
        )
      )
    )
    WHERE data->>'type' = 'video'
    """

    # Process refs with GalleryBlock data: a gallery for each gallery ref with
    # images, its id taken first so each ref is linked to its own
    execute """
    WITH refs AS (
      SELECT
        r.id AS ref_id,
        nextval(pg_get_serial_sequence('galleries', 'id')) AS gallery_id,
        COALESCE(b.creator_id, 1) AS creator_id
      FROM content_refs r
      LEFT JOIN content_blocks b ON r.block_id = b.id
      WHERE r.data->>'type' = 'gallery'
      AND r.gallery_id IS NULL
      AND jsonb_array_length(#{gallery_images("r.data->'data'")}) > 0
    ),
    created AS (
      INSERT INTO galleries (id, config_target, creator_id, inserted_at, updated_at)
      SELECT gallery_id, 'default', creator_id, NOW(), NOW() FROM refs
      RETURNING id
    )
    UPDATE content_refs r
    SET gallery_id = refs.gallery_id
    FROM refs
    WHERE r.id = refs.ref_id
    """

    # `config` carries the per-placement metadata below, and it is added by a
    # later migration. Ensure it here so this one can populate it; the later
    # migration adds it conditionally and stays correct either way.
    execute """
    ALTER TABLE galleries_gallery_objects
    ADD COLUMN IF NOT EXISTS config jsonb DEFAULT '{}'::jsonb
    """

    # As for pictures: a gallery image without a live row gets one made from
    # its data, so the gallery keeps every image 0.53 showed
    execute insert_images(gallery_items())

    # A gallery object for each image, in the legacy order
    execute """
    INSERT INTO galleries_gallery_objects (
      gallery_id, image_id, sequence, creator_id, config,
      inserted_at, updated_at
    )
    WITH items AS (#{gallery_items()}),
    resolved AS (#{resolve_images("items")})
    SELECT
      gallery_id,
      image_id,
      (row_number() OVER (PARTITION BY gallery_id ORDER BY ord)) - 1,
      creator_id,
      -- The same image can sit in several galleries, or twice in one, with a
      -- different caption each time, so this metadata belongs on the placement
      -- rather than on the image. An absent key means "not overridden", which is
      -- what the admin's override fields write.
      (
        CASE WHEN COALESCE(d->>'title', '') <> ''
             THEN jsonb_build_object('title', d->>'title') ELSE '{}'::jsonb END
        ||
        CASE WHEN COALESCE(d->>'alt', '') <> ''
             THEN jsonb_build_object('alt', d->>'alt') ELSE '{}'::jsonb END
        ||
        CASE WHEN COALESCE(d->>'credits', '') <> ''
             THEN jsonb_build_object('credits', d->>'credits') ELSE '{}'::jsonb END
      ),
      NOW(),
      NOW()
    FROM resolved
    WHERE image_id IS NOT NULL
    """

    execute "SET LOCAL enable_nestloop = DEFAULT"

    # Clean up gallery data - remove the images array
    # NOTE: active and collapsed are now database columns, not in JSONB data
    execute """
    UPDATE content_refs
    SET data = jsonb_build_object(
      'type', 'gallery',
      'data', (data->'data')::jsonb - 'images'
    )
    WHERE data->>'type' = 'gallery'
    AND (gallery_id IS NOT NULL OR jsonb_array_length(#{gallery_images("data->'data'")}) = 0)
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
                  'cover', #{legacy_cover("data->'data'->'template_video'")},
                  'aspect_ratio', data->'data'->'template_video'->>'aspect_ratio',
                  'cover_image', data->'data'->'template_video'->'cover_image',
                  'loop', CASE WHEN data->'data'->'template_video'->'autoplay' = 'true'::jsonb THEN 'true'::jsonb ELSE COALESCE(data->'data'->'template_video'->'loop', 'true'::jsonb) END,
                  'muted', #{legacy_muted("data->'data'->'template_video'")},
                  'playsinline', 'true'::jsonb,
                  'video_class', data->'data'->'template_video'->>'video_class',
                  'container_class', data->'data'->'template_video'->>'container_class'
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

  # Villain data from before 0.4x stored media paths as URLs under the media
  # prefix (`/media/images/site/x.jpg`), while `images.path` has no prefix
  # (`images/site/x.jpg`). Match a stored path as it is, and with the configured
  # media URL's path (and the default `/media`) stripped off its front.
  # Brando before 0.54 passed `cover: :svg` for every file video whatever the
  # block's `cover` held (the default "false", or a Vimeo thumbnail URL), and
  # the placeholder was drawn when the block had a width. The renderer now
  # honours `cover`, so write "svg" where it was drawn. Anything else keeps
  # "false", "svg" or "true", and an unknown string becomes "svg".
  defp legacy_cover(data) do
    """
    CASE
      WHEN #{data}->>'source' = 'file' AND #{data}->>'width' ~ '^[1-9][0-9]*$' THEN 'svg'
      WHEN #{data}->>'cover' IN ('false', 'svg', 'true') THEN #{data}->>'cover'
      WHEN #{data}->>'cover' IS NOT NULL THEN 'svg'
    END
    """
  end

  # Blocks had no `muted` setting. Brando before September 2022 (0.52 and
  # earlier) rendered every file video muted, and pages saved then still show
  # that HTML; later the renderer muted only autoplaying ones. A file video
  # with neither a play button nor controls can only be started by the site's
  # own script, and browsers refuse to play it with sound, so it stays muted.
  # One the visitor starts keeps its sound, as it had since 0.53. Autoplay
  # always mutes.
  defp legacy_muted(data) do
    """
    CASE
      WHEN #{data}->'autoplay' = 'true'::jsonb THEN 'true'::jsonb
      WHEN #{data}->'muted' IS NOT NULL THEN #{data}->'muted'
      WHEN #{data}->>'source' = 'file'
        AND #{data}->'play_button' IS DISTINCT FROM 'true'::jsonb
        AND #{data}->'controls' IS DISTINCT FROM 'true'::jsonb
      THEN 'true'::jsonb
      ELSE 'false'::jsonb
    END
    """
  end

  # The source a legacy video block points at: its url, or for an embed saved
  # with only a remote id, the provider URL built from it. Creating the videos
  # and linking the refs to them must use the same expression, or an embed
  # without a url is never linked and loses its video when the ref data is
  # cleaned up.
  defp video_source(data) do
    """
    CASE
      WHEN #{data}->>'source' = 'vimeo' AND #{data}->>'url' IS NULL AND #{data}->>'remote_id' IS NOT NULL
      THEN 'https://vimeo.com/' || SPLIT_PART(#{data}->>'remote_id', '?', 1)
      WHEN #{data}->>'source' = 'youtube' AND #{data}->>'url' IS NULL AND #{data}->>'remote_id' IS NOT NULL
      THEN 'https://www.youtube.com/watch?v=' || SPLIT_PART(#{data}->>'remote_id', '?', 1)
      ELSE COALESCE(#{data}->>'url', #{data}->>'remote_id')
    END
    """
  end

  # Blocks sharing a file share one video, sized by the first of them. Before
  # 0.54 each block rendered its own width and height, so a block whose shape
  # differs from the video's keeps it as its own aspect ratio. Sizes of one
  # shape at another scale rarely multiply out exactly (840×1052 and 971×1216
  # differ by 0.005%), so ratios within half a percent count as the same shape.
  defp keep_own_shape(type, path) do
    data = Enum.map_join(["r.data" | Enum.map(path, &"'#{&1}'")], "->", & &1)
    width = "(#{data}->>'width')"
    height = "(#{data}->>'height')"

    """
    UPDATE content_refs r
    SET data = jsonb_set(r.data, '{#{Enum.join(path, ",")},aspect_ratio}', to_jsonb(#{width} || ':' || #{height}))
    FROM videos v
    WHERE r.video_id = v.id
    AND r.data->>'type' = '#{type}'
    AND #{data}->>'aspect_ratio' IS NULL
    AND #{width} ~ '^[1-9][0-9]*$' AND #{height} ~ '^[1-9][0-9]*$'
    AND v.width > 0 AND v.height > 0
    AND abs(#{width}::numeric * v.height - #{height}::numeric * v.width) > 0.005 * #{height}::numeric * v.width
    """
  end

  # The picture refs still without an image, as `(item_id, d, ord, creator_id)`
  # with `d` the legacy picture data
  defp picture_items do
    """
    SELECT r.id AS item_id, r.data->'data' AS d, r.id AS ord, b.creator_id
    FROM content_refs r
    LEFT JOIN content_blocks b ON r.block_id = b.id
    WHERE r.data->>'type' = 'picture'
    AND r.image_id IS NULL
    AND jsonb_typeof(r.data->'data') = 'object'
    """
  end

  # Every image of a linked gallery ref, as `(gallery_id, d, ord, creator_id)`
  # with `d` the legacy image data
  defp gallery_items do
    """
    SELECT r.gallery_id, imgs.d, imgs.ord, COALESCE(b.creator_id, 1) AS creator_id
    FROM content_refs r
    CROSS JOIN LATERAL jsonb_array_elements(#{gallery_images("r.data->'data'")}) WITH ORDINALITY AS imgs(d, ord)
    LEFT JOIN content_blocks b ON r.block_id = b.id
    WHERE r.data->>'type' = 'gallery'
    AND r.gallery_id IS NOT NULL
    """
  end

  defp gallery_images(data) do
    "CASE WHEN jsonb_typeof(#{data}->'images') = 'array' THEN #{data}->'images' ELSE '[]'::jsonb END"
  end

  defp link_pictures do
    """
    WITH items AS (#{picture_items()}),
    resolved AS (#{resolve_images("items")})
    UPDATE content_refs r
    SET image_id = resolved.image_id
    FROM resolved
    WHERE r.id = resolved.item_id
    AND resolved.image_id IS NOT NULL
    """
  end

  # The live image each item's legacy data `d` shows, as `image_id` next to
  # the item's columns, and whether a row may be made for it (`makeable`).
  # A soft-deleted row is not a match: emptying the trash deletes it, and
  # what links to it with it.
  #
  # `sizes` and `path` usually name the same image (a size file is
  # `<dir>/<size>/<name>`, or the file itself for an SVG; its extension may
  # be a converted one). Then only a row with that exact `path` is a match,
  # as two images can share a stem (`team.png`, `team.jpg`), and when there
  # is none a row is made from the data.
  #
  # When they name different images, `path` is stale: a replaced image wrote
  # one but not the other, and the old renderer read `sizes`, so that is the
  # image the site displayed. It is linked when exactly one row has its
  # stem; otherwise the ref is left unlinked, keeping its data, rather than
  # linked to what the stale path names.
  #
  # The live images are read once, and matched on equality, so this joins
  # rather than scanning `images` per item.
  defp resolve_images(items) do
    """
    WITH live AS MATERIALIZED (
      SELECT id, path, regexp_replace(path, '\\.[^.]+$', '') AS stem
      FROM images
      WHERE deleted_at IS NULL
    ),
    normalised AS MATERIALIZED (
      SELECT x.*, n.cpath, n.csize,
        regexp_replace(n.cpath, '\\.[^.]+$', '') AS pstem,
        ARRAY[
          regexp_replace(n.csize, '\\.[^.]+$', ''),
          regexp_replace(regexp_replace(n.csize, '/[^/]+/([^/]+)$', '/\\1'), '\\.[^.]+$', '')
        ] AS sstems
      FROM (SELECT #{items}.*, row_number() OVER () AS item_key FROM #{items}) x
      CROSS JOIN LATERAL (
        SELECT
          #{canonical_path("x.d->>'path'")} AS cpath,
          (
            SELECT #{canonical_path("value")}
            FROM jsonb_each_text(CASE WHEN jsonb_typeof(x.d->'sizes') = 'object' THEN x.d->'sizes' ELSE '{}'::jsonb END)
            WHERE value IS NOT NULL AND btrim(value) <> ''
            ORDER BY key
            LIMIT 1
          ) AS csize
      ) n
    ),
    exact AS (
      SELECT o.item_key, min(live.id) AS id
      FROM normalised o
      CROSS JOIN LATERAL unnest(ARRAY[o.d->>'path', o.cpath]) AS v(path)
      JOIN live ON live.path = v.path
      GROUP BY o.item_key
    ),
    by_size AS (
      SELECT o.item_key, count(DISTINCT live.id) AS n, min(live.id) AS id
      FROM normalised o
      CROSS JOIN LATERAL unnest(o.sstems) AS v(stem)
      JOIN live ON live.stem = v.stem
      GROUP BY o.item_key
    ),
    judged AS (
      SELECT o.*, (o.csize IS NULL OR o.pstem IS NULL OR o.pstem = ANY(o.sstems)) AS agree
      FROM normalised o
    )
    SELECT j.*,
      CASE
        WHEN j.agree AND j.cpath IS NOT NULL THEN e.id
        WHEN z.n = 1 THEN z.id
      END AS image_id,
      (j.agree AND j.cpath IS NOT NULL AND e.id IS NULL) AS makeable
    FROM judged j
    LEFT JOIN exact e ON e.item_key = j.item_key
    LEFT JOIN by_size z ON z.item_key = j.item_key
    """
  end

  # An image row for each legacy path among `items` that no live row shows,
  # made from the first item's data, as 0.53 rendered it: its path and sizes
  # (without the media prefix), dimensions, formats (from the extension when
  # the data has none), dominant color and focal point. Its texts stay on the
  # ref or gallery object that set them.
  defp insert_images(items) do
    path = "cpath"

    """
    INSERT INTO images (
      path, sizes, width, height, formats, dominant_color, focal, cdn,
      config_target, status, creator_id, inserted_at, updated_at
    )
    WITH items AS (#{items}),
    resolved AS (#{resolve_images("items")})
    SELECT DISTINCT ON (#{path})
      #{path},
      CASE WHEN jsonb_typeof(d->'sizes') = 'object' THEN
        (SELECT jsonb_object_agg(key, #{canonical_path("value")}) FROM jsonb_each_text(d->'sizes'))
      END,
      CASE WHEN d->>'width' ~ '^[0-9]+$' THEN (d->>'width')::integer END,
      CASE WHEN d->>'height' ~ '^[0-9]+$' THEN (d->>'height')::integer END,
      CASE
        WHEN jsonb_typeof(d->'formats') = 'array' AND jsonb_array_length(d->'formats') > 0
        THEN ARRAY(SELECT jsonb_array_elements_text(d->'formats'))::varchar[]
        ELSE ARRAY[
          CASE lower(substring(#{path} from '\\.([^./]+)$'))
            WHEN 'jpeg' THEN 'jpg'
            WHEN 'jpg' THEN 'jpg'
            WHEN 'png' THEN 'png'
            WHEN 'gif' THEN 'gif'
            WHEN 'webp' THEN 'webp'
            WHEN 'avif' THEN 'avif'
            WHEN 'svg' THEN 'svg'
            ELSE 'original'
          END
        ]::varchar[]
      END,
      d->>'dominant_color',
      CASE WHEN jsonb_typeof(d->'focal') = 'object' THEN d->'focal' ELSE '{"x": 50, "y": 50}'::jsonb END,
      COALESCE(d->'cdn' = 'true'::jsonb, false),
      'default',
      'processed',
      creator_id,
      NOW(),
      NOW()
    FROM resolved
    WHERE makeable
    ORDER BY #{path}, ord
    """
  end

  # A legacy `path`, or NULL when the data has none (a picture never picked)
  defp legacy_path(data), do: "NULLIF(btrim(#{data}->>'path'), '')"

  # How a legacy path is stored in `images.path`: without the media prefix
  # or a leading slash. path_variants/1 includes this form, so a ref finds
  # the row made from its data.
  defp canonical_path(expression) do
    stripped =
      Enum.reduce(Enum.reverse(media_prefixes()), "ltrim(#{expression}, '/')", fn prefix, rest ->
        "CASE WHEN substr(#{expression}, 1, #{String.length(prefix)}) = #{literal(prefix)} " <>
          "THEN substr(#{expression}, #{String.length(prefix) + 1}) ELSE #{rest} END"
      end)

    "NULLIF(btrim(#{stripped}), '')"
  end

  defp path_candidates(expression), do: expression |> path_variants() |> Enum.join(", ")

  defp path_variants(expression) do
    stripped =
      Enum.map(media_prefixes(), fn prefix ->
        "CASE WHEN substr(#{expression}, 1, #{String.length(prefix)}) = #{literal(prefix)} " <>
          "THEN substr(#{expression}, #{String.length(prefix) + 1}) ELSE #{expression} END"
      end)

    [expression | stripped] ++ ["ltrim(#{expression}, '/')"]
  end

  defp media_prefixes do
    configured =
      case Brando.config(:media_url) do
        url when is_binary(url) -> URI.parse(url).path
        _ -> nil
      end

    [configured, "/media"]
    |> Enum.reject(&(&1 in [nil, "", "/"]))
    |> Enum.map(&(String.trim_trailing(&1, "/") <> "/"))
    |> Enum.uniq()
  end

  defp literal(value), do: "'" <> String.replace(value, "'", "''") <> "'"
end
