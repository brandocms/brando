defmodule Brando.OperationsTest do
  use ExUnit.Case
  import Brando.Images.Operations

  @image_struct %Brando.Images.Image{
    id: 1,
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
    status: :unprocessed,
    width: 2600
  }

  @image_struct_png %Brando.Images.Image{
    id: 2,
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
    status: :unprocessed,
    width: 2600
  }

  @image_struct_gif %Brando.Images.Image{
    id: 3,
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
    status: :unprocessed,
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
      "thumb" => %{"size" => "400x400>", "quality" => 90, "crop" => true},
      "small" => %{"size" => "700", "quality" => 90},
      "medium" => %{"size" => "1100", "quality" => 90},
      "large" => %{"size" => "1700", "quality" => 90},
      "xlarge" => %{"size" => "2100", "quality" => 90}
    }
  }

  @img_config_png %Brando.Type.ImageConfig{
    allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
    default_size: "medium",
    formats: [:png],
    upload_path: Path.join(["images", "exhibitions", "cover"]),
    random_filename: true,
    size_limit: 10_240_000,
    sizes: %{
      "micro" => %{"size" => "25x25>", "quality" => 30, "crop" => true},
      "thumb" => %{"size" => "400x400>", "quality" => 90, "crop" => true},
      "small" => %{"size" => "700", "quality" => 90},
      "medium" => %{"size" => "1100", "quality" => 90},
      "large" => %{"size" => "1700", "quality" => 90},
      "xlarge" => %{"size" => "2100", "quality" => 90}
    }
  }

  @img_config_gif %Brando.Type.ImageConfig{
    allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
    default_size: "medium",
    upload_path: Path.join(["images", "exhibitions", "cover"]),
    random_filename: true,
    size_limit: 10_240_000,
    sizes: %{
      "micro" => %{"size" => "25x25>", "quality" => 30, "crop" => true},
      "thumb" => %{"size" => "400x400>", "quality" => 90, "crop" => true},
      "small" => %{"size" => "700", "quality" => 90},
      "medium" => %{"size" => "1100", "quality" => 90},
      "large" => %{"size" => "1700", "quality" => 90},
      "xlarge" => %{"size" => "2100", "quality" => 90}
    },
    formats: [:gif]
  }

  test "create operations from file" do
    {:ok, operations} =
      create(
        @image_struct,
        @img_config,
        :system
      )

    assert operations == [
             %Brando.Images.Operation{
               filename: "image.jpeg",
               image_id: 1,
               image_struct: %Brando.Images.Image{
                 alt: nil,
                 cdn: false,
                 config_target: nil,
                 creator_id: nil,
                 credits: nil,
                 deleted_at: nil,
                 dominant_color: nil,
                 focal: %{"x" => 50, "y" => 50},
                 formats: nil,
                 height: 2600,
                 id: 1,
                 inserted_at: nil,
                 path: "images/exhibitions/cover/image.jpeg",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.jpg",
                   "medium" => "images/exhibitions/cover/medium/image.jpg",
                   "micro" => "images/exhibitions/cover/micro/image.jpg",
                   "small" => "images/exhibitions/cover/small/image.jpg",
                   "thumb" => "images/exhibitions/cover/thumb/image.jpg",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.jpg"
                 },
                 status: :unprocessed,
                 title: nil,
                 updated_at: nil,
                 width: 2600
               },
               operation_index: 1,
               processed_formats: [:jpg],
               size_cfg: %{"quality" => 90, "size" => "1700"},
               size_key: "large",
               sized_image_dir: "images/exhibitions/cover/large",
               sized_image_path: "images/exhibitions/cover/large/image.jpg",
               total_operations: 6,
               type: :jpg,
               user_id: :system
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               image_id: 1,
               image_struct: %Brando.Images.Image{
                 alt: nil,
                 cdn: false,
                 config_target: nil,
                 creator_id: nil,
                 credits: nil,
                 deleted_at: nil,
                 dominant_color: nil,
                 focal: %{"x" => 50, "y" => 50},
                 formats: nil,
                 height: 2600,
                 id: 1,
                 inserted_at: nil,
                 path: "images/exhibitions/cover/image.jpeg",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.jpg",
                   "medium" => "images/exhibitions/cover/medium/image.jpg",
                   "micro" => "images/exhibitions/cover/micro/image.jpg",
                   "small" => "images/exhibitions/cover/small/image.jpg",
                   "thumb" => "images/exhibitions/cover/thumb/image.jpg",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.jpg"
                 },
                 status: :unprocessed,
                 title: nil,
                 updated_at: nil,
                 width: 2600
               },
               operation_index: 2,
               processed_formats: [:jpg],
               size_cfg: %{"quality" => 90, "size" => "1100"},
               size_key: "medium",
               sized_image_dir: "images/exhibitions/cover/medium",
               sized_image_path: "images/exhibitions/cover/medium/image.jpg",
               total_operations: 6,
               type: :jpg,
               user_id: :system
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               image_id: 1,
               image_struct: %Brando.Images.Image{
                 alt: nil,
                 cdn: false,
                 config_target: nil,
                 creator_id: nil,
                 credits: nil,
                 deleted_at: nil,
                 dominant_color: nil,
                 focal: %{"x" => 50, "y" => 50},
                 formats: nil,
                 height: 2600,
                 id: 1,
                 inserted_at: nil,
                 path: "images/exhibitions/cover/image.jpeg",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.jpg",
                   "medium" => "images/exhibitions/cover/medium/image.jpg",
                   "micro" => "images/exhibitions/cover/micro/image.jpg",
                   "small" => "images/exhibitions/cover/small/image.jpg",
                   "thumb" => "images/exhibitions/cover/thumb/image.jpg",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.jpg"
                 },
                 status: :unprocessed,
                 title: nil,
                 updated_at: nil,
                 width: 2600
               },
               operation_index: 3,
               processed_formats: [:jpg],
               size_cfg: %{"crop" => true, "quality" => 30, "size" => "25x25>"},
               size_key: "micro",
               sized_image_dir: "images/exhibitions/cover/micro",
               sized_image_path: "images/exhibitions/cover/micro/image.jpg",
               total_operations: 6,
               type: :jpg,
               user_id: :system
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               image_id: 1,
               image_struct: %Brando.Images.Image{
                 alt: nil,
                 cdn: false,
                 config_target: nil,
                 creator_id: nil,
                 credits: nil,
                 deleted_at: nil,
                 dominant_color: nil,
                 focal: %{"x" => 50, "y" => 50},
                 formats: nil,
                 height: 2600,
                 id: 1,
                 inserted_at: nil,
                 path: "images/exhibitions/cover/image.jpeg",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.jpg",
                   "medium" => "images/exhibitions/cover/medium/image.jpg",
                   "micro" => "images/exhibitions/cover/micro/image.jpg",
                   "small" => "images/exhibitions/cover/small/image.jpg",
                   "thumb" => "images/exhibitions/cover/thumb/image.jpg",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.jpg"
                 },
                 status: :unprocessed,
                 title: nil,
                 updated_at: nil,
                 width: 2600
               },
               operation_index: 4,
               processed_formats: [:jpg],
               size_cfg: %{"quality" => 90, "size" => "700"},
               size_key: "small",
               sized_image_dir: "images/exhibitions/cover/small",
               sized_image_path: "images/exhibitions/cover/small/image.jpg",
               total_operations: 6,
               type: :jpg,
               user_id: :system
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               image_id: 1,
               image_struct: %Brando.Images.Image{
                 alt: nil,
                 cdn: false,
                 config_target: nil,
                 creator_id: nil,
                 credits: nil,
                 deleted_at: nil,
                 dominant_color: nil,
                 focal: %{"x" => 50, "y" => 50},
                 formats: nil,
                 height: 2600,
                 id: 1,
                 inserted_at: nil,
                 path: "images/exhibitions/cover/image.jpeg",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.jpg",
                   "medium" => "images/exhibitions/cover/medium/image.jpg",
                   "micro" => "images/exhibitions/cover/micro/image.jpg",
                   "small" => "images/exhibitions/cover/small/image.jpg",
                   "thumb" => "images/exhibitions/cover/thumb/image.jpg",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.jpg"
                 },
                 status: :unprocessed,
                 title: nil,
                 updated_at: nil,
                 width: 2600
               },
               operation_index: 5,
               processed_formats: [:jpg],
               size_cfg: %{"crop" => true, "quality" => 90, "size" => "400x400>"},
               size_key: "thumb",
               sized_image_dir: "images/exhibitions/cover/thumb",
               sized_image_path: "images/exhibitions/cover/thumb/image.jpg",
               total_operations: 6,
               type: :jpg,
               user_id: :system
             },
             %Brando.Images.Operation{
               filename: "image.jpeg",
               image_id: 1,
               image_struct: %Brando.Images.Image{
                 alt: nil,
                 cdn: false,
                 config_target: nil,
                 creator_id: nil,
                 credits: nil,
                 deleted_at: nil,
                 dominant_color: nil,
                 focal: %{"x" => 50, "y" => 50},
                 formats: nil,
                 height: 2600,
                 id: 1,
                 inserted_at: nil,
                 path: "images/exhibitions/cover/image.jpeg",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.jpg",
                   "medium" => "images/exhibitions/cover/medium/image.jpg",
                   "micro" => "images/exhibitions/cover/micro/image.jpg",
                   "small" => "images/exhibitions/cover/small/image.jpg",
                   "thumb" => "images/exhibitions/cover/thumb/image.jpg",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.jpg"
                 },
                 status: :unprocessed,
                 title: nil,
                 updated_at: nil,
                 width: 2600
               },
               operation_index: 6,
               processed_formats: [:jpg],
               size_cfg: %{"quality" => 90, "size" => "2100"},
               size_key: "xlarge",
               sized_image_dir: "images/exhibitions/cover/xlarge",
               sized_image_path: "images/exhibitions/cover/xlarge/image.jpg",
               total_operations: 6,
               type: :jpg,
               user_id: :system
             }
           ]
  end

  test "create png operations from file" do
    {:ok, operations} =
      create(
        @image_struct_png,
        @img_config_png,
        :system
      )

    assert operations == [
             %Brando.Images.Operation{
               filename: "image.png",
               image_id: 2,
               image_struct: %Brando.Images.Image{
                 alt: nil,
                 cdn: false,
                 config_target: nil,
                 creator_id: nil,
                 credits: nil,
                 deleted_at: nil,
                 dominant_color: nil,
                 focal: %{"x" => 50, "y" => 50},
                 formats: nil,
                 height: 2600,
                 id: 2,
                 inserted_at: nil,
                 path: "images/exhibitions/cover/image.png",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.png",
                   "medium" => "images/exhibitions/cover/medium/image.png",
                   "micro" => "images/exhibitions/cover/micro/image.png",
                   "small" => "images/exhibitions/cover/small/image.png",
                   "thumb" => "images/exhibitions/cover/thumb/image.png",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.png"
                 },
                 status: :unprocessed,
                 title: nil,
                 updated_at: nil,
                 width: 2600
               },
               operation_index: 1,
               processed_formats: [:png],
               size_cfg: %{"quality" => 90, "size" => "1700"},
               size_key: "large",
               sized_image_dir: "images/exhibitions/cover/large",
               sized_image_path: "images/exhibitions/cover/large/image.png",
               total_operations: 6,
               type: :png,
               user: :system
             },
             %Brando.Images.Operation{
               filename: "image.png",
               image_id: 2,
               image_struct: %Brando.Images.Image{
                 alt: nil,
                 cdn: false,
                 config_target: nil,
                 creator_id: nil,
                 credits: nil,
                 deleted_at: nil,
                 dominant_color: nil,
                 focal: %{"x" => 50, "y" => 50},
                 formats: nil,
                 height: 2600,
                 id: 2,
                 inserted_at: nil,
                 path: "images/exhibitions/cover/image.png",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.png",
                   "medium" => "images/exhibitions/cover/medium/image.png",
                   "micro" => "images/exhibitions/cover/micro/image.png",
                   "small" => "images/exhibitions/cover/small/image.png",
                   "thumb" => "images/exhibitions/cover/thumb/image.png",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.png"
                 },
                 status: :unprocessed,
                 title: nil,
                 updated_at: nil,
                 width: 2600
               },
               operation_index: 2,
               processed_formats: [:png],
               size_cfg: %{"quality" => 90, "size" => "1100"},
               size_key: "medium",
               sized_image_dir: "images/exhibitions/cover/medium",
               sized_image_path: "images/exhibitions/cover/medium/image.png",
               total_operations: 6,
               type: :png,
               user: :system
             },
             %Brando.Images.Operation{
               filename: "image.png",
               image_id: 2,
               image_struct: %Brando.Images.Image{
                 alt: nil,
                 cdn: false,
                 config_target: nil,
                 creator_id: nil,
                 credits: nil,
                 deleted_at: nil,
                 dominant_color: nil,
                 focal: %{"x" => 50, "y" => 50},
                 formats: nil,
                 height: 2600,
                 id: 2,
                 inserted_at: nil,
                 path: "images/exhibitions/cover/image.png",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.png",
                   "medium" => "images/exhibitions/cover/medium/image.png",
                   "micro" => "images/exhibitions/cover/micro/image.png",
                   "small" => "images/exhibitions/cover/small/image.png",
                   "thumb" => "images/exhibitions/cover/thumb/image.png",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.png"
                 },
                 status: :unprocessed,
                 title: nil,
                 updated_at: nil,
                 width: 2600
               },
               operation_index: 3,
               processed_formats: [:png],
               size_cfg: %{"crop" => true, "quality" => 30, "size" => "25x25>"},
               size_key: "micro",
               sized_image_dir: "images/exhibitions/cover/micro",
               sized_image_path: "images/exhibitions/cover/micro/image.png",
               total_operations: 6,
               type: :png,
               user: :system
             },
             %Brando.Images.Operation{
               filename: "image.png",
               image_id: 2,
               image_struct: %Brando.Images.Image{
                 alt: nil,
                 cdn: false,
                 config_target: nil,
                 creator_id: nil,
                 credits: nil,
                 deleted_at: nil,
                 dominant_color: nil,
                 focal: %{"x" => 50, "y" => 50},
                 formats: nil,
                 height: 2600,
                 id: 2,
                 inserted_at: nil,
                 path: "images/exhibitions/cover/image.png",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.png",
                   "medium" => "images/exhibitions/cover/medium/image.png",
                   "micro" => "images/exhibitions/cover/micro/image.png",
                   "small" => "images/exhibitions/cover/small/image.png",
                   "thumb" => "images/exhibitions/cover/thumb/image.png",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.png"
                 },
                 status: :unprocessed,
                 title: nil,
                 updated_at: nil,
                 width: 2600
               },
               operation_index: 4,
               processed_formats: [:png],
               size_cfg: %{"quality" => 90, "size" => "700"},
               size_key: "small",
               sized_image_dir: "images/exhibitions/cover/small",
               sized_image_path: "images/exhibitions/cover/small/image.png",
               total_operations: 6,
               type: :png,
               user: :system
             },
             %Brando.Images.Operation{
               filename: "image.png",
               image_id: 2,
               image_struct: %Brando.Images.Image{
                 alt: nil,
                 cdn: false,
                 config_target: nil,
                 creator_id: nil,
                 credits: nil,
                 deleted_at: nil,
                 dominant_color: nil,
                 focal: %{"x" => 50, "y" => 50},
                 formats: nil,
                 height: 2600,
                 id: 2,
                 inserted_at: nil,
                 path: "images/exhibitions/cover/image.png",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.png",
                   "medium" => "images/exhibitions/cover/medium/image.png",
                   "micro" => "images/exhibitions/cover/micro/image.png",
                   "small" => "images/exhibitions/cover/small/image.png",
                   "thumb" => "images/exhibitions/cover/thumb/image.png",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.png"
                 },
                 status: :unprocessed,
                 title: nil,
                 updated_at: nil,
                 width: 2600
               },
               operation_index: 5,
               processed_formats: [:png],
               size_cfg: %{"crop" => true, "quality" => 90, "size" => "400x400>"},
               size_key: "thumb",
               sized_image_dir: "images/exhibitions/cover/thumb",
               sized_image_path: "images/exhibitions/cover/thumb/image.png",
               total_operations: 6,
               type: :png,
               user: :system
             },
             %Brando.Images.Operation{
               filename: "image.png",
               image_id: 2,
               image_struct: %Brando.Images.Image{
                 alt: nil,
                 cdn: false,
                 config_target: nil,
                 creator_id: nil,
                 credits: nil,
                 deleted_at: nil,
                 dominant_color: nil,
                 focal: %{"x" => 50, "y" => 50},
                 formats: nil,
                 height: 2600,
                 id: 2,
                 inserted_at: nil,
                 path: "images/exhibitions/cover/image.png",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.png",
                   "medium" => "images/exhibitions/cover/medium/image.png",
                   "micro" => "images/exhibitions/cover/micro/image.png",
                   "small" => "images/exhibitions/cover/small/image.png",
                   "thumb" => "images/exhibitions/cover/thumb/image.png",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.png"
                 },
                 status: :unprocessed,
                 title: nil,
                 updated_at: nil,
                 width: 2600
               },
               operation_index: 6,
               processed_formats: [:png],
               size_cfg: %{"quality" => 90, "size" => "2100"},
               size_key: "xlarge",
               sized_image_dir: "images/exhibitions/cover/xlarge",
               sized_image_path: "images/exhibitions/cover/xlarge/image.png",
               total_operations: 6,
               type: :png,
               user: :system
             }
           ]
  end

  test "create gif operations from file" do
    {:ok, operations} =
      create(
        @image_struct_gif,
        @img_config_gif,
        :system
      )

    assert operations == [
             %Brando.Images.Operation{
               filename: "image.gif",
               image_id: 3,
               image_struct: %Brando.Images.Image{
                 alt: nil,
                 cdn: false,
                 config_target: nil,
                 creator_id: nil,
                 credits: nil,
                 deleted_at: nil,
                 dominant_color: nil,
                 focal: %{"x" => 50, "y" => 50},
                 formats: nil,
                 height: 2600,
                 id: 3,
                 inserted_at: nil,
                 path: "images/exhibitions/cover/image.gif",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.gif",
                   "medium" => "images/exhibitions/cover/medium/image.gif",
                   "micro" => "images/exhibitions/cover/micro/image.gif",
                   "small" => "images/exhibitions/cover/small/image.gif",
                   "thumb" => "images/exhibitions/cover/thumb/image.gif",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.gif"
                 },
                 status: :unprocessed,
                 title: nil,
                 updated_at: nil,
                 width: 2600
               },
               operation_index: 1,
               processed_formats: [:gif],
               size_cfg: %{"quality" => 90, "size" => "1700"},
               size_key: "large",
               sized_image_dir: "images/exhibitions/cover/large",
               sized_image_path: "images/exhibitions/cover/large/image.gif",
               total_operations: 6,
               type: :gif,
               user: :system
             },
             %Brando.Images.Operation{
               filename: "image.gif",
               image_id: 3,
               image_struct: %Brando.Images.Image{
                 alt: nil,
                 cdn: false,
                 config_target: nil,
                 creator_id: nil,
                 credits: nil,
                 deleted_at: nil,
                 dominant_color: nil,
                 focal: %{"x" => 50, "y" => 50},
                 formats: nil,
                 height: 2600,
                 id: 3,
                 inserted_at: nil,
                 path: "images/exhibitions/cover/image.gif",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.gif",
                   "medium" => "images/exhibitions/cover/medium/image.gif",
                   "micro" => "images/exhibitions/cover/micro/image.gif",
                   "small" => "images/exhibitions/cover/small/image.gif",
                   "thumb" => "images/exhibitions/cover/thumb/image.gif",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.gif"
                 },
                 status: :unprocessed,
                 title: nil,
                 updated_at: nil,
                 width: 2600
               },
               operation_index: 2,
               processed_formats: [:gif],
               size_cfg: %{"quality" => 90, "size" => "1100"},
               size_key: "medium",
               sized_image_dir: "images/exhibitions/cover/medium",
               sized_image_path: "images/exhibitions/cover/medium/image.gif",
               total_operations: 6,
               type: :gif,
               user: :system
             },
             %Brando.Images.Operation{
               filename: "image.gif",
               image_id: 3,
               image_struct: %Brando.Images.Image{
                 alt: nil,
                 cdn: false,
                 config_target: nil,
                 creator_id: nil,
                 credits: nil,
                 deleted_at: nil,
                 dominant_color: nil,
                 focal: %{"x" => 50, "y" => 50},
                 formats: nil,
                 height: 2600,
                 id: 3,
                 inserted_at: nil,
                 path: "images/exhibitions/cover/image.gif",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.gif",
                   "medium" => "images/exhibitions/cover/medium/image.gif",
                   "micro" => "images/exhibitions/cover/micro/image.gif",
                   "small" => "images/exhibitions/cover/small/image.gif",
                   "thumb" => "images/exhibitions/cover/thumb/image.gif",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.gif"
                 },
                 status: :unprocessed,
                 title: nil,
                 updated_at: nil,
                 width: 2600
               },
               operation_index: 3,
               processed_formats: [:gif],
               size_cfg: %{"crop" => true, "quality" => 30, "size" => "25x25>"},
               size_key: "micro",
               sized_image_dir: "images/exhibitions/cover/micro",
               sized_image_path: "images/exhibitions/cover/micro/image.gif",
               total_operations: 6,
               type: :gif,
               user: :system
             },
             %Brando.Images.Operation{
               filename: "image.gif",
               image_id: 3,
               image_struct: %Brando.Images.Image{
                 alt: nil,
                 cdn: false,
                 config_target: nil,
                 creator_id: nil,
                 credits: nil,
                 deleted_at: nil,
                 dominant_color: nil,
                 focal: %{"x" => 50, "y" => 50},
                 formats: nil,
                 height: 2600,
                 id: 3,
                 inserted_at: nil,
                 path: "images/exhibitions/cover/image.gif",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.gif",
                   "medium" => "images/exhibitions/cover/medium/image.gif",
                   "micro" => "images/exhibitions/cover/micro/image.gif",
                   "small" => "images/exhibitions/cover/small/image.gif",
                   "thumb" => "images/exhibitions/cover/thumb/image.gif",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.gif"
                 },
                 status: :unprocessed,
                 title: nil,
                 updated_at: nil,
                 width: 2600
               },
               operation_index: 4,
               processed_formats: [:gif],
               size_cfg: %{"quality" => 90, "size" => "700"},
               size_key: "small",
               sized_image_dir: "images/exhibitions/cover/small",
               sized_image_path: "images/exhibitions/cover/small/image.gif",
               total_operations: 6,
               type: :gif,
               user: :system
             },
             %Brando.Images.Operation{
               filename: "image.gif",
               image_id: 3,
               image_struct: %Brando.Images.Image{
                 alt: nil,
                 cdn: false,
                 config_target: nil,
                 creator_id: nil,
                 credits: nil,
                 deleted_at: nil,
                 dominant_color: nil,
                 focal: %{"x" => 50, "y" => 50},
                 formats: nil,
                 height: 2600,
                 id: 3,
                 inserted_at: nil,
                 path: "images/exhibitions/cover/image.gif",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.gif",
                   "medium" => "images/exhibitions/cover/medium/image.gif",
                   "micro" => "images/exhibitions/cover/micro/image.gif",
                   "small" => "images/exhibitions/cover/small/image.gif",
                   "thumb" => "images/exhibitions/cover/thumb/image.gif",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.gif"
                 },
                 status: :unprocessed,
                 title: nil,
                 updated_at: nil,
                 width: 2600
               },
               operation_index: 5,
               processed_formats: [:gif],
               size_cfg: %{"crop" => true, "quality" => 90, "size" => "400x400>"},
               size_key: "thumb",
               sized_image_dir: "images/exhibitions/cover/thumb",
               sized_image_path: "images/exhibitions/cover/thumb/image.gif",
               total_operations: 6,
               type: :gif,
               user: :system
             },
             %Brando.Images.Operation{
               filename: "image.gif",
               image_id: 3,
               image_struct: %Brando.Images.Image{
                 alt: nil,
                 cdn: false,
                 config_target: nil,
                 creator_id: nil,
                 credits: nil,
                 deleted_at: nil,
                 dominant_color: nil,
                 focal: %{"x" => 50, "y" => 50},
                 formats: nil,
                 height: 2600,
                 id: 3,
                 inserted_at: nil,
                 path: "images/exhibitions/cover/image.gif",
                 sizes: %{
                   "large" => "images/exhibitions/cover/large/image.gif",
                   "medium" => "images/exhibitions/cover/medium/image.gif",
                   "micro" => "images/exhibitions/cover/micro/image.gif",
                   "small" => "images/exhibitions/cover/small/image.gif",
                   "thumb" => "images/exhibitions/cover/thumb/image.gif",
                   "xlarge" => "images/exhibitions/cover/xlarge/image.gif"
                 },
                 status: :unprocessed,
                 title: nil,
                 updated_at: nil,
                 width: 2600
               },
               operation_index: 6,
               processed_formats: [:gif],
               size_cfg: %{"quality" => 90, "size" => "2100"},
               size_key: "xlarge",
               sized_image_dir: "images/exhibitions/cover/xlarge",
               sized_image_path: "images/exhibitions/cover/xlarge/image.gif",
               total_operations: 6,
               type: :gif,
               user: :system
             }
           ]
  end

  test "create_image_size gif" do
    op = %Brando.Images.Operation{
      filename: "image.gif",
      image_id: 1,
      image_struct: %Brando.Images.Image{
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
      image_id: 1,
      image_struct: %Brando.Images.Image{
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
