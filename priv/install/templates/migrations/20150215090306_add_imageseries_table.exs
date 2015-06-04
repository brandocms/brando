defmodule <%= application_module %>.Repo.Migrations.AddImageseriesTable do
  use Ecto.Migration
  use Brando.Sequence, :migration

  def up do
    create table(:imageseries) do
      add :name,              :text
      add :slug,              :text
      add :credits,           :text
      add :creator_id,        references(:users)
      add :image_category_id, references(:imagecategories)
      sequenced
      timestamps
    end
    create index(:imageseries, [:slug])
    execute """
      INSERT INTO
        imageseries
        ("name", "slug", "credits", "sequence", "creator_id", "image_category_id", "inserted_at", "updated_at")
      VALUES
        ('post', 'post', NULL, 0, 1, 1, NOW(), NOW());
    """
    execute """
      INSERT INTO
        imageseries
        ("name", "slug", "credits", "sequence", "creator_id", "image_category_id", "inserted_at", "updated_at")
      VALUES
        ('page', 'page', NULL, 0, 1, 2, NOW(), NOW());
    """
  end

  def down do
    drop table(:imageseries)
    drop index(:imageseries, [:slug])
    drop index(:imageseries, [:order])
  end
end
