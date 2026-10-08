defmodule Brando.Repo.Migrations.AddIndexnow do
  use Ecto.Migration

  # A site environment's IndexNow settings, see `Brando.IndexNow`.
  def change do
    create table(:sites_indexnow) do
      add :enabled, :boolean, null: false, default: false
      add :key, :text, null: false
      add :last_submitted_at, :utc_datetime
      add :last_status, :integer
      add :last_response, :text
      add :last_url_count, :integer
      timestamps(type: :utc_datetime)
    end
  end
end
