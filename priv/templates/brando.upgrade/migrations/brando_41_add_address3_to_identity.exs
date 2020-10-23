defmodule Brando.Repo.Migrations.AddAddress3ToIdentity do
  use Ecto.Migration

  def change do
    alter table(:sites_identities) do
      add :address3, :string
    end
  end
end
