defmodule Brando.Images.Field.ImageFieldTest do
  use ExUnit.Case, async: true
  import Brando.Images.Utils

  defmodule TestModel do
    use Brando.Field.ImageField

    has_image_field :avatar,
      %{allowed_mimetypes: ["image/jpeg", "image/png"],
        default_size: :medium,
        upload_path: Path.join("images", "avatars"),
        random_filename: true,
        size_limit: 10240000,
        sizes: %{
          "micro"  => %{"size" => "25x25", "quality" => 100, "crop" => true},
          "thumb"  => %{"size" => "150x150", "quality" => 100, "crop" => true},
          "small"  => %{"size" => "300", "quality" => 100},
          "medium" => %{"size" => "500", "quality" => 100},
          "large"  => %{"size" => "700", "quality" => 100},
          "xlarge" => %{"size" => "900", "quality" => 100}
        }
      }
  end

  test "use works" do
    assert Brando.Images.Field.ImageFieldTest.TestModel.get_image_cfg(:avatar)
           == %{allowed_mimetypes: ["image/jpeg", "image/png"],
                default_size: :medium,
                upload_path: Path.join("images", "avatars"),
                random_filename: true, size_limit: 10240000,
                sizes: %{"micro" => %{"size" => "25x25",
                "quality" => 100, "crop" => true},
                "thumb"  => %{"size" => "150x150", "quality" => 100,
                "crop" => true},
                "small"  => %{"size" => "300", "quality" => 100},
                "medium" => %{"size" => "500", "quality" => 100},
                "large"  => %{"size" => "700", "quality" => 100},
                "xlarge" => %{"size" => "900", "quality" => 100}
        }
      }
  end
end
