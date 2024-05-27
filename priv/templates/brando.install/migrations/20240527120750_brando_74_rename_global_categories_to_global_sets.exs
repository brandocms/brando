defmodule Brando.Repo.Migrations.RenameGlobalCategoriesToGlobalSets do
  use Ecto.Migration

  def change do
    rename table(:sites_global_categories), to: table(:sites_global_sets)

    alter table(:sites_global_sets) do
      add :creator_id, references(:users, on_delete: :nothing)
      timestamps(null: true)
    end

    execute """
    UPDATE sites_global_sets
    SET updated_at=NOW(), inserted_at=NOW(), creator_id=1
    """

    alter table(:sites_global_sets) do
      modify :inserted_at, :utc_datetime, null: false
      modify :updated_at, :utc_datetime, null: false
    end
  end
end
