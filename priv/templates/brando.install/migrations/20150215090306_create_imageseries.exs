defmodule <%= application_module %>.Repo.Migrations.CreateImageseries do
  use Ecto.Migration
  use Brando.Sequence.Migration

  def up do
    create table(:imageseries) do
      add :name,              :text
      add :slug,              :text
      add :cfg,               :json
      add :credits,           :text
      add :creator_id,        references(:users)
      add :image_category_id, references(:imagecategories)
      sequenced()
      timestamps()
    end
    create unique_index(:imageseries, [:slug])
  end

  def down do
    drop table(:imageseries)
    drop index(:imageseries, [:slug])
    drop index(:imageseries, [:order])
  end
end
