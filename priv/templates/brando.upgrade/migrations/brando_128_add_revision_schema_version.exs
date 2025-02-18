defmodule Brando.Repo.Migrations.AddRevisionSchemaVersion do
  use Ecto.Migration

  def change do
    alter table(:revisions) do
      add :schema_version, :integer, default: 0
    end
  end
end