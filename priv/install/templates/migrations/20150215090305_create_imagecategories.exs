defmodule <%= application_module %>.Repo.Migrations.CreateImagecategories do
  use Ecto.Migration
  def up do
    create table(:imagecategories) do
      add :name,              :text
      add :slug,              :text
      add :cfg,               :json
      add :creator_id,        references(:users)
      timestamps
    end
    create index(:imagecategories, [:slug])
  end

  def down do
    drop table(:imagecategories)
    drop index(:imagecategories, [:slug])
  end
end
