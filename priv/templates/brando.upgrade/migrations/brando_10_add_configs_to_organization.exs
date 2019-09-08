defmodule Brando.Repo.Migrations.AddConfigsToOrganization do
  use Ecto.Migration

  def change do
    alter table(:sites_organizations) do
      add :configs, :map
    end
  end
end
