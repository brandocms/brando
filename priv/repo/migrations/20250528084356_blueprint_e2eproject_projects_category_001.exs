defmodule E2eProject.Migrations.Projects.Category.Blueprint001 do
  use Ecto.Migration

  def up do
    create table(:projects_categories) do
      add :status, :integer
      add :language, :text
      add :title, :text
      add :slug, :text
      add :sequence, :integer
      timestamps()
      add :creator_id, references(:users, on_delete: :nothing)
    end

    create index(:projects_categories, [:language])
    create unique_index(:projects_categories, [:slug])

    create table(:projects_categories_alternates) do
      add :entry_id, references(:projects_categories, on_delete: :delete_all)
      add :linked_entry_id, references(:projects_categories, on_delete: :delete_all)
      timestamps()
    end

    create unique_index(:projects_categories_alternates, [:entry_id, :linked_entry_id])
  end

  def down do
    drop table(:projects_categories)

    drop index(:projects_categories, [:language])
    drop unique_index(:projects_categories, [:slug])

    drop table(:projects_categories_alternates)
  end
end