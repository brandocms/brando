defmodule <%= application_module %>.Repo.Migrations.CreateImages do
  use Ecto.Migration
  use Brando.Sequence, :migration

  def up do
    create table(:images) do
      add :image,             :jsonb
      add :creator_id,        references(:users)
      add :image_series_id,   references(:imageseries)
      sequenced()
      timestamps()
    end
  end

  def down do
    drop table(:images)
  end
end
