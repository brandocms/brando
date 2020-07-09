defmodule Brando.OperationsTest do
  use ExUnit.Case
  import Brando.Images.Operations

  @img_struct %Brando.Type.Image{
    credits: nil,
    focal: %{"x" => 50, "y" => 50},
    height: 2600,
    path: "images/exhibitions/cover/image.jpeg",
    sizes: %{
      "large" => "images/exhibitions/cover/large/image.jpg",
      "medium" => "images/exhibitions/cover/medium/image.jpg",
      "micro" => "images/exhibitions/cover/micro/image.jpg",
      "small" => "images/exhibitions/cover/small/image.jpg",
      "thumb" => "images/exhibitions/cover/thumb/image.jpg",
      "xlarge" => "images/exhibitions/cover/xlarge/image.jpg"
    },
    title: nil,
    width: 2600
  }

  @img_config %Brando.Type.ImageConfig{
    allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
    default_size: "medium",
    upload_path: Path.join(["images", "exhibitions", "cover"]),
    random_filename: true,
    size_limit: 10_240_000,
    sizes: %{
      "micro" => %{"size" => "25x25>", "quality" => 30, "crop" => true},
      "thumb" => %{"size" => "150x150>", "quality" => 90, "crop" => true},
      "small" => %{"size" => "700", "quality" => 90},
      "medium" => %{"size" => "1100", "quality" => 90},
      "large" => %{"size" => "1700", "quality" => 90},
      "xlarge" => %{"size" => "2100", "quality" => 90}
    }
  }

  @img_config_png %Brando.Type.ImageConfig{
    allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
    default_size: "medium",
    upload_path: Path.join(["images", "exhibitions", "cover"]),
    random_filename: true,
    size_limit: 10_240_000,
    sizes: %{
      "micro" => %{"size" => "25x25>", "quality" => 30, "crop" => true},
      "thumb" => %{"size" => "150x150>", "quality" => 90, "crop" => true},
      "small" => %{"size" => "700", "quality" => 90},
      "medium" => %{"size" => "1100", "quality" => 90},
      "large" => %{"size" => "1700", "quality" => 90},
      "xlarge" => %{"size" => "2100", "quality" => 90}
    },
    target_format: :png
  }

  test "create operations from file" do
    {:ok, operations} =
      create_operations(
        @img_struct,
        @img_config,
        :system,
        "test_id"
      )

    assert operations == [
             %Brando.Images.Operation{
               filename: "image.jpeg",
               id: "test_id",
               img_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.jpeg",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.jpg",
                   "medium" => "images/exhibitions/cover/medium/image.jpg",
                   "micro" => "images/exhibitions/cover/micro/image.jpg",
                   "small" => "images/exhibitions/cover/small/image.jpg",
                   "thumb" => "images/exhibitions/cover/thumb/image.jpg",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.jpg"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"quality" => 90, "size" => "1700"},
               size_key: "large",
               type: :jpg,
               user: :system,
               sized_img_dir: "images/exhibitions/cover/large",
               sized_img_path: "images/exhibitions/cover/large/image.jpg",
               operation_index: 1,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               id: "test_id",
               img_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.jpeg",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.jpg",
                   "medium" => "images/exhibitions/cover/medium/image.jpg",
                   "micro" => "images/exhibitions/cover/micro/image.jpg",
                   "small" => "images/exhibitions/cover/small/image.jpg",
                   "thumb" => "images/exhibitions/cover/thumb/image.jpg",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.jpg"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"quality" => 90, "size" => "1100"},
               size_key: "medium",
               type: :jpg,
               user: :system,
               sized_img_dir: "images/exhibitions/cover/medium",
               sized_img_path: "images/exhibitions/cover/medium/image.jpg",
               operation_index: 2,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               id: "test_id",
               img_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.jpeg",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.jpg",
                   "medium" => "images/exhibitions/cover/medium/image.jpg",
                   "micro" => "images/exhibitions/cover/micro/image.jpg",
                   "small" => "images/exhibitions/cover/small/image.jpg",
                   "thumb" => "images/exhibitions/cover/thumb/image.jpg",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.jpg"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"crop" => true, "quality" => 30, "size" => "25x25>"},
               size_key: "micro",
               type: :jpg,
               user: :system,
               sized_img_dir: "images/exhibitions/cover/micro",
               sized_img_path: "images/exhibitions/cover/micro/image.jpg",
               operation_index: 3,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               id: "test_id",
               img_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.jpeg",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.jpg",
                   "medium" => "images/exhibitions/cover/medium/image.jpg",
                   "micro" => "images/exhibitions/cover/micro/image.jpg",
                   "small" => "images/exhibitions/cover/small/image.jpg",
                   "thumb" => "images/exhibitions/cover/thumb/image.jpg",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.jpg"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"quality" => 90, "size" => "700"},
               size_key: "small",
               type: :jpg,
               user: :system,
               sized_img_dir: "images/exhibitions/cover/small",
               sized_img_path: "images/exhibitions/cover/small/image.jpg",
               operation_index: 4,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               id: "test_id",
               img_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.jpeg",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.jpg",
                   "medium" => "images/exhibitions/cover/medium/image.jpg",
                   "micro" => "images/exhibitions/cover/micro/image.jpg",
                   "small" => "images/exhibitions/cover/small/image.jpg",
                   "thumb" => "images/exhibitions/cover/thumb/image.jpg",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.jpg"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"crop" => true, "quality" => 90, "size" => "150x150>"},
               size_key: "thumb",
               type: :jpg,
               user: :system,
               sized_img_dir: "images/exhibitions/cover/thumb",
               sized_img_path: "images/exhibitions/cover/thumb/image.jpg",
               operation_index: 5,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               id: "test_id",
               img_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.jpeg",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.jpg",
                   "medium" => "images/exhibitions/cover/medium/image.jpg",
                   "micro" => "images/exhibitions/cover/micro/image.jpg",
                   "small" => "images/exhibitions/cover/small/image.jpg",
                   "thumb" => "images/exhibitions/cover/thumb/image.jpg",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.jpg"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"quality" => 90, "size" => "2100"},
               size_key: "xlarge",
               type: :jpg,
               user: :system,
               sized_img_dir: "images/exhibitions/cover/xlarge",
               sized_img_path: "images/exhibitions/cover/xlarge/image.jpg",
               operation_index: 6,
               total_operations: 6
             }
           ]
  end

  test "create png operations from file" do
    {:ok, operations} =
      create_operations(
        @img_struct,
        @img_config_png,
        :system,
        "test_id"
      )

    assert operations == [
             %Brando.Images.Operation{
               filename: "image.jpeg",
               id: "test_id",
               img_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.jpeg",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.jpg",
                   "medium" => "images/exhibitions/cover/medium/image.jpg",
                   "micro" => "images/exhibitions/cover/micro/image.jpg",
                   "small" => "images/exhibitions/cover/small/image.jpg",
                   "thumb" => "images/exhibitions/cover/thumb/image.jpg",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.jpg"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"quality" => 90, "size" => "1700"},
               size_key: "large",
               type: :png,
               user: :system,
               sized_img_dir: "images/exhibitions/cover/large",
               sized_img_path: "images/exhibitions/cover/large/image.png",
               operation_index: 1,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               id: "test_id",
               img_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.jpeg",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.jpg",
                   "medium" => "images/exhibitions/cover/medium/image.jpg",
                   "micro" => "images/exhibitions/cover/micro/image.jpg",
                   "small" => "images/exhibitions/cover/small/image.jpg",
                   "thumb" => "images/exhibitions/cover/thumb/image.jpg",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.jpg"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"quality" => 90, "size" => "1100"},
               size_key: "medium",
               type: :png,
               user: :system,
               sized_img_dir: "images/exhibitions/cover/medium",
               sized_img_path: "images/exhibitions/cover/medium/image.png",
               operation_index: 2,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               id: "test_id",
               img_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.jpeg",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.jpg",
                   "medium" => "images/exhibitions/cover/medium/image.jpg",
                   "micro" => "images/exhibitions/cover/micro/image.jpg",
                   "small" => "images/exhibitions/cover/small/image.jpg",
                   "thumb" => "images/exhibitions/cover/thumb/image.jpg",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.jpg"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"crop" => true, "quality" => 30, "size" => "25x25>"},
               size_key: "micro",
               type: :png,
               user: :system,
               sized_img_dir: "images/exhibitions/cover/micro",
               sized_img_path: "images/exhibitions/cover/micro/image.png",
               operation_index: 3,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               id: "test_id",
               img_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.jpeg",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.jpg",
                   "medium" => "images/exhibitions/cover/medium/image.jpg",
                   "micro" => "images/exhibitions/cover/micro/image.jpg",
                   "small" => "images/exhibitions/cover/small/image.jpg",
                   "thumb" => "images/exhibitions/cover/thumb/image.jpg",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.jpg"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"quality" => 90, "size" => "700"},
               size_key: "small",
               type: :png,
               user: :system,
               sized_img_dir: "images/exhibitions/cover/small",
               sized_img_path: "images/exhibitions/cover/small/image.png",
               operation_index: 4,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               id: "test_id",
               img_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.jpeg",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.jpg",
                   "medium" => "images/exhibitions/cover/medium/image.jpg",
                   "micro" => "images/exhibitions/cover/micro/image.jpg",
                   "small" => "images/exhibitions/cover/small/image.jpg",
                   "thumb" => "images/exhibitions/cover/thumb/image.jpg",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.jpg"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"crop" => true, "quality" => 90, "size" => "150x150>"},
               size_key: "thumb",
               type: :png,
               user: :system,
               sized_img_dir: "images/exhibitions/cover/thumb",
               sized_img_path: "images/exhibitions/cover/thumb/image.png",
               operation_index: 5,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               id: "test_id",
               img_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.jpeg",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.jpg",
                   "medium" => "images/exhibitions/cover/medium/image.jpg",
                   "micro" => "images/exhibitions/cover/micro/image.jpg",
                   "small" => "images/exhibitions/cover/small/image.jpg",
                   "thumb" => "images/exhibitions/cover/thumb/image.jpg",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.jpg"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"quality" => 90, "size" => "2100"},
               size_key: "xlarge",
               type: :png,
               user: :system,
               sized_img_dir: "images/exhibitions/cover/xlarge",
               sized_img_path: "images/exhibitions/cover/xlarge/image.png",
               operation_index: 6,
               total_operations: 6
             }
           ]
  end
end
