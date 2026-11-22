defmodule BrandoIntegration.Repo.Migrations.AddSitesUsageDays do
  use Ecto.Migration

  # Mirrors the brando_243 upgrade migration for the test schema.
  @moduledoc """
  What each site of a multi-site installation uses, one row per site per
  UTC day (`Brando.Sites.Usage`).
  """

  def change do
    create table(:sites_usage_days) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :day, :date, null: false
      add :requests, :bigint, null: false, default: 0
      add :bytes_sent, :bigint, null: false, default: 0
      add :media_bytes, :bigint
      add :builds_bytes, :bigint
      add :databases, {:array, :map}
      add :measured_at, :utc_datetime_usec
    end

    create unique_index(:sites_usage_days, [:site_id, :day])
    create index(:sites_usage_days, [:day])
  end
end
