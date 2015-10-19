defmodule <%= application_module %>.Repo.Migrations.CreatePostimages do
  use Ecto.Migration

  def up do
    create table(:postimages) do
      add :title,              :text
      add :credits,            :text
      add :image,              :text
      timestamps
    end
  end

  def down do
    drop table(:postimages)
  end
end
