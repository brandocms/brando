defmodule Brando.Repo.Migrations.AddUserSites do
  use Ecto.Migration

  @moduledoc """
  Test/e2e mirror of `priv/templates/brando.upgrade/migrations/brando_160_*`.
  """

  def change do
    create table(:user_sites, prefix: "public") do
      add :user_id, references(:users, prefix: "public", on_delete: :delete_all), null: false
      add :site_id, references(:sites, prefix: "public", on_delete: :delete_all), null: false
      add :role, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:user_sites, [:user_id, :site_id], prefix: "public")
    create index(:user_sites, [:site_id, :role], prefix: "public")

    create constraint(:user_sites, :user_sites_valid_role,
             prefix: "public",
             check: "role IN ('editor', 'admin')"
           )
  end
end
