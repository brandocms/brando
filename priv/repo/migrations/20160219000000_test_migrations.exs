defmodule BrandoIntegration.TestRop.Migrations.CreateTestTables do
  use Ecto.Migration
  use Brando.Sequence.Migration
  use Brando.Tag, :migration

  import Brando.SoftDelete.Migration
  import Brando.Meta.Migration

  def up do
    create table(:users_users) do
      add(:name, :text)
      add(:email, :text)
      add(:password, :text)
      add(:avatar, :jsonb)
      add(:role, :integer)
      add(:config, :map)
      add(:active, :boolean, default: true)
      add(:language, :text, default: "no")
      add(:last_login, :naive_datetime)
      timestamps()
      soft_delete()
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
      add(:featured, :boolean)
      add(:published, :boolean)
      add(:publish_at, :naive_datetime)
      timestamps()
      soft_delete()
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
      soft_delete()
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
      soft_delete()
      sequenced()
      timestamps()
    end

    create table(:images_images) do
      add(:image, :jsonb)
      add(:creator_id, references(:users_users))
      add(:image_series_id, references(:images_series))
      soft_delete()
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
      add(:uri, :text)
      add(:language, :text)
      add(:title, :text)
      add(:data, :json)
      add(:html, :text)
      add(:status, :integer)
      add(:is_homepage, :boolean)
      add(:parent_id, references(:pages_pages), default: nil)
      add(:creator_id, references(:users_users))
      add(:css_classes, :text)
      add(:template, :text)
      meta_fields()
      add(:publish_at, :utc_datetime)
      sequenced()
      soft_delete()
      timestamps()
    end

    create(index(:pages_pages, [:language]))
    create(index(:pages_pages, [:uri]))
    create(unique_index(:pages_pages, [:uri, :language]))
    create(index(:pages_pages, [:parent_id]))
    create(index(:pages_pages, [:status]))

    create table(:pages_properties) do
      add :key, :string
      add :label, :text
      add :type, :string
      add :data, :jsonb
      add :page_id, references(:pages_pages, on_delete: :delete_all)
    end

    create table(:pages_fragments) do
      add(:key, :text)
      add(:parent_key, :text)
      add(:language, :text)
      add(:title, :text)
      add(:wrapper, :text)
      add(:data, :json)
      add(:html, :text)
      add(:sequence, :integer)
      add(:creator_id, references(:users_users))
      add(:page_id, references(:pages_pages))
      soft_delete()
      timestamps()
    end

    create(index(:pages_fragments, [:language]))
    create(index(:pages_fragments, [:key]))
    create(index(:pages_fragments, [:parent_key]))

    create table(:pages_modules) do
      add :name, :string
      add :namespace, :string
      add :help_text, :text
      add :class, :string
      add :code, :text
      add :refs, :jsonb
      add :vars, :jsonb
      add :svg, :string
      add :multi, :boolean
      add :wrapper, :string
      sequenced()
      timestamps()
      soft_delete()
    end

    create index(:pages_modules, [:namespace])

    create table(:sites_identity) do
      add :name, :string
      add :alternate_name, :string
      add :email, :string
      add :phone, :string
      add :address, :string
      add :address2, :string
      add :address3, :string
      add :zipcode, :string
      add :city, :string
      add :country, :string
      add :description, :text
      add :title_prefix, :string
      add :title, :text
      add :title_postfix, :string
      add :image, :jsonb
      add :logo, :jsonb
      add :url, :string

      add :metas, :map
      add :links, :map
      add :configs, :map
      add :type, :string, default: "organization"

      timestamps()
    end

    create table(:sites_seo) do
      add :fallback_meta_description, :text
      add :fallback_meta_title, :text
      add :fallback_meta_image, :jsonb
      add :base_url, :text
      add :robots, :text
      add :redirects, :map
      timestamps()
    end

    create table(:sites_global_categories) do
      add :key, :string
      add :label, :text
    end

    create table(:sites_globals) do
      add :key, :string
      add :label, :text
      add :type, :string
      add :data, :jsonb
      add :global_category_id, references(:sites_global_categories, on_delete: :delete_all)
    end

    create table(:navigation_menus) do
      add :status, :integer
      add :title, :text
      add :key, :text
      add :language, :text
      add :template, :text
      add :creator_id, references(:users_users)
      add :items, :map
      sequenced()
      timestamps()
    end

    create table(:tags) do
    end

    create table(:photos) do
    end

    create table(:photos_to_tags, primary_key: false) do
      add :tag_id, references(:tags, on_delete: :nothing), null: false
      add :photo_id, references(:photos, on_delete: :nothing), null: false
    end

    create table(:revisions, primary_key: false) do
      add :active, :boolean, default: false
      add :entry_id, :integer, null: false
      add :entry_type, :string, null: false
      add :encoded_entry, :binary, null: false
      add :creator_id, references(:users_users, on_delete: :nilify_all)
      add :description, :string
      add :metadata, :map, null: false
      add :revision, :integer, null: false
      add :protected, :boolean, default: false
      timestamps()
    end

    create unique_index(:revisions, [:entry_type, :entry_id, :revision])
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

    drop table(:sites_global_categories)
    drop table(:sites_globals)
  end
end
