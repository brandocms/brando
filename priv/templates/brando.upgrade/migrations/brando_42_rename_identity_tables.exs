defmodule Brando.Migrations.RenameTables do
  use Ecto.Migration
  use Brando.Sequence.Migration

  def change do
    rename table(:sites_identities), to: table(:sites_identity)
  end
end
