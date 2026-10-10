defmodule Brando.Repo.Migrations.Brando215AddListingViews do
  use Ecto.Migration

  @moduledoc """
  In every site environment, the tables for saved listing views
  (`Brando.ListingViews`):

    * `listing_views` holds a listing's filters, status, sort and page size
      under a name: one person's, or shared with everyone who can open that
      listing.
    * `listing_view_defaults` holds the view each person opens a listing
      with, one per person and listing.

  A view's filters belong to the environment's content, so the tables live in
  each environment. Users live in `public`, so their foreign keys name that
  schema.
  """

  def up do
    for prefix <- prefixes() do
      create table(:listing_views, prefix: prefix) do
        add :name, :text, null: false
        add :schema, :text, null: false
        add :listing, :text, null: false
        add :params, :map, null: false, default: %{}
        add :shared, :boolean, null: false, default: false
        add :creator_id, references(:users, prefix: "public", on_delete: :delete_all), null: false

        timestamps(type: :utc_datetime_usec)
      end

      create index(:listing_views, [:schema, :listing], prefix: prefix)

      create unique_index(:listing_views, [:creator_id, :schema, :listing, :name],
               prefix: prefix,
               name: :listing_views_creator_name_index
             )

      create table(:listing_view_defaults, prefix: prefix) do
        add :user_id, references(:users, prefix: "public", on_delete: :delete_all), null: false
        add :view_id, references(:listing_views, on_delete: :delete_all), null: false
        add :schema, :text, null: false
        add :listing, :text, null: false

        timestamps(type: :utc_datetime_usec)
      end

      create unique_index(:listing_view_defaults, [:user_id, :schema, :listing],
               prefix: prefix,
               name: :listing_view_defaults_user_listing_index
             )

      create index(:listing_view_defaults, [:view_id], prefix: prefix)
    end
  end

  def down do
    for prefix <- prefixes() do
      drop table(:listing_view_defaults, prefix: prefix)
      drop table(:listing_views, prefix: prefix)
    end
  end

  # Every site environment, or only the one named by the migrator's prefix:
  # `Brando.Environments.ArchiveUpgrade` runs this again in an archive
  # restored from before it ran.
  defp prefixes do
    case prefix() do
      "tenant_" <> _ = environment ->
        [environment]

      _ ->
        %{rows: rows} =
          repo().query!(
            "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
          )

        Enum.map(rows, &hd/1)
    end
  end
end
