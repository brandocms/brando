defmodule Brando.Repo.Migrations.RemoveSitesIdentitiesImage do
  use Ecto.Migration

  def change do
    alter table(:sites_identities) do
      remove :image
    end
  end
end
