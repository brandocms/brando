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
