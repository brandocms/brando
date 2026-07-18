defmodule Brando.MigrationTest.Project do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "Project",
    singular: "project",
    plural: "projects",
    gettext_module: Brando.Gettext

  trait Brando.Trait.Creator
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable

  absolute_url ~H|/projects/{@entry.creator.slug}/{Enum.at(@entry.properties, 0).slug}/{Enum.at(@entry.properties, 0).title}/{@entry.slug}|

  attributes do
    attribute :title, :string
    attribute :status, :status, required: true
    attribute :slug, :slug, required: true, unique: [prevent_collision: :language]
  end

  assets do
    asset :cover, :image,
      cfg: [
        allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
        upload_path: Path.join("images", "avatars"),
        random_filename: true,
        size_limit: 10_240_000,
        sizes: %{"micro" => %{"size" => "25", "quality" => 10, "crop" => false}},
        srcset: [{"small", "300w"}, {"medium", "500w"}, {"large", "700w"}]
      ]
  end

  relations do
    relation :properties, :embeds_many, module: Brando.MigrationTest.Property
  end
end

defmodule Brando.MigrationTest.ProjectUpdate1 do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "Project",
    singular: "project",
    plural: "projects",
    gettext_module: Brando.Gettext

  trait Brando.Trait.Creator
  trait Brando.Trait.Meta
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable

  attributes do
    attribute :title, :string
    attribute :status, :status, required: true
    attribute :slug, :slug, required: true, unique: [prevent_collision: :language]
    attribute :summary, :text
    attribute :unique_hash, :text, unique: true
  end

  assets do
    asset :cover, :image,
      cfg: [
        allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
        default_size: "medium",
        upload_path: Path.join("images", "avatars"),
        random_filename: true,
        size_limit: 10_240_000,
        sizes: %{"micro" => %{"size" => "25", "quality" => 10, "crop" => false}},
        srcset: [{"small", "300w"}, {"medium", "500w"}, {"large", "700w"}]
      ]

    asset :photos, :gallery,
      cfg: [
        allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
        default_size: "medium",
        upload_path: Path.join("images", "photos"),
        random_filename: true,
        size_limit: 10_240_000,
        sizes: %{"micro" => %{"size" => "25", "quality" => 10, "crop" => false}},
        srcset: [{"small", "300w"}, {"medium", "500w"}, {"large", "700w"}]
      ]
  end

  relations do
    relation :properties, :embeds_many, module: Brando.MigrationTest.Property
    relation :more_properties, :embeds_many, module: Brando.MigrationTest.Property
  end
end

defmodule Brando.MigrationTest.ProjectUpdate2 do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "Project",
    singular: "project",
    plural: "projects",
    gettext_module: Brando.Gettext

  trait Brando.Trait.Sequenced
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable

  attributes do
    attribute :summary, :text
    attribute :unique_hash, :text, unique: true
  end
end

defmodule Brando.MigrationTest.Property do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "Property",
    singular: "property",
    plural: "properties",
    gettext_module: Brando.Gettext

  data_layer :embedded

  attributes do
    attribute :key, :string
    attribute :value, :string
  end
end

defmodule Brando.MigrationTest.Profile do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Persons",
    schema: "Person",
    singular: "profiles",
    plural: "profile",
    gettext_module: Brando.Gettext

  trait Brando.Trait.Creator
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Timestamped

  primary_key :uuid

  attributes do
    attribute :status, :string
  end
end

defmodule Brando.Persons.Person do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Persons",
    schema: "Person",
    singular: "person",
    plural: "persons",
    gettext_module: Brando.Gettext

  trait Brando.Trait.Creator
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable

  primary_key :uuid

  attributes do
    attribute :name, :string
    attribute :email, :string, required: true
  end

  relations do
    relation :profile, :belongs_to, module: Brando.MigrationTest.Profile, type: :binary_id
    relation :related_entries, :entries, constraints: [max_length: 3]
  end
end

defmodule Brando.MigrationTest.Tag do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "Tag",
    singular: "tag",
    plural: "tags",
    gettext_module: Brando.Gettext

  trait Brando.Trait.Timestamped

  attributes do
    attribute :name, :string, required: true
  end
end

defmodule Brando.MigrationTest.ProjectTag do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "ProjectTag",
    singular: "project_tag",
    plural: "project_tags",
    gettext_module: Brando.Gettext

  trait Brando.Trait.Sequenced

  @allow_mark_as_deleted true

  relations do
    relation :project, :belongs_to, module: Brando.MigrationTest.Project
    relation :tag, :belongs_to, module: Brando.MigrationTest.Tag
  end
end

defmodule Brando.MigrationTest.StorageV1 do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Storage",
    schema: "Record",
    singular: "storage_record",
    plural: "storage_records",
    gettext_module: Brando.Gettext

  attributes do
    attribute :legacy_title, :string
  end
end

defmodule Brando.MigrationTest.StorageV2 do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Storage",
    schema: "Record",
    singular: "storage_record",
    plural: "storage_records",
    gettext_module: Brando.Gettext

  attributes do
    attribute :title, :integer, rename_from: :legacy_title
  end
end

defmodule Brando.MigrationTest.StorageTableV2 do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Storage",
    schema: "Record",
    singular: "storage_record",
    plural: "storage_records",
    gettext_module: Brando.Gettext

  table "renamed_storage_records"

  attributes do
    attribute :legacy_title, :string
  end
end

defmodule Brando.MigrationTest.StorageUuidV2 do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Storage",
    schema: "Record",
    singular: "storage_record",
    plural: "storage_records",
    gettext_module: Brando.Gettext

  primary_key :uuid

  attributes do
    attribute :legacy_title, :string
  end
