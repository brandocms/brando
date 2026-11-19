defmodule BrandoIntegration.Repo.Migrations.AddAllowedDeployTargetsToSites do
  use Ecto.Migration

  # Mirrors the brando_237 upgrade migration for the test schema.
  @moduledoc """
  `sites.allowed_rsync_targets` and `sites.allowed_s3_targets`: the deploy
  targets a superuser allows a site besides those in config.
  """

  def change do
    alter table(:sites, prefix: "public") do
      add :allowed_rsync_targets, {:array, :text}, null: false, default: []
      add :allowed_s3_targets, {:array, :text}, null: false, default: []
    end
  end
end
