defmodule Brando.UploadTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Plug.Test
  use RouterHelper

  import Brando.Upload
  import Brando.Images.Utils

  @cfg %Brando.Type.ImageConfig{
    allowed_mimetypes: ["image/jpeg", "image/png"],
    default_size: :medium,
    upload_path: Path.join("images", "avatars"),
    random_filename: true,
    size_limit: 10_240_000,
    sizes: %{
      "thumb" => %{"size" => "150x150", "quality" => 100, "crop" => true},
      "large" => %{"size" => "700", "quality" => 100}
    }
  }

  @up %Plug.Upload{
    content_type: "image/png",
    filename: "sample.png",
    path: Path.expand("../", __DIR__) <> "/fixtures/sample.png"
  }

  test "process_upload regular" do
    {:ok, upload} = process_upload(@up, @cfg)
    refute upload.plug.filename == "sample.png"
    assert upload.plug.upload_path == media_path("images/avatars")
    assert upload.plug.uploaded_file == media_path("images/avatars/#{upload.plug.filename}")
  end

  test "process_upload with non allowed mimetype" do
    up = Map.merge(@up, %{content_type: "image/zip", filename: "sample.zip"})

    assert process_upload(up, @cfg) ==
             {:error, :content_type, "image/zip", ["image/jpeg", "image/png"]}
  end

  test "process_upload with empty filename" do
    up = Map.merge(@up, %{content_type: "image/png", filename: ""})
    assert process_upload(up, @cfg) == {:error, :empty_filename}
  end

  test "process_upload with non-existing file" do
    up = Map.merge(@up, %{path: "fake/path.png"})
    assert {:error, :cp, {:enoent, "fake/path.png", _}} = process_upload(up, @cfg)
  end
end
