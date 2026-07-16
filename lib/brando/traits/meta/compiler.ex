defmodule Brando.Trait.Meta.Compiler do
  @moduledoc false

  @doc false
  def generate_code(_module, _config) do
    quote do
      attributes do
        attribute :meta_title, :text
        attribute :meta_description, :text
      end

      assets do
        asset :meta_image, :image,
          cfg: %{
            formats: [:jpg],
            allowed_mimetypes: ["image/jpeg", "image/png"],
            default_size: "xlarge",
            upload_path: Path.join(["images", "meta"]),
            random_filename: true,
            size_limit: 5_240_000,
            sizes: %{
              "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
              "thumb" => %{"size" => "400x400>", "quality" => 75, "crop" => true},
              "xlarge" => %{"size" => "2400x1260", "quality" => 75, "crop" => true}
            }
          }
      end
    end
  end
end
