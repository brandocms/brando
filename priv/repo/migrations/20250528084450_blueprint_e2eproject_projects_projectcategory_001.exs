defmodule E2eProject.Migrations.Projects.ProjectCategory.Blueprint001 do
  use Ecto.Migration

  def up do
    create table(:projects_project_categories) do
      add :project_id, references(:projects_projects, on_delete: :nothing)
      add :category_id, references(:projects_categories, on_delete: :nothing)
      add :sequence, :integer
    end
  end

  def down do
    drop table(:projects_project_categories)
  end
end
