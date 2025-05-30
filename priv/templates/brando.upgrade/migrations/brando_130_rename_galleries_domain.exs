defmodule Brando.Migrations.Galleries.Gallery.RenameGalleriesDomain do
  use Ecto.Migration

  def up do
    rename table(:images_galleries), to: table(:galleries)
    rename table(:images_gallery_images), to: table(:galleries_gallery_objects)
    
    alter table(:galleries_gallery_objects) do
      add :video_id, references(:videos, on_delete: :delete_all)
    end
  end

  def down do
    alter table(:galleries_gallery_objects) do
      remove :video_id
    end

    rename table(:galleries_gallery_objects), to: table(:images_gallery_images)
    rename table(:galleries), to: table(:images_galleries)
  end
end