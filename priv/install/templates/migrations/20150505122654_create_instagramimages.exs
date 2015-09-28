defmodule <%= application_module %>.Repo.Migrations.CreateInstagramimages do
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
      add :image,         :text
      add :created_time,  :text
      add :status,        :integer, default: 1
    end
  end

  def down do
    drop table(:instagramimages)
  end
end
