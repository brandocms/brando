defmodule Brando.Repo.Migrations.Brando243AddSitesUsageDays do
  use Ecto.Migration

  @moduledoc """
  What each site of a multi-site installation uses, one row per site per UTC
  day (`Brando.Sites.Usage`):

    * `requests` and `bytes_sent`, the requests the endpoint answered on the
      site's own hosts, added to by every node's counters;
    * `media_bytes`, `builds_bytes` and `databases` (each environment's and
      archive's schema), set by the daily measuring, with `measured_at`. A
      day with traffic and no measurement has them empty.

  Sites live in `public`, and so does this table. Empty until the first
  requests and measuring, and unused outside `tenancy_mode: :multi`.
  """

  def up do
    create_if_not_exists table(:sites_usage_days, prefix: "public") do
      add :site_id, references(:sites, on_delete: :delete_all, prefix: "public"), null: false
      add :day, :date, null: false
      add :requests, :bigint, null: false, default: 0
      add :bytes_sent, :bigint, null: false, default: 0
      add :media_bytes, :bigint
      add :builds_bytes, :bigint
      add :databases, {:array, :map}
      add :measured_at, :utc_datetime_usec
    end

    create_if_not_exists unique_index(:sites_usage_days, [:site_id, :day], prefix: "public")
    create_if_not_exists index(:sites_usage_days, [:day], prefix: "public")
  end

  def down do
    drop_if_exists table(:sites_usage_days, prefix: "public")
  end
end
