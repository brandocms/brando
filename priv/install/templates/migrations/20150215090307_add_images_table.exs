defmodule <%= application_module %>.Repo.Migrations.AddImagesTable do
  use Ecto.Migration

  def up do
    create table(:images) do
      add :title,             :text
      add :credits,           :text
      add :order,             :integer
      add :optimized,         :boolean
      add :creator_id,        references(:users)
      add :image_series_id,   references(:imageseries)
      timestamps
    end
    create index(:images, [:order])
  end

  def down do
    drop table(:images)
    drop index(:images, [:order])
  end
end
