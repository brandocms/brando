defmodule Brando.BlueprintTest.Project do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "Projects",
    schema: "Project",
    singular: "project",
    plural: "projects",
    gettext_module: Brando.Gettext

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
  @image_cdn_cfg [
    cdn: %{
      enabled: true,
      s3: :default,
      media_url: "https://mycustomcdn.com"
    },
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
      "xlarge" => %{"size" => "2800", "quality" => 65},
      "crop_xlarge" => %{"size" => "1000x500", "quality" => 65, "crop" => true}
    },
    srcset: %{
      default: [
        {"xlarge", "900w"}
      ],
      cropped: [
        {"crop_xlarge", "900w"}
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

  absolute_url {:i18n, :project_path, :show_fancy, [[:slug], [:creator, :slug], [:properties, :name]]}
  identifier "{{ entry.title }} [{{ entry.id }}]"

  trait Brando.Trait.Creator
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Status
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable

  attributes do
    attribute :title, :string
    attribute :slug, :slug, required: true
  end

  relations do
    relation :properties, :embeds_many, module: Brando.BlueprintTest.Property
  end

  assets do
    asset :cover, :image, cfg: @image_cfg
    asset :cover_cdn, :image, cfg: @image_cdn_cfg
    asset :pdf, :file, cfg: @file_cfg
  end

  listings do
    listing do
      query %{status: :published}
    end
  end

  forms do
    form do
      blocks :blocks

      tab "Content" do
        fieldset do
          size :half
          input :title, :text
          input :slug, :slug, from: :title
        end
      end

      tab "Properties" do
        fieldset do
          inputs_for :properties do
            cardinality :many
            style :inline
            default %{}

            input :key, :text, placeholder: "Key"
            input :value, :text, placeholder: "Val"
          end
        end
      end
    end

    form :extra do
      tab "Test" do
        fieldset do
          size :half
          input :title, :text
        end
      end
    end
  end
end

defmodule Brando.TraitTest.Project do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "TraitTest",
    schema: "Project",
    singular: "project",
    plural: "projects",
    gettext_module: Brando.Gettext

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
  trait Brando.Trait.Translatable
  trait Brando.Trait.Blocks

  attributes do
    attribute :title, :string, unique: true
  end

  assets do
    asset :cover, :image, cfg: @image_cfg
  end

  relations do
    relation :blocks, :has_many, module: :blocks
    relation :bio_blocks, :has_many, module: :blocks
  end
end

defmodule Brando.BlueprintTest.Property do
  @moduledoc false
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
