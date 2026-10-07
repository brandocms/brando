defmodule BrandoIntegration.Repo.Migrations.AddNotFoundHits do
  use Ecto.Migration

  # Mirrors the brando_201 upgrade migration for the test schema.
  @moduledoc """
  The 404 log (`Brando.Sites.FourOhFour`): daily hit totals per missing URL
  and referrer.
  """

  def change do
    create table(:sites_not_found_hits) do
      add :url, :text, null: false
      add :referrer, :text, null: false, default: ""
      add :date, :date, null: false
      add :hits, :integer, null: false, default: 0
      add :last_hit_at, :utc_datetime, null: false
    end

    create unique_index(:sites_not_found_hits, [:url, :referrer, :date])
    create index(:sites_not_found_hits, [:date])
  end
end
