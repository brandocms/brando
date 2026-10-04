defmodule BrandoIntegration.Repo.Migrations.AddConfigFingerprintToImages do
  use Ecto.Migration

  # Mirrors the brando_197 upgrade migration for the test schema.
  def change do
    alter table(:images) do
      add :config_fingerprint, :text
    end
  end
end
