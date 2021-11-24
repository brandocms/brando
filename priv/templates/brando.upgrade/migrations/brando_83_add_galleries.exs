defmodule Brando.Migrations.Images.Gallery.AddGalleries do
  use Ecto.Migration

  def up do
    alter table(:images) do
      remove :sequence
    end

    create table(:images_galleries) do
      add :config_target, :text
      add :deleted_at, :utc_datetime
      add :creator_id, references(:users, on_delete: :nothing)
      timestamps()
    end

    create table(:images_gallery_images) do
      add :sequence, :integer
      add :gallery_id, references(:images_galleries, on_delete: :delete_all)
      add :image_id, references(:images, on_delete: :delete_all)
      add :creator_id, references(:users, on_delete: :nothing)
      timestamps()
    end
  end

  def down do
    drop table(:images_gallery_images)
    drop table(:images_galleries)

    alter table(:images) do
      add :sequence, :integer
    end
  end
end
