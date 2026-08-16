defmodule Brando.Repo.Migrations.Brando162AddSiteAssetSets do
  use Ecto.Migration

  def change do
    create table(:site_asset_sets, prefix: "public") do
      add :site_id, references(:sites, prefix: "public", on_delete: :delete_all)
      add :name, :text, null: false
      add :path, :text, null: false
      add :active, :boolean, null: false, default: false
      add :uploaded_at, :utc_datetime_usec, null: false
      add :size, :bigint, null: false, default: 0
      add :file_count, :integer, null: false, default: 0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:site_asset_sets, [:name],
             prefix: "public",
             where: "site_id IS NULL",
             name: :site_asset_sets_standalone_name_index
           )

    create unique_index(:site_asset_sets, [:site_id, :name],
             prefix: "public",
             where: "site_id IS NOT NULL",
             name: :site_asset_sets_site_name_index
           )

    create unique_index(:site_asset_sets, [:active],
             prefix: "public",
             where: "site_id IS NULL AND active",
             name: :site_asset_sets_one_standalone_active_index
           )

    create unique_index(:site_asset_sets, [:site_id],
             prefix: "public",
             where: "site_id IS NOT NULL AND active",
             name: :site_asset_sets_one_site_active_index
           )

    create index(:site_asset_sets, [:site_id, :uploaded_at], prefix: "public")
  end
end
