defmodule BrandoIntegration.Repo.Migrations.AddSiteToPreviews do
  use Ecto.Migration

  # Mirrors the brando_227 upgrade migration for the test schema.
  @moduledoc """
  `sites_previews.site_id` and `environment_id`: the site and environment a
  shared preview was shared from.
  """

  def change do
    alter table(:sites_previews, prefix: "public") do
      add :site_id, references(:sites, prefix: "public", on_delete: :delete_all)
      add :environment_id, references(:environments, prefix: "public", on_delete: :delete_all)
    end

    create index(:sites_previews, [:site_id], prefix: "public")
    create index(:sites_previews, [:environment_id], prefix: "public")
  end
end
