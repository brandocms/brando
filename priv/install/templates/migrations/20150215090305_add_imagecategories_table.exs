defmodule <%= application_module %>.Repo.Migrations.AddImagecategoriesTable do
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
    execute """
      INSERT INTO
        imagecategories
        (name, slug, cfg, creator_id, inserted_at, updated_at)
      VALUES
        ('post', 'post', NULL, 1, NOW(), NOW());
    """
    execute """
      INSERT INTO
        imagecategories
        (name, slug, cfg, creator_id, inserted_at, updated_at)
      VALUES
        ('page', 'page', NULL, 1, NOW(), NOW());
    """
  end

  def down do
    drop table(:imagecategories)
    drop index(:imagecategories, [:slug])
  end
end
