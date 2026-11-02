defmodule BrandoIntegration.Repo.Migrations.AddProviderLibraryGroupToSites do
  use Ecto.Migration

  # Mirrors the brando_226 upgrade migration for the test schema.
  @moduledoc """
  `sites.provider_library_group`: which sites share the video providers'
  libraries (`Brando.Videos.ProviderLibrary`).
  """

  def change do
    alter table(:sites, prefix: "public") do
      add :provider_library_group, :text
    end
  end
end
