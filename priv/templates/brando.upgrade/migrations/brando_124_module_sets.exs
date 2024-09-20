defmodule Brando.Repo.Migrations.ModuleSets do
  use Ecto.Migration

  def up do
    create table(:content_module_sets) do
      add :title, :text
      add :creator_id, references(:users, on_delete: :nothing)
      timestamps()
    end

    create table(:content_module_set_modules) do
      timestamps()
      add :module_id, references(:content_modules, on_delete: :delete_all)
      add :module_set_id, references(:content_module_sets, on_delete: :delete_all)
      add :sequence, :integer
    end
  end

  def down do
    drop table(:content_module_set_modules)
    drop table(:content_module_sets)
  end
end
