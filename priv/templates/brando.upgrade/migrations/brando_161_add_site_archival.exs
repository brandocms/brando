defmodule Brando.Repo.Migrations.Brando161AddSiteArchival do
  use Ecto.Migration

  def change do
    alter table(:sites, prefix: "public") do
      add :archived_at, :utc_datetime_usec
    end

    create index(:sites, [:status, :archived_at], prefix: "public")
  end
end
