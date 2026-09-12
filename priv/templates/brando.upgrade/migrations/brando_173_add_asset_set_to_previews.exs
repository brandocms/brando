defmodule Brando.Repo.Migrations.Brando173AddAssetSetToPreviews do
  use Ecto.Migration

  def change do
    alter table(:sites_previews) do
      add :asset_set_id, references(:site_asset_sets, prefix: "public", on_delete: :nilify_all)
    end

    create index(:sites_previews, [:asset_set_id])
  end
end
