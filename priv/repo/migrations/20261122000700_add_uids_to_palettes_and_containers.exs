defmodule BrandoIntegration.Repo.Migrations.AddUidsToPalettesAndContainers do
  use Ecto.Migration

  # Mirrors the brando_245 upgrade migration for the test schema.
  @moduledoc """
  `uid` on palettes and containers: their identity in definition files.
  """

  def change do
    alter table(:content_palettes) do
      add :uid, :text
    end

    alter table(:content_containers) do
      add :uid, :text
    end

    create unique_index(:content_palettes, [:uid])
    create unique_index(:content_containers, [:uid])
  end
end
