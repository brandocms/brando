defmodule Brando.Integration.TestRop.Migrations.CreateTestTables do
  use Ecto.Migration
  use Brando.Sequence, :migration
  use Brando.Tag, :migration

  def up do
    create table(:users_users) do
      add(:full_name, :text)
      add(:email, :text)
      add(:password, :text)
      add(:avatar, :jsonb)
      add(:role, :integer)
      add(:active, :boolean, default: true)
      add(:language, :text, default: "nb")
      add(:last_login, :naive_datetime)
      timestamps()
    end

    create(index(:users_users, [:email], unique: true))

    create table(:posts) do
      add(:language, :text)
      add(:header, :text)
      add(:slug, :text)
      add(:lead, :text)
      add(:data, :json)
      add(:html, :text)
      add(:cover, :text)
      add(:status, :integer)
      add(:creator_id, references(:users_users))
      add(:meta_description, :text)
      add(:meta_keywords, :text)
      add(:featured, :boolean)
      add(:published, :boolean)
      add(:publish_at, :naive_datetime)
      timestamps()
      tags()
    end

    create(index(:posts, [:language]))
    create(index(:posts, [:slug]))
    create(index(:posts, [:status]))
    create(index(:posts, [:tags]))

    create table(:images_categories) do
      add(:name, :text)
      add(:slug, :text)
      add(:cfg, :json)
      add(:creator_id, references(:users_users))
      timestamps()
    end

    create(index(:images_categories, [:slug]))

    create table(:images_series) do
      add(:name, :text)
      add(:slug, :text)
      add(:credits, :text)
      add(:cfg, :json)
      add(:creator_id, references(:users_users))
      add(:image_category_id, references(:images_categories))
      sequenced()
      timestamps()
    end

    create table(:images_images) do
      add(:image, :jsonb)
      add(:creator_id, references(:users_users))
      add(:image_series_id, references(:images_series))
      sequenced()
      timestamps()
    end

    create table(:instagramimages) do
      add(:instagram_id, :text)
      add(:type, :text)
      add(:caption, :text)
      add(:link, :text)
      add(:username, :text)
      add(:url_original, :text)
      add(:url_thumbnail, :text)
      add(:image, :text)
      add(:created_time, :text)
      add(:status, :integer, default: 1)
    end

    create table(:pages_pages) do
      add(:key, :text)
      add(:language, :text)
      add(:title, :text)
      add(:slug, :text)
      add(:data, :json)
      add(:html, :text)
      add(:status, :integer)
      add(:parent_id, references(:pages_pages), default: nil)
      add(:creator_id, references(:users_users))
      add(:css_classes, :text)
      add(:meta_description, :text)
      add(:meta_keywords, :text)
      timestamps()
    end

    create(index(:pages_pages, [:language]))
    create(index(:pages_pages, [:slug]))
    create(index(:pages_pages, [:key]))
    create(index(:pages_pages, [:parent_id]))
    create(index(:pages_pages, [:status]))

    create table(:pages_fragments) do
      add(:key, :text)
      add(:language, :text)
      add(:data, :json)
      add(:html, :text)
      add(:creator_id, references(:users_users))
      timestamps()
    end

    create(index(:pages_fragments, [:language]))
    create(index(:pages_fragments, [:key]))
  end

  def down do
    drop(table(:users_users))
    drop(index(:users_users, [:email], unique: true))

    drop(table(:posts))
    drop(index(:posts, [:language]))
    drop(index(:posts, [:slug]))
    drop(index(:posts, [:key]))
    drop(index(:posts, [:status]))

    drop(table(:images_categories))
    drop(index(:images_categories, [:slug]))

    drop(table(:images_series))
    drop(index(:images_series, [:slug]))

    drop(table(:images_images))

    drop(table(:instagramimages))

    drop(table(:pages_fragments))
    drop(index(:pages_fragments, [:language]))
    drop(index(:pages_fragments, [:key]))
  end
end
