defmodule BrandoIntegration.Repo.Migrations.AddPublishedBuildToSites do
  use Ecto.Migration

  # Mirrors the brando_230 upgrade migration for the test schema.
  @moduledoc """
  `sites.published_build`: the version of the static build the installation
  serves itself (`Brando.SSG.LocalDelivery`).
  """

  def change do
    alter table(:sites, prefix: "public") do
      add :published_build, :text
    end
  end
end