end

defmodule Brando.MigrationTest.ExecutionV1 do
  use Brando.Blueprint,
    application: "Brando",
    domain: "MigrationExecution",
    schema: "Record",
    singular: "record",
    plural: "records",
    gettext_module: Brando.Gettext

  table "blueprint_migration_execution_records"

  attributes do
    attribute :title, :string
  end
end

defmodule Brando.MigrationTest.ExecutionV2 do
  use Brando.Blueprint,
    application: "Brando",
    domain: "MigrationExecution",
    schema: "Record",
    singular: "record",
    plural: "records",
    gettext_module: Brando.Gettext

  table "blueprint_migration_execution_records"

  attributes do
    attribute :count, :integer, default: 0, unique: true
    attribute :title, :string
  end
end

defmodule Brando.MigrationTest.LongIdentifiers do
  use Brando.Blueprint,
    application: "Brando",
    domain: "MigrationIdentifiers",
    schema: "Record",
    singular: "record",
    plural: "records",
    gettext_module: Brando.Gettext

  table "blueprint_runtime_constraint_records"

  attributes do
    attribute :tenant_reference_identifier, :integer

    attribute :uniqueness_value, :string,
      unique: [with: :tenant_reference_identifier, message: "has already been used for this tenant"]
  end

  relations do
    relation :owner, :belongs_to,
      module: Brando.Users.User,
      foreign_key: :owner_reference_identifier_id
  end
end

defmodule Brando.MigrationTest.UniqueLanguage do
  use Brando.Blueprint,
    application: "Brando",
    domain: "MigrationConstraints",
    schema: "UniqueLanguage",
    singular: "unique_language",
    plural: "unique_languages",
    gettext_module: Brando.Gettext

  attributes do
    attribute :language, :language, unique: true
  end
end

defmodule Brando.MigrationTest.CollidingIndexNames do
  use Brando.Blueprint,
    application: "Brando",
    domain: "MigrationConstraints",
    schema: "CollidingIndexNames",
    singular: "colliding_index_names",
    plural: "colliding_index_names",
    gettext_module: Brando.Gettext

  table "blueprint_constraint_collision_records"

  attributes do
    attribute :extremely_long_shared_prefix_alpha, :string, unique: true
    attribute :extremely_long_shared_prefix_beta, :string, unique: true
  end
end

defmodule Brando.MigrationTest.CollidingForeignKeyNames do
  use Brando.Blueprint,
    application: "Brando",
    domain: "MigrationConstraints",
    schema: "CollidingForeignKeyNames",
    singular: "colliding_foreign_key_names",
    plural: "colliding_foreign_key_names",
    gettext_module: Brando.Gettext

  relations do
    relation :primary_owner, :belongs_to,
      module: Brando.Users.User,
      constraint_name: "duplicate_owner_fkey"

    relation :secondary_owner, :belongs_to,
      module: Brando.Users.User,
      constraint_name: "duplicate_owner_fkey"
  end
end

defmodule Brando.MigrationTest.PhysicalSources do
  use Brando.Blueprint,
    application: "Brando",
    domain: "MigrationSources",
    schema: "PhysicalSources",
    singular: "physical_source",
    plural: "physical_sources",
    gettext_module: Brando.Gettext

  primary_key {:id, :id, autogenerate: true, source: :record_pk}

  attributes do
    attribute :tenant_id, :integer, source: :account_ref
    attribute :title, :string, source: :headline, unique: [with: :tenant_id]
  end

  relations do
    relation :metadata, :embeds_one,
      module: Brando.MigrationTest.Property,
      source: :payload

    relation :owner, :belongs_to,
      module: Brando.Users.User,
      source: :owner_ref,
      unique: [with: :tenant_id]

    relation :related_entries, :entries
  end
end

defmodule Brando.MigrationTest.ManualPhysicalForeignKey do
  use Brando.Blueprint,
    application: "Brando",
    domain: "MigrationSources",
    schema: "ManualPhysicalForeignKey",
    singular: "manual_physical_foreign_key",
    plural: "manual_physical_foreign_keys",
    gettext_module: Brando.Gettext

  attributes do
    attribute :owner_id, :id, source: :owner_ref
  end

  relations do
    relation :owner, :belongs_to,
      module: Brando.Users.User,
      foreign_key: :owner_id,
      define_field: false
  end
end

defmodule Brando.MigrationTest.PhysicalSourceV1 do
  use Brando.Blueprint,
    application: "Brando",
    domain: "MigrationSources",
    schema: "PhysicalSourceRename",
    singular: "physical_source_rename",
    plural: "physical_source_renames",
    gettext_module: Brando.Gettext

  table "blueprint_physical_source_renames"

  attributes do
    attribute :title, :string, unique: true
  end
end

defmodule Brando.MigrationTest.PhysicalSourceV2 do
  use Brando.Blueprint,
    application: "Brando",
    domain: "MigrationSources",
    schema: "PhysicalSourceRename",
    singular: "physical_source_rename",
    plural: "physical_source_renames",
    gettext_module: Brando.Gettext

  table "blueprint_physical_source_renames"

  attributes do
    attribute :title, :string, source: :headline, rename_from: :title, unique: true
  end
end

defmodule Brando.MigrationTest.NoPrimaryKey do
  use Brando.Blueprint,
    application: "Brando",
    domain: "MigrationSources",
    schema: "NoPrimaryKey",
    singular: "no_primary_key",
    plural: "no_primary_keys",
    gettext_module: Brando.Gettext

  primary_key false

  attributes do
    attribute :key, :string
  end
end
