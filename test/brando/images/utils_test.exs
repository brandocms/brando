defmodule Brando.Images.UtilsTest do
  use ExUnit.Case
  import Brando.Images.Utils
  alias Brando.Images.Upload
  alias Brando.Factory

  setup do
    File.rm_rf!(Brando.config(:media_path))
    File.mkdir_p!(Brando.config(:media_path))
    :ok
  end

  test "do_upload/2" do
    cfg = Factory.build(:image_cfg_params)
    image = Factory.build(:image_type)
    upload = Factory.build(:plug_upload)

    slug_upload = Map.put(upload, :filename, "file with spaces.png")
    blank_upload = Map.put(upload, :filename, "")

    assert Upload.do_upload(upload, cfg) == {:ok, Map.put(image, :optimized, true)}
    refute Upload.do_upload(upload, cfg) == {:ok, image}

    {:ok, image} = Upload.do_upload(slug_upload, cfg)
    assert image.path == "images/default/file-with-spaces.png"

    random_filename_cfg = Map.put(cfg, :random_filename, true)
    {:ok, image} = Upload.do_upload(slug_upload, random_filename_cfg)
    refute image.path == "images/default/file-with-spaces.png"

    broken_cfg = Map.put(cfg, :upload_path, Path.join(["images", "default", "sample.png"]))

    assert_raise Brando.Exception.UploadError, fn -> Upload.do_upload(slug_upload, broken_cfg) end
    assert_raise Brando.Exception.UploadError, fn -> Upload.do_upload(blank_upload, cfg) end
  end

  test "size_dir/2 binary" do
    assert size_dir("test/dir/filename.jpg", "thumb") == "test/dir/thumb/filename.jpg"
  end

  test "size_dir/2 atom" do
    assert size_dir("test/dir/filename.jpg", :thumb) == "test/dir/thumb/filename.jpg"
  end
end
