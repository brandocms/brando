defmodule Brando.Repo.Migrations.AddGlobalsToIdentity do
  use Ecto.Migration

  def change do
    alter table(:sites_identities) do
      add :globals, :map
    end
  end
end
