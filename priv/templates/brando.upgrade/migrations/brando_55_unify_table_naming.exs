defmodule Brando.Repo.Migrations.UnifyTableNaming do
  use Ecto.Migration

  def change do
    rename table(:users_users), to: table(:users)
    rename table(:pages_pages), to: table(:pages)
    rename table(:images_images), to: table(:images)
  end
end
