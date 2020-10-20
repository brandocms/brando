defmodule Brando.Repo.Migrations.AddAddress2ToIdentity do
  use Ecto.Migration

  def change do
    alter table(:sites_identities) do
      add :address2, :string
    end
  end
end
