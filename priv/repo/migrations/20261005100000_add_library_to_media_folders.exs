defmodule BrandoIntegration.Repo.Migrations.AddLibraryToMediaFolders do
  use Ecto.Migration

  # Mirrors the brando_199 upgrade migration for the test schema.
  def change do
    alter table(:media_folders) do
      add :library, :boolean, default: true, null: false
    end
  end
end
