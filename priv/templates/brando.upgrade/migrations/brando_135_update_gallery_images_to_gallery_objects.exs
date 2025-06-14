defmodule Brando.Migrations.UpdateGalleryImagesToGalleryObjects do
  use Ecto.Migration
  import Ecto.Query

  def up do
    # Update module code to replace gallery_images with gallery_objects
    execute """
    UPDATE content_modules
    SET code = regexp_replace(
      code,
      '(entry\\.[a-zA-Z0-9_]+)\\.gallery_images',
      '\\1.gallery_objects',
      'g'
    )
    WHERE code ~ 'entry\\.[a-zA-Z0-9_]+\\.gallery_images'
    """

    # Also update refs that might reference gallery_images directly
    execute """
    UPDATE content_modules
    SET code = regexp_replace(
      code,
      '(refs\\.[a-zA-Z0-9_]+)\\.gallery_images',
      '\\1.gallery_objects',
      'g'
    )
    WHERE code ~ 'refs\\.[a-zA-Z0-9_]+\\.gallery_images'
    """

    # Update any direct gallery.gallery_images references
    execute """
    UPDATE content_modules
    SET code = regexp_replace(
      code,
      '([a-zA-Z0-9_]+)\\.gallery_images',
      '\\1.gallery_objects',
      'g'
    )
    WHERE code ~ '[a-zA-Z0-9_]+\\.gallery_images'
    AND code !~ '(entry|refs)\\.[a-zA-Z0-9_]+\\.gallery_images'
    """

    # Update fragments that might contain gallery_images references
    execute """
    UPDATE pages_fragments
    SET html = regexp_replace(
      html,
      '(entry\\.[a-zA-Z0-9_]+)\\.gallery_images',
      '\\1.gallery_objects',
      'g'
    )
    WHERE html ~ 'entry\\.[a-zA-Z0-9_]+\\.gallery_images'
    """

    # Update any page templates that might have gallery_images
    execute """
    UPDATE pages
    SET html = regexp_replace(
      html,
      '(entry\\.[a-zA-Z0-9_]+)\\.gallery_images',
      '\\1.gallery_objects',
      'g'
    )
    WHERE html ~ 'entry\\.[a-zA-Z0-9_]+\\.gallery_images'
    """

  end

  def down do
    # Reverse: change gallery_objects back to gallery_images
    execute """
    UPDATE content_modules
    SET code = regexp_replace(
      code,
      '(entry\\.[a-zA-Z0-9_]+)\\.gallery_objects',
      '\\1.gallery_images',
      'g'
    )
    WHERE code ~ 'entry\\.[a-zA-Z0-9_]+\\.gallery_objects'
    """

    execute """
    UPDATE content_modules
    SET code = regexp_replace(
      code,
      '(refs\\.[a-zA-Z0-9_]+)\\.gallery_objects',
      '\\1.gallery_images',
      'g'
    )
    WHERE code ~ 'refs\\.[a-zA-Z0-9_]+\\.gallery_objects'
    """

    execute """
    UPDATE content_modules
    SET code = regexp_replace(
      code,
      '([a-zA-Z0-9_]+)\\.gallery_objects',
      '\\1.gallery_images',
      'g'
    )
    WHERE code ~ '[a-zA-Z0-9_]+\\.gallery_objects'
    AND code !~ '(entry|refs)\\.[a-zA-Z0-9_]+\\.gallery_objects'
    """

    execute """
    UPDATE pages_fragments
    SET html = regexp_replace(
      html,
      '(entry\\.[a-zA-Z0-9_]+)\\.gallery_objects',
      '\\1.gallery_images',
      'g'
    )
    WHERE html ~ 'entry\\.[a-zA-Z0-9_]+\\.gallery_objects'
    """

    execute """
    UPDATE pages
    SET html = regexp_replace(
      html,
      '(entry\\.[a-zA-Z0-9_]+)\\.gallery_objects',
      '\\1.gallery_images',
      'g'
    )
    WHERE html ~ 'entry\\.[a-zA-Z0-9_]+\\.gallery_objects'
    """

  end
end
