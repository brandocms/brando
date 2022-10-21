defmodule Brando.Repo.Migrations.AddUniqueIndexForSEOandIdentity do
  use Ecto.Migration

  def change do
    create unique_index(:sites_identities, [:language])
    create unique_index(:sites_seos, [:language])
  end
end
