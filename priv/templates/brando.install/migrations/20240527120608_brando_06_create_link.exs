defmodule Brando.Repo.Migrations.CreateLink do
  use Ecto.Migration

  def change do
    create table(:sites_links) do
      add :name, :string
      add :url, :string
      add :organization_id, references(:sites_organizations)
      add :sequence, :integer
      timestamps()
    end
  end
end
