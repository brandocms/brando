defmodule Brando.Integration.Migration do
  use Ecto.Migration
  use Brando.Sequence, :migration
  def up do
    create table(:users) do
      add :username,      :text
      add :full_name,     :text
      add :email,         :text
      add :password,      :text
      add :avatar,        :text
      add :role,          :integer
      add :last_login,    :datetime
      timestamps
    end

    create index(:users, [:username], unique: true)
    create index(:users, [:email], unique: true)

    create table(:posts) do
      add :language,          :text
      add :header,            :text
      add :slug,              :text
      add :lead,              :text
      add :data,              :json
      add :html,              :text
      add :cover,             :text
      add :status,            :integer
      add :creator_id,        references(:users)
      add :meta_description,  :text
      add :meta_keywords,     :text
      add :featured,          :boolean
      add :published,         :boolean
      add :publish_at,        :datetime
      timestamps
    end

    create index(:posts, [:language])
    create index(:posts, [:slug])
    create index(:posts, [:status])

    create table(:imagecategories) do
      add :name,              :text
      add :slug,              :text
      add :cfg,               :json
      add :creator_id,        references(:users)
      timestamps
    end
    create index(:imagecategories, [:slug])

    create table(:imageseries) do
      add :name,              :text
      add :slug,              :text
      add :credits,           :text
      add :order,             :integer
      add :creator_id,        references(:users)
      add :image_category_id, references(:imagecategories)
      timestamps
    end
    create index(:imageseries, [:slug])
    create index(:imageseries, [:order])

    create table(:images) do
      add :image,             :text
      add :creator_id,        references(:users)
      add :image_series_id,   references(:imageseries)
      sequenced
      timestamps
    end

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
      add :approved,      :boolean, default: false
      add :deleted,       :boolean, default: false
    end

    create table(:pages) do
      add :key,               :text
      add :language,          :text
      add :title,             :text
      add :slug,              :text
      add :data,              :json
      add :html,              :text
      add :status,            :integer
      add :parent_id,         references(:pages), default: nil
      add :creator_id,        references(:users)
      add :meta_description,  :text
      add :meta_keywords,     :text
      timestamps
    end
    create index(:pages, [:language])
    create index(:pages, [:slug])
    create index(:pages, [:key])
    create index(:pages, [:parent_id])
    create index(:pages, [:status])

    create table(:pagefragments) do
      add :key,               :text
      add :language,          :text
      add :data,              :json
      add :html,              :text
      add :creator_id,        references(:users)
      timestamps
    end
    create index(:pagefragments, [:language])
    create index(:pagefragments, [:key])
  end

  def down do
    drop table(:users)
    drop index(:users, [:username], unique: true)
    drop index(:users, [:email], unique: true)

    drop table(:posts)
    drop index(:posts, [:language])
    drop index(:posts, [:slug])
    drop index(:posts, [:key])
    drop index(:posts, [:status])

    drop table(:imagecategories)
    drop index(:imagecategories, [:slug])

    drop table(:imageseries)
    drop index(:imageseries, [:slug])
    drop index(:imageseries, [:order])

    drop table(:images)

    drop table(:instagramimages)

    drop table(:pagefragments)
    drop index(:pagefragments, [:language])
    drop index(:pagefragments, [:key])
  end
end