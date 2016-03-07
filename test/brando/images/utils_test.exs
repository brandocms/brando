defmodule Brando.Images.UtilsTest do
  use ExUnit.Case
  import Brando.Images.Utils
  alias Brando.Images.Upload

  @cfg %{
    allowed_mimetypes: ["image/jpeg", "image/png"],
    default_size: :medium,
    upload_path: Path.join("images", "default"),
    random_filename: false,
    size_limit: 10_240_000,
    sizes: %{
      "small" =>  %{"size" => "300", "quality" => 100},
      "medium" => %{"size" => "500", "quality" => 100},
      "large" =>  %{"size" => "700", "quality" => 100},
      "xlarge" => %{"size" => "900", "quality" => 100},
      "thumb" =>  %{"size" => "150x150", "quality" => 100, "crop" => true},
      "micro" =>  %{"size" => "25x25", "quality" => 100, "crop" => true}
    }
  }

  @broken_cfg Map.put(@cfg, :upload_path, Path.join(["images", "default", "sample.png"]))
  @random_filename_cfg Map.put(@cfg, :random_filename, true)
  @upload %Plug.Upload{
    content_type: "image/png",
    filename: "sample.png",
    path: "#{Path.expand("../../", __DIR__)}/fixtures/sample.png"
  }
  @blank_upload %Plug.Upload{
    content_type: "image/png",
    filename: "",
    path: "#{Path.expand("../../", __DIR__)}/fixtures/sample.png"
  }
  @slug_upload %Plug.Upload{
    content_type: "image/png",
    filename: "file with spaces.png",
    path: "#{Path.expand("../../", __DIR__)}/fixtures/sample.png"
  }
  @image %Brando.Type.Image{
    credits: nil,
    optimized: false,
    path: "images/default/sample.png",
    sizes: %{
      "large" => "images/default/large/sample.png",
      "medium" => "images/default/medium/sample.png",
      "micro" => "images/default/micro/sample.png",
      "small" => "images/default/small/sample.png",
      "thumb" => "images/default/thumb/sample.png",
      "xlarge" => "images/default/xlarge/sample.png"},
    title: nil
  }

  setup do
    File.rm_rf!(Brando.config(:media_path))
    File.mkdir_p!(Brando.config(:media_path))
    :ok
  end

  test "do_upload/2" do
    assert Upload.do_upload(@upload, @cfg) == {:ok, Map.put(@image, :optimized, true)}
    refute Upload.do_upload(@upload, @cfg) == {:ok, @image}

    {:ok, image} = Upload.do_upload(@slug_upload, @cfg)
    assert image.path == "images/default/file-with-spaces.png"

    {:ok, image} = Upload.do_upload(@slug_upload, @random_filename_cfg)
    refute image.path == "images/default/file-with-spaces.png"

    assert_raise Brando.Exception.UploadError, fn -> Upload.do_upload(@slug_upload, @broken_cfg) end
    assert_raise Brando.Exception.UploadError, fn -> Upload.do_upload(@blank_upload, @cfg) end
  end

  test "size_dir/2 binary" do
    assert size_dir("test/dir/filename.jpg", "thumb") == "test/dir/thumb/filename.jpg"
  end

  test "size_dir/2 atom" do
    assert size_dir("test/dir/filename.jpg", :thumb) == "test/dir/thumb/filename.jpg"
  end
end
