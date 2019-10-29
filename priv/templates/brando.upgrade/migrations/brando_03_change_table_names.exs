defmodule Brando.Repo.Migrations.ChangeTableNames do
  use Ecto.Migration

  def change do
    rename(table(:users), to: table(:users_users))
    rename(table(:pages), to: table(:pages_pages))
    rename(table(:pagefragments), to: table(:pages_fragments))
    rename(table(:templates), to: table(:pages_templates))
    rename(table(:imagecategories), to: table(:images_categories))
    rename(table(:imageseries), to: table(:images_series))
    rename(table(:images), to: table(:images_images))
  end
end
