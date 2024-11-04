defmodule Brando.Migrations.RenameTables do
  use Ecto.Migration

  def change do
    rename table(:sites_identities), to: table(:sites_identity)
  end
end
