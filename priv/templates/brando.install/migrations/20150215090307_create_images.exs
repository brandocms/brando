defmodule <%= application_module %>.Repo.Migrations.CreateImages do
  use Ecto.Migration

  def up do
    create table(:images) do
      add :image,             :jsonb
      add :creator_id,        references(:users)
      add :image_series_id,   references(:imageseries)
      add :sequence, :integer
      timestamps()
    end
  end

  def down do
    drop table(:images)
  end
end
