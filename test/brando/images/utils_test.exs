defmodule Brando.Images.UtilsTest do
  use ExUnit.Case, async: true
  import Brando.Images.Utils
  alias Brando.Type.ImageConfig

  @cfg %ImageConfig{}
  @random_filename_cfg %ImageConfig{random_filename: true}
  @upload %Plug.Upload{content_type: "image/png", filename: "sample.png", path: "#{Path.expand("../../", __DIR__)}/fixtures/sample.png"}
  @blank_upload %Plug.Upload{content_type: "image/png", filename: "", path: "#{Path.expand("../../", __DIR__)}/fixtures/sample.png"}
  @slug_upload %Plug.Upload{content_type: "image/png", filename: "file with spaces.png", path: "#{Path.expand("../../", __DIR__)}/fixtures/sample.png"}
  @image %Brando.Type.Image{credits: nil, optimized: false, path: "images/default/sample.png", sizes: %{large: "images/default/large/sample.png", medium: "images/default/medium/sample.png", small: "images/default/small/sample.png", thumb: "images/default/thumb/sample.png", xlarge: "images/default/xlarge/sample.png"}, title: nil}

  test "do_upload/2" do
    assert do_upload(@upload, @cfg) == {:ok, @image}
    refute do_upload(@upload, @cfg) == {:ok, @image}
    {:ok, image} = do_upload(@slug_upload, @cfg)
    assert image.path == "images/default/file-with-spaces.png"
    {:ok, image} = do_upload(@slug_upload, @random_filename_cfg)
    refute image.path == "images/default/file-with-spaces.png"
    assert_raise Brando.Exception.UploadError, fn -> do_upload(@blank_upload, @cfg) end
  end

  test "size_dir/2 binary" do
    assert size_dir("test/dir/filename.jpg", "thumb") ==
           "test/dir/thumb/filename.jpg"
  end

  test "size_dir/2 atom" do
    assert size_dir("test/dir/filename.jpg", :thumb) ==
           "test/dir/thumb/filename.jpg"
  end
end