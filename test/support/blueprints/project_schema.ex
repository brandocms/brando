defmodule Brando.BlueprintTest.Project do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "Project",
    singular: "project",
    plural: "projects"

  @image_cfg [
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
      "xlarge" => %{"size" => "900x900", "quality" => 65, "crop" => true},
      "crop_small" => %{"size" => "300x300", "quality" => 65, "crop" => true},
      "crop_medium" => %{"size" => "500x500", "quality" => 65, "crop" => true}
    },
    srcset: %{
      default: [
        {"small", "300w"},
        {"medium", "500w"},
        {"large", "700w"},
        {"xlarge", "900w"}
      ],
      cropped: [
        {"crop_small", "300w"},
        {"crop_medium", "500w"}
      ]
    }
  ]

  @file_cfg %{
    allowed_mimetypes: ["application/pdf"],
    upload_path: Path.join("files", "projects"),
    random_filename: false,
    overwrite: false,
    size_limit: 10_240_000
  }

  trait Brando.Trait.Creator
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Timestamped

  attributes do
    attribute :title, :string
    attribute :slug, :slug, from: :title, required: true
  end

  relations do
    relation :properties, :embeds_many, module: Brando.BlueprintTest.Property
  end

  assets do
    asset :cover, :image, cfg: @image_cfg
    asset :pdf, :file, cfg: @file_cfg
  end

  listings do
    listing do
      listing_query %{status: :published}
    end
  end

  forms do
    form do
      tab "Content" do
        fieldset size: :half do
          input :title, :text
          input :slug, :slug, from: :title
        end
      end

      tab "Properties" do
        fieldset size: :full do
          inputs_for :properties,
            cardinality: :many,
            style: :inline,
            default: %{} do
            input :key, :text, placeholder: "Key"
            input :value, :text, placeholder: "Val"
          end

          input :data, :blocks
        end
      end
    end

    form :extra do
      tab "Test" do
        fieldset size: :half do
          input :title, :text
        end
      end
    end
  end
end

defmodule Brando.TraitTest.Project do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "Project",
    singular: "project",
    plural: "projects"

  @image_cfg [
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
  ]

  trait Brando.Trait.Creator
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Villain
  trait Brando.Trait.Translatable

  attributes do
    attribute :title, :string, unique: true
    attribute :data, :villain
    attribute :bio_data, :villain
  end

  assets do
    asset :cover, :image, cfg: @image_cfg
  end
end

defmodule Brando.BlueprintTest.Property do
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
