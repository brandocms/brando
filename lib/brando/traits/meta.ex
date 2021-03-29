defmodule Brando.Trait.Meta do
  use Brando.Trait

  @meta_image_cfg [
    allowed_mimetypes: ["image/jpeg", "image/png"],
    default_size: "xlarge",
    upload_path: Path.join(["images", "meta"]),
    random_filename: true,
    size_limit: 5_240_000,
    sizes: %{
      "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
      "thumb" => %{"size" => "150x150>", "quality" => 75, "crop" => true},
      "xlarge" => %{"size" => "1200x630", "quality" => 75, "crop" => true}
    }
  ]

  attributes do
    attribute :meta_title, :text
    attribute :meta_description, :text
    attribute :meta_image, :image, @meta_image_cfg
  end
end
