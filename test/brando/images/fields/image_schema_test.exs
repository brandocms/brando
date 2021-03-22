defmodule Brando.Field.Image.SchemaTest do
  use ExUnit.Case, async: true
  import Brando.Images.Utils

  defmodule TestSchema do
    use Brando.Field.Image.Schema

    @cfg %{
      allowed_mimetypes: ["image/jpeg", "image/png"],
      default_size: "medium",
      upload_path: Path.join("images", "avatars"),
      random_filename: true,
      size_limit: 10_240_000,
      sizes: %{
        "micro" => %{"size" => "25x25", "quality" => 100, "crop" => true},
        "thumb" => %{"size" => "150x150", "quality" => 100, "crop" => true},
        "small" => %{"size" => "300", "quality" => 100},
        "medium" => %{"size" => "500", "quality" => 100},
        "large" => %{"size" => "700", "quality" => 100},
        "xlarge" => %{"size" => "900", "quality" => 100}
      }
    }

    has_image_field(:avatar, @cfg)

    def cfg, do: struct!(Brando.Type.ImageConfig, @cfg)
  end

  test "use works" do
    assert Brando.Field.Image.SchemaTest.TestSchema.get_image_cfg(:avatar) ==
             {:ok, TestSchema.cfg()}
  end
end
