defmodule Brando.MigrationTest.Project do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "Project",
    singular: "project",
    plural: "projects"

  trait Brando.Trait.Creator
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable

  attributes do
    attribute :title, :string
    attribute :status, :status, required: true
    attribute :slug, :slug, from: :title, required: true, unique: [prevent_collision: :language]

    attribute :cover, :image,
      allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
      default_size: "medium",
      upload_path: Path.join("images", "avatars"),
      random_filename: true,
      size_limit: 10_240_000,
      sizes: %{"micro" => %{"size" => "25", "quality" => 10, "crop" => false}},
      srcset: [{"small", "300w"}, {"medium", "500w"}, {"large", "700w"}]

    attribute :data, :villain
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
    plural: "projects"

  trait Brando.Trait.Creator
  trait Brando.Trait.Meta
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable

  attributes do
    attribute :title, :string
    attribute :status, :status, required: true
    attribute :slug, :slug, from: :title, required: true, unique: [prevent_collision: :language]
    attribute :summary, :text
    attribute :unique_hash, :text, unique: true

    attribute :cover, :image,
      allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
      default_size: "medium",
      upload_path: Path.join("images", "avatars"),
      random_filename: true,
      size_limit: 10_240_000,
      sizes: %{"micro" => %{"size" => "25", "quality" => 10, "crop" => false}},
      srcset: [{"small", "300w"}, {"medium", "500w"}, {"large", "700w"}]

    attribute :data, :villain
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
    plural: "projects"

  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable

  attributes do
    attribute :summary, :text
    attribute :unique_hash, :text, unique: true
    attribute :data, :villain
  end
end

defmodule Brando.MigrationTest.Property do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "Property",
    singular: "property",
    plural: "properties"

  data_layer :embedded

  attributes do
    attribute :key, :string
    attribute :value, :string
  end
end
