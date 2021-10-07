defmodule Brando.MigrationTest.Project do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "Project",
    singular: "project",
    plural: "projects"

  trait(Brando.Trait.Creator)
  trait(Brando.Trait.SoftDelete)
  trait(Brando.Trait.Sequenced)
  trait(Brando.Trait.Timestamped)
  trait(Brando.Trait.Translatable)

  attributes do
    attribute(:title, :string)
    attribute(:status, :status, required: true)
    attribute(:slug, :slug, from: :title, required: true, unique: [prevent_collision: :language])
    attribute(:data, :villain)
  end

  assets do
    asset(:cover, :image,
      cfg: [
        allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
        upload_path: Path.join("images", "avatars"),
        random_filename: true,
        size_limit: 10_240_000,
        sizes: %{"micro" => %{"size" => "25", "quality" => 10, "crop" => false}},
        srcset: [{"small", "300w"}, {"medium", "500w"}, {"large", "700w"}]
      ]
    )
  end

  relations do
    relation(:properties, :embeds_many, module: Brando.MigrationTest.Property)
  end
end

defmodule Brando.MigrationTest.ProjectUpdate1 do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "Project",
    singular: "project",
    plural: "projects"

  trait(Brando.Trait.Creator)
  trait(Brando.Trait.Meta)
  trait(Brando.Trait.Sequenced)
  trait(Brando.Trait.Timestamped)
  trait(Brando.Trait.Translatable)

  attributes do
    attribute(:title, :string)
    attribute(:status, :status, required: true)
    attribute(:slug, :slug, from: :title, required: true, unique: [prevent_collision: :language])
    attribute(:summary, :text)
    attribute(:unique_hash, :text, unique: true)

    attribute(:data, :villain)
  end

  assets do
    asset(:cover, :image,
      cfg: [
        allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
        default_size: "medium",
        upload_path: Path.join("images", "avatars"),
        random_filename: true,
        size_limit: 10_240_000,
        sizes: %{"micro" => %{"size" => "25", "quality" => 10, "crop" => false}},
        srcset: [{"small", "300w"}, {"medium", "500w"}, {"large", "700w"}]
      ]
    )
  end

  relations do
    relation(:properties, :embeds_many, module: Brando.MigrationTest.Property)
    relation(:more_properties, :embeds_many, module: Brando.MigrationTest.Property)
  end
end

defmodule Brando.MigrationTest.ProjectUpdate2 do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "Project",
    singular: "project",
    plural: "projects"

  trait(Brando.Trait.Sequenced)
  trait(Brando.Trait.Timestamped)
  trait(Brando.Trait.Translatable)

  attributes do
    attribute(:summary, :text)
    attribute(:unique_hash, :text, unique: true)
    attribute(:data, :villain)
  end
end

defmodule Brando.MigrationTest.Property do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "Property",
    singular: "property",
    plural: "properties"

  data_layer(:embedded)

  attributes do
    attribute(:key, :string)
    attribute(:value, :string)
  end
end

defmodule Brando.MigrationTest.Profile do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Persons",
    schema: "Person",
    singular: "profiles",
    plural: "profile"

  trait(Brando.Trait.Creator)
  trait(Brando.Trait.SoftDelete)
  trait(Brando.Trait.Sequenced)
  trait(Brando.Trait.Timestamped)

  primary_key(:uuid)

  attributes do
    attribute(:status, :string)
  end
end

defmodule Brando.MigrationTest.Person do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Persons",
    schema: "Person",
    singular: "person",
    plural: "persons"

  trait(Brando.Trait.Creator)
  trait(Brando.Trait.SoftDelete)
  trait(Brando.Trait.Sequenced)
  trait(Brando.Trait.Timestamped)
  trait(Brando.Trait.Translatable)

  primary_key(:uuid)

  attributes do
    attribute(:name, :string)
    attribute(:email, :string, required: true)
  end

  relations do
    relation(:profile, :belongs_to, module: Brando.MigrationTest.Profile, type: :binary_id)
  end
end
