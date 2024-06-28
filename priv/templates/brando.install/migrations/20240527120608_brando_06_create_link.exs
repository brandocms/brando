defmodule Brando.Repo.Migrations.CreateLink do
  use Ecto.Migration
  use Brando.Sequence.Migration

  def change do
    create table(:sites_links) do
      add :name, :string
      add :url, :string
      add :organization_id, references(:sites_organizations)
      sequenced()
      timestamps()
    end
  end
end
