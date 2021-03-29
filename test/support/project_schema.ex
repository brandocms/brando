defmodule Brando.BlueprintTest.Project do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "Project",
    singular: "project",
    plural: "projects"

  trait Brando.Trait.Creator
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Sequence
  trait Brando.Trait.Timestamps

  attributes do
    attribute :title, :string
    attribute :slug, :slug, from: :title, required: true

    attribute :cover, :image,
      allowed_mimetypes: [
        "image/jpeg",
        "image/png",
        "image/gif"
      ],
      default_size: "medium",
      upload_path: Path.join("images", "avatars"),
      random_filename: true,
      size_limit: 10_240_000,
      sizes: %{
        "micro" => %{"size" => "25", "quality" => 10, "crop" => false},
        "thumb" => %{"size" => "150x150", "quality" => 65, "crop" => true},
        "small" => %{"size" => "300x300", "quality" => 65, "crop" => true},
        "medium" => %{"size" => "500x500", "quality" => 65, "crop" => true},
        "large" => %{"size" => "700x700", "quality" => 65, "crop" => true},
        "xlarge" => %{"size" => "900x900", "quality" => 65, "crop" => true}
      },
      srcset: [
        {"small", "300w"},
        {"medium", "500w"},
        {"large", "700w"}
      ]
  end

  relations do
  end
end

defmodule Brando.TraitTest.Project do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "Project",
    singular: "project",
    plural: "projects"

  trait Brando.Trait.Creator
  trait Brando.Trait.Sequence
  trait Brando.Trait.Villain
  trait Brando.Trait.Translatable

  attributes do
    attribute :title, :string, unique: true
    attribute :data, :villain
    attribute :bio_data, :villain

    attribute :cover, :image,
      allowed_mimetypes: [
        "image/jpeg",
        "image/png",
        "image/gif"
      ],
      default_size: "medium",
      upload_path: Path.join("images", "avatars"),
      random_filename: true,
      size_limit: 10_240_000,
      sizes: %{
        "micro" => %{"size" => "25", "quality" => 10, "crop" => false},
        "thumb" => %{"size" => "150x150", "quality" => 65, "crop" => true},
        "small" => %{"size" => "300x300", "quality" => 65, "crop" => true},
        "medium" => %{"size" => "500x500", "quality" => 65, "crop" => true},
        "large" => %{"size" => "700x700", "quality" => 65, "crop" => true},
        "xlarge" => %{"size" => "900x900", "quality" => 65, "crop" => true}
      },
      srcset: [
        {"small", "300w"},
        {"medium", "500w"},
        {"large", "700w"}
      ]
  end
end
