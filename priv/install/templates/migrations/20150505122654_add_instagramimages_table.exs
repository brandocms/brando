defmodule <%= application_module %>.Repo.Migrations.AddInstagramimagesTable do
  use Ecto.Migration

  def up do
    create table(:instagramimages) do
      add :instagram_id,  :text
      add :type,          :text
      add :caption,       :text
      add :link,          :text
      add :username,      :text
      add :url_original,  :text
      add :url_thumbnail, :text
      add :created_time,  :text
      add :approved,      :boolean, default: false
      add :deleted,       :boolean, default: false
    end
  end

  def down do
    drop table(:instagramimages)
  end
end
