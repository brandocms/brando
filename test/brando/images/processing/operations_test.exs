defmodule Brando.OperationsTest do
  use ExUnit.Case
  import Brando.Images.Operations

  @image_struct %Brando.Type.Image{
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

  @image_struct_png %Brando.Type.Image{
    credits: nil,
    focal: %{"x" => 50, "y" => 50},
    height: 2600,
    path: "images/exhibitions/cover/image.png",
    sizes: %{
      "large" => "images/exhibitions/cover/large/image.png",
      "medium" => "images/exhibitions/cover/medium/image.png",
      "micro" => "images/exhibitions/cover/micro/image.png",
      "small" => "images/exhibitions/cover/small/image.png",
      "thumb" => "images/exhibitions/cover/thumb/image.png",
      "xlarge" => "images/exhibitions/cover/xlarge/image.png"
    },
    title: nil,
    width: 2600
  }

  @image_struct_gif %Brando.Type.Image{
    credits: nil,
    focal: %{"x" => 50, "y" => 50},
    height: 2600,
    path: "images/exhibitions/cover/image.gif",
    sizes: %{
      "large" => "images/exhibitions/cover/large/image.gif",
      "medium" => "images/exhibitions/cover/medium/image.gif",
      "micro" => "images/exhibitions/cover/micro/image.gif",
      "small" => "images/exhibitions/cover/small/image.gif",
      "thumb" => "images/exhibitions/cover/thumb/image.gif",
      "xlarge" => "images/exhibitions/cover/xlarge/image.gif"
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

  @img_config_gif %Brando.Type.ImageConfig{
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
    target_format: :gif
  }

  test "create operations from file" do
    {:ok, operations} =
      create(
        @image_struct,
        @img_config,
        "test_id",
        :system
      )

    assert operations == [
             %Brando.Images.Operation{
               filename: "image.jpeg",
               id: "test_id",
               image_struct: %Brando.Type.Image{
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
               sized_image_dir: "images/exhibitions/cover/large",
               sized_image_path: "images/exhibitions/cover/large/image.jpg",
               operation_index: 1,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               id: "test_id",
               image_struct: %Brando.Type.Image{
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
               sized_image_dir: "images/exhibitions/cover/medium",
               sized_image_path: "images/exhibitions/cover/medium/image.jpg",
               operation_index: 2,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               id: "test_id",
               image_struct: %Brando.Type.Image{
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
               sized_image_dir: "images/exhibitions/cover/micro",
               sized_image_path: "images/exhibitions/cover/micro/image.jpg",
               operation_index: 3,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               id: "test_id",
               image_struct: %Brando.Type.Image{
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
               sized_image_dir: "images/exhibitions/cover/small",
               sized_image_path: "images/exhibitions/cover/small/image.jpg",
               operation_index: 4,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               id: "test_id",
               image_struct: %Brando.Type.Image{
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
               sized_image_dir: "images/exhibitions/cover/thumb",
               sized_image_path: "images/exhibitions/cover/thumb/image.jpg",
               operation_index: 5,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               id: "test_id",
               image_struct: %Brando.Type.Image{
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
               sized_image_dir: "images/exhibitions/cover/xlarge",
               sized_image_path: "images/exhibitions/cover/xlarge/image.jpg",
               operation_index: 6,
               total_operations: 6
             }
           ]
  end

  test "create png operations from file" do
    {:ok, operations} =
      create(
        @image_struct_png,
        @img_config_png,
        "test_id",
        :system
      )

    assert operations == [
             %Brando.Images.Operation{
               filename: "image.png",
               id: "test_id",
               image_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.png",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.png",
                   "medium" => "images/exhibitions/cover/medium/image.png",
                   "micro" => "images/exhibitions/cover/micro/image.png",
                   "small" => "images/exhibitions/cover/small/image.png",
                   "thumb" => "images/exhibitions/cover/thumb/image.png",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.png"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"quality" => 90, "size" => "1700"},
               size_key: "large",
               type: :png,
               user: :system,
               sized_image_dir: "images/exhibitions/cover/large",
               sized_image_path: "images/exhibitions/cover/large/image.png",
               operation_index: 1,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.png",
               id: "test_id",
               image_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.png",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.png",
                   "medium" => "images/exhibitions/cover/medium/image.png",
                   "micro" => "images/exhibitions/cover/micro/image.png",
                   "small" => "images/exhibitions/cover/small/image.png",
                   "thumb" => "images/exhibitions/cover/thumb/image.png",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.png"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"quality" => 90, "size" => "1100"},
               size_key: "medium",
               type: :png,
               user: :system,
               sized_image_dir: "images/exhibitions/cover/medium",
               sized_image_path: "images/exhibitions/cover/medium/image.png",
               operation_index: 2,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.png",
               id: "test_id",
               image_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.png",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.png",
                   "medium" => "images/exhibitions/cover/medium/image.png",
                   "micro" => "images/exhibitions/cover/micro/image.png",
                   "small" => "images/exhibitions/cover/small/image.png",
                   "thumb" => "images/exhibitions/cover/thumb/image.png",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.png"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"crop" => true, "quality" => 30, "size" => "25x25>"},
               size_key: "micro",
               type: :png,
               user: :system,
               sized_image_dir: "images/exhibitions/cover/micro",
               sized_image_path: "images/exhibitions/cover/micro/image.png",
               operation_index: 3,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.png",
               id: "test_id",
               image_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.png",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.png",
                   "medium" => "images/exhibitions/cover/medium/image.png",
                   "micro" => "images/exhibitions/cover/micro/image.png",
                   "small" => "images/exhibitions/cover/small/image.png",
                   "thumb" => "images/exhibitions/cover/thumb/image.png",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.png"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"quality" => 90, "size" => "700"},
               size_key: "small",
               type: :png,
               user: :system,
               sized_image_dir: "images/exhibitions/cover/small",
               sized_image_path: "images/exhibitions/cover/small/image.png",
               operation_index: 4,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.png",
               id: "test_id",
               image_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.png",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.png",
                   "medium" => "images/exhibitions/cover/medium/image.png",
                   "micro" => "images/exhibitions/cover/micro/image.png",
                   "small" => "images/exhibitions/cover/small/image.png",
                   "thumb" => "images/exhibitions/cover/thumb/image.png",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.png"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"crop" => true, "quality" => 90, "size" => "150x150>"},
               size_key: "thumb",
               type: :png,
               user: :system,
               sized_image_dir: "images/exhibitions/cover/thumb",
               sized_image_path: "images/exhibitions/cover/thumb/image.png",
               operation_index: 5,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.png",
               id: "test_id",
               image_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.png",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.png",
                   "medium" => "images/exhibitions/cover/medium/image.png",
                   "micro" => "images/exhibitions/cover/micro/image.png",
                   "small" => "images/exhibitions/cover/small/image.png",
                   "thumb" => "images/exhibitions/cover/thumb/image.png",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.png"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"quality" => 90, "size" => "2100"},
               size_key: "xlarge",
               type: :png,
               user: :system,
               sized_image_dir: "images/exhibitions/cover/xlarge",
               sized_image_path: "images/exhibitions/cover/xlarge/image.png",
               operation_index: 6,
               total_operations: 6
             }
           ]
  end

  test "create gif operations from file" do
    {:ok, operations} =
      create(
        @image_struct_gif,
        @img_config_gif,
        "test_id",
        :system
      )

    assert operations == [
             %Brando.Images.Operation{
               filename: "image.gif",
               id: "test_id",
               image_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.gif",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.gif",
                   "medium" => "images/exhibitions/cover/medium/image.gif",
                   "micro" => "images/exhibitions/cover/micro/image.gif",
                   "small" => "images/exhibitions/cover/small/image.gif",
                   "thumb" => "images/exhibitions/cover/thumb/image.gif",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.gif"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"quality" => 90, "size" => "1700"},
               size_key: "large",
               type: :gif,
               user: :system,
               sized_image_dir: "images/exhibitions/cover/large",
               sized_image_path: "images/exhibitions/cover/large/image.gif",
               operation_index: 1,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.gif",
               id: "test_id",
               image_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.gif",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.gif",
                   "medium" => "images/exhibitions/cover/medium/image.gif",
                   "micro" => "images/exhibitions/cover/micro/image.gif",
                   "small" => "images/exhibitions/cover/small/image.gif",
                   "thumb" => "images/exhibitions/cover/thumb/image.gif",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.gif"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"quality" => 90, "size" => "1100"},
               size_key: "medium",
               type: :gif,
               user: :system,
               sized_image_dir: "images/exhibitions/cover/medium",
               sized_image_path: "images/exhibitions/cover/medium/image.gif",
               operation_index: 2,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.gif",
               id: "test_id",
               image_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.gif",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.gif",
                   "medium" => "images/exhibitions/cover/medium/image.gif",
                   "micro" => "images/exhibitions/cover/micro/image.gif",
                   "small" => "images/exhibitions/cover/small/image.gif",
                   "thumb" => "images/exhibitions/cover/thumb/image.gif",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.gif"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"crop" => true, "quality" => 30, "size" => "25x25>"},
               size_key: "micro",
               type: :gif,
               user: :system,
               sized_image_dir: "images/exhibitions/cover/micro",
               sized_image_path: "images/exhibitions/cover/micro/image.gif",
               operation_index: 3,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.gif",
               id: "test_id",
               image_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.gif",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.gif",
                   "medium" => "images/exhibitions/cover/medium/image.gif",
                   "micro" => "images/exhibitions/cover/micro/image.gif",
                   "small" => "images/exhibitions/cover/small/image.gif",
                   "thumb" => "images/exhibitions/cover/thumb/image.gif",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.gif"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"quality" => 90, "size" => "700"},
               size_key: "small",
               type: :gif,
               user: :system,
               sized_image_dir: "images/exhibitions/cover/small",
               sized_image_path: "images/exhibitions/cover/small/image.gif",
               operation_index: 4,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.gif",
               id: "test_id",
               image_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.gif",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.gif",
                   "medium" => "images/exhibitions/cover/medium/image.gif",
                   "micro" => "images/exhibitions/cover/micro/image.gif",
                   "small" => "images/exhibitions/cover/small/image.gif",
                   "thumb" => "images/exhibitions/cover/thumb/image.gif",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.gif"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"crop" => true, "quality" => 90, "size" => "150x150>"},
               size_key: "thumb",
               type: :gif,
               user: :system,
               sized_image_dir: "images/exhibitions/cover/thumb",
               sized_image_path: "images/exhibitions/cover/thumb/image.gif",
               operation_index: 5,
               total_operations: 6
             },
             %Brando.Images.Operation{
               filename: "image.gif",
               id: "test_id",
               image_struct: %Brando.Type.Image{
                 credits: nil,
                 focal: %{"x" => 50, "y" => 50},
                 height: 2600,
                 path: "images/exhibitions/cover/image.gif",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.gif",
                   "medium" => "images/exhibitions/cover/medium/image.gif",
                   "micro" => "images/exhibitions/cover/micro/image.gif",
                   "small" => "images/exhibitions/cover/small/image.gif",
                   "thumb" => "images/exhibitions/cover/thumb/image.gif",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.gif"
                 },
                 title: nil,
                 width: 2600
               },
               size_cfg: %{"quality" => 90, "size" => "2100"},
               size_key: "xlarge",
               type: :gif,
               user: :system,
               sized_image_dir: "images/exhibitions/cover/xlarge",
               sized_image_path: "images/exhibitions/cover/xlarge/image.gif",
               operation_index: 6,
               total_operations: 6
             }
           ]
  end

  test "create_image_size gif" do
    op = %Brando.Images.Operation{
      filename: "image.gif",
      id: "test_id",
      image_struct: %Brando.Type.Image{
        credits: nil,
        focal: %{"x" => 50, "y" => 50},
        height: 2600,
        path: "images/exhibitions/cover/image.gif",
        sizes: %{
          "micro" => "images/exhibitions/cover/micro/image.gif"
        },
        title: nil,
        width: 2600
      },
      size_cfg: %{"quality" => 1, "size" => "10"},
      size_key: "micro",
      type: :gif,
      user: :system,
      sized_image_dir: "images/exhibitions/cover/micro",
      sized_image_path: "images/exhibitions/cover/micro/image.gif",
      operation_index: 6,
      total_operations: 6
    }

    {:ok, result} = Brando.Images.Operations.Sizing.create_image_size(op)
    assert result.cmd_params =~ "--resize-fit-width 10"
    assert result.size_key == "micro"
  end

  test "create_image_size cropped gif" do
    op = %Brando.Images.Operation{
      filename: "image.gif",
      id: "test_id",
      image_struct: %Brando.Type.Image{
        credits: nil,
        focal: %{"x" => 50, "y" => 50},
        height: 2600,
        path: "images/exhibitions/cover/image.gif",
        sizes: %{
          "micro" => "images/exhibitions/cover/micro/image.gif"
        },
        title: nil,
        width: 2600
      },
      size_cfg: %{"quality" => 1, "size" => "10x10", "crop" => true},
      size_key: "micro",
      type: :gif,
      user: :system,
      sized_image_dir: "images/exhibitions/cover/micro",
      sized_image_path: "images/exhibitions/cover/micro/image.gif",
      operation_index: 6,
      total_operations: 6
    }

    {:ok, result} = Brando.Images.Operations.Sizing.create_image_size(op)
    assert result.cmd_params =~ "--crop 0,0-10,10 --resize 10x10"
    assert result.size_key == "micro"
  end
end
