defmodule E2eProject.Migrations.Projects.Client.Blueprint001 do
  use Ecto.Migration

  def up do
    create table(:projects_clients) do
      add :status, :integer
      add :language, :text
      add :name, :text
      add :slug, :text
      timestamps()
      add :creator_id, references(:users, on_delete: :nothing)
    end

    create index(:projects_clients, [:language])
    create unique_index(:projects_clients, [:slug])

    create table(:projects_clients_alternates) do
      add :entry_id, references(:projects_clients, on_delete: :delete_all)
      add :linked_entry_id, references(:projects_clients, on_delete: :delete_all)
      timestamps()
    end

    create unique_index(:projects_clients_alternates, [:entry_id, :linked_entry_id])
  end

  def down do
    drop table(:projects_clients)

    drop index(:projects_clients, [:language])
    drop unique_index(:projects_clients, [:slug])

    drop table(:projects_clients_alternates)
  end
end