defmodule BrandoIntegration.Repo.Migrations.AddContentHashToImages do
  use Ecto.Migration

  # Mirrors the brando_189 upgrade migration for the test schema.
  def change do
    alter table(:images) do
      add :content_hash, :text
    end

    create index(:images, [:content_hash])
  end
end
