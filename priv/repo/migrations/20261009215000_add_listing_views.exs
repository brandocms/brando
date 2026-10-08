defmodule BrandoIntegration.Repo.Migrations.AddListingViews do
  use Ecto.Migration

  # Mirrors the brando_215 upgrade migration for the test schema.
  @moduledoc """
  Saved listing views (`Brando.ListingViews`): a listing's filters, status,
  sort and page size under a name, and the view each person opens a listing
  with.
  """

  def change do
    create table(:listing_views) do
      add :name, :text, null: false
      add :schema, :text, null: false
      add :listing, :text, null: false
      add :params, :map, null: false, default: %{}
      add :shared, :boolean, null: false, default: false
      add :creator_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:listing_views, [:schema, :listing])

    create unique_index(:listing_views, [:creator_id, :schema, :listing, :name], name: :listing_views_creator_name_index)

    create table(:listing_view_defaults) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :view_id, references(:listing_views, on_delete: :delete_all), null: false
      add :schema, :text, null: false
      add :listing, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:listing_view_defaults, [:user_id, :schema, :listing],
             name: :listing_view_defaults_user_listing_index
           )

    create index(:listing_view_defaults, [:view_id])
  end
end
