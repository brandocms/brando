defmodule BrandoIntegration.TestRop.Migrations.CreateTestTables do
  use Ecto.Migration
  use Brando.Sequence.Migration
  use Brando.Tag, :migration

  import Brando.SoftDelete.Migration

  def up do
    create table(:images) do
      add :title, :text
      add :credits, :text
      add :alt, :text
      add :formats, {:array, :string}
      add :path, :text
      add :width, :integer
      add :height, :integer
      add :status, :string
      add :sizes, :map
      add :cdn, :boolean, default: false
      add :dominant_color, :text
      add :focal, :jsonb
      add :config_target, :text, default: "default"
      soft_delete()
      sequenced()
      timestamps()
    end

    create table(:users) do
      add(:name, :text)
      add(:email, :text)
      add(:password, :text)
      add(:avatar_id, references(:images))
      add(:role, :string)
      add(:config, :map)
      add(:active, :boolean, default: true)
      add(:language, :text, default: "no")
      add(:last_login, :naive_datetime)
      timestamps()
      soft_delete()
    end

    create(index(:users, [:email], unique: true))

    create table(:images_galleries) do
      add :config_target, :text
      add :deleted_at, :utc_datetime
      add :creator_id, references(:users, on_delete: :nothing)
      timestamps()
    end

    create table(:images_gallery_images) do
      add :sequence, :integer
      add :gallery_id, references(:images_galleries, on_delete: :delete_all)
      add :image_id, references(:images, on_delete: :delete_all)
      add :creator_id, references(:users, on_delete: :nothing)
      timestamps()
    end


    alter table(:images) do
      add :creator_id, references(:users)
    end

    create table(:files) do
      add :title, :text
      add :mime_type, :text
      add :filesize, :integer
      add :filename, :text
      add :config_target, :text
      add :cdn, :boolean
      add :deleted_at, :utc_datetime
      timestamps()
      add :creator_id, references(:users, on_delete: :nothing)
    end

    create table(:videos) do
      add :url, :text
      add :source, :text
      add :filename, :text
      add :remote_id, :text
      add :width, :integer
      add :height, :integer
      add :thumbnail_url, :text
      add :autoplay, :boolean
      add :preload, :boolean
      add :loop, :boolean
      add :controls, :boolean
      add :cdn, :boolean
      add :config_target, :text
      add :creator_id, references(:users, on_delete: :nothing)
      add :cover_image_id, references(:images, on_delete: :nilify_all)
      add :deleted_at, :utc_datetime
      timestamps()
    end

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      timestamps(updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])

    create table(:posts) do
      add(:language, :text)
      add(:header, :text)
      add(:slug, :text)
      add(:lead, :text)
      add(:data, :json)
      add(:html, :text)
      add(:cover, :text)
      add(:status, :integer)
      add(:creator_id, references(:users))
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

    create table(:pages) do
      add :uri, :text
      add :language, :text
      add :title, :text
      add :data, :jsonb
      add :html, :text
      add :vars, :jsonb
      add :status, :integer
      add :is_homepage, :boolean
      add :parent_id, references(:pages), default: nil
      add :creator_id, references(:users)
      add :css_classes, :text
      add :template, :text
      add :publish_at, :utc_datetime
      add :has_url, :boolean, default: true
      add :meta_title, :text
      add :meta_description, :text
      add :meta_image_id, references(:images)
      sequenced()
      soft_delete()
      timestamps()
    end

    create(index(:pages, [:language]))
    create(index(:pages, [:uri]))
    create(unique_index(:pages, [:uri, :language]))
    create(index(:pages, [:parent_id]))
    create(index(:pages, [:status]))

    create table(:pages_fragments) do
      add(:key, :text)
      add(:parent_key, :text)
      add(:language, :text)
      add(:title, :text)
      add(:wrapper, :text)
      add(:data, :jsonb)
      add(:html, :text)
      add(:status, :integer)
      add(:sequence, :integer)
      add(:publish_at, :utc_datetime)
      add(:creator_id, references(:users))
      add(:page_id, references(:pages))
      soft_delete()
      timestamps()
    end

    create(index(:pages_fragments, [:language]))
    create(index(:pages_fragments, [:key]))
    create(index(:pages_fragments, [:parent_key]))

    create table(:pages_alternates) do
      add :entry_id, references(:pages, on_delete: :delete_all)
      add :linked_entry_id, references(:pages, on_delete: :delete_all)
      timestamps()
    end

    create unique_index(:pages_alternates, [:entry_id, :linked_entry_id])

    create table(:content_modules) do
      add :name, :string
      add :namespace, :string
      add :help_text, :text
      add :class, :string
      add :code, :text
      add :refs, :jsonb
      add :vars, :jsonb
      add :svg, :string
      add :multi, :boolean
      add :wrapper, :boolean
      add :entry_template, :jsonb
      add :datasource, :boolean
      add :datasource_module, :string
      add :datasource_type, :string
      add :datasource_query, :string
      sequenced()
      timestamps()
      soft_delete()
    end

    create index(:content_modules, [:namespace])

    create table(:content_palettes) do
      add :name, :text
      add :key, :text
      add :namespace, :text
      add :sequence, :integer
      add :status, :integer
      add :global, :boolean, default: false
      add :instructions, :text
      add :colors, :jsonb
      add :deleted_at, :utc_datetime
      add :creator_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end


    create table(:content_templates) do
      add :name, :text
      add :namespace, :text
      add :sequence, :integer
      add :instructions, :text
      add :deleted_at, :utc_datetime
      add :creator_id, references(:users, on_delete: :nilify_all)
      add :data, :jsonb
      add :html, :text

      timestamps()
    end

    create table(:projects) do
      add :title, :string
      add :status, :integer
      add :slug, :string
      add :language, :string
      add :data, :jsonb
      add :html, :text
      add :bio_data, :jsonb
      add :bio_html, :text
      add :cover_id, references(:images)
      add :pdf_id, references(:files)
      add :properties, :map
      add :creator_id, references(:users, on_delete: :nilify_all)

      sequenced()
      soft_delete()
      timestamps()
    end

    create table(:projects_related) do
      add :project_id, references(:projects)
      add :related_project_id, references(:projects)
    end

    create table(:persons_profile, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :status, :text
      add :sequence, :integer
      add :deleted_at, :utc_datetime
      timestamps()
      add :creator_id, references(:users)
    end

    create table(:persons, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :text
      add :email, :text
      add :deleted_at, :utc_datetime
      add :sequence, :integer
      timestamps()
      add :language, :text
      add :profile_id, references(:persons_profile, type: :uuid)
      add :creator_id, references(:users)
    end

    create index(:persons, [:language])

    create table(:sites_identities) do
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
      add :logo_id, references(:images)
      add :url, :string

      add :language, :string

      add :metas, :jsonb
      add :links, :jsonb
      add :configs, :jsonb
      add :type, :string, default: "organization"

      timestamps()
    end

    create table(:sites_seos) do
      add :fallback_meta_description, :text
      add :fallback_meta_title, :text
      add :fallback_meta_image_id, references(:images)
      add :base_url, :text
      add :language, :string
      add :robots, :text
      add :redirects, :map
      timestamps()
    end

    create table(:sites_global_sets) do
      add :key, :string
      add :label, :text
      add :language, :text
      add :globals, :jsonb
      add :creator_id, references(:users)
      timestamps()
    end

    create table(:navigation_menus) do
      add :status, :integer
      add :title, :text
      add :key, :text
      add :language, :text
      add :template, :text
      add :creator_id, references(:users)
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
      add :creator_id, references(:users, on_delete: :nilify_all)
      add :description, :string
      add :metadata, :map, null: false
      add :revision, :integer, null: false
      add :protected, :boolean, default: false
      timestamps()
    end

    create unique_index(:revisions, [:entry_type, :entry_id, :revision])

    create table(:content_identifiers) do
      add :entry_id, :id
      add :schema, :string
      add :title, :string
      add :status, :integer
      add :language, :string
      add :cover, :string
      add :updated_at, :utc_datetime
    end

    create unique_index(:content_identifiers, [:entry_id, :schema])
  end

  def down do
    drop table(:users)
    drop index(:users, [:email], unique: true)

    drop table(:posts)
    drop index(:posts, [:language])
    drop index(:posts, [:slug])
    drop index(:posts, [:key])
    drop index(:posts, [:status])

    drop table(:images)
    drop table(:images_galleries)
    drop table(:images_gallery_images)

    drop table(:pages_fragments)
    drop index(:pages_fragments, [:language])
    drop index(:pages_fragments, [:key])

    drop table(:sites_global_sets)
    drop table(:sites_globals)
  end
end
