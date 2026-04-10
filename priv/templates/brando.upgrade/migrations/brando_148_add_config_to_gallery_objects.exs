defmodule Brando.Repo.Migrations.AddConfigToGalleryObjects do
  use Ecto.Migration

  def change do
    alter table(:galleries_gallery_objects) do
      add_if_not_exists :config, :map, default: %{}
    end
  end
end
