defmodule BrandoIntegration.Repo.Migrations.AddAssetSetToEnvironments do
  use Ecto.Migration

  # Mirrors the brando_228 upgrade migration for the test schema.
  @moduledoc """
  `environments.asset_set_id`: the frontend asset set an environment uses in
  place of its site's active set.
  """

  def change do
    alter table(:environments, prefix: "public") do
      add :asset_set_id, references(:site_asset_sets, prefix: "public", on_delete: :nilify_all)
    end

    create index(:environments, [:asset_set_id], prefix: "public")
  end
end
