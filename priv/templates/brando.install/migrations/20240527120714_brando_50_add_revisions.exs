defmodule Brando.Repo.Migrations.AddRevisions do
  use Ecto.Migration

  def change do
    create table(:revisions, primary_key: false) do
      add :active, :boolean, default: false, null: false
      add :entry_id, :integer, null: false
      add :entry_type, :string, null: false
      add :encoded_entry, :binary, null: false
      add :creator_id, references(:users_users, on_delete: :nilify_all)
      add :metadata, :map, null: false
      add :revision, :integer, null: false
      add :protected, :boolean, default: false, null: false
      add :scheduled, :boolean, default: false, null: false
      add :schema_version, :integer, default: 0, null: false
      timestamps()
    end

    create unique_index(:revisions, [:entry_type, :entry_id, :revision])

    create unique_index(:revisions, [:entry_type, :entry_id],
             name: :revisions_one_active_per_entry_index,
             where: "active = true"
           )
  end
end
