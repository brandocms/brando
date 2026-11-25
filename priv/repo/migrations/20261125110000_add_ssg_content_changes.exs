defmodule BrandoIntegration.Repo.Migrations.AddSSGContentChanges do
  use Ecto.Migration

  # Mirrors the brando_250 upgrade migration for the test schema.
  @moduledoc """
  When each environment's content last changed, and when a static build
  started (`Brando.SSG.ContentChanges`).
  """

  def change do
    create table(:ssg_content_changes, primary_key: false, prefix: "public") do
      add :environment_id, references(:environments, on_delete: :delete_all, prefix: "public"), primary_key: true
      add :changed_at, :utc_datetime_usec, null: false
    end

    alter table(:ssg_builds, prefix: "public") do
      add :started_at, :utc_datetime_usec
    end
  end
end
