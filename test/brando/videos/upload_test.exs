defmodule Brando.Videos.UploadTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory

  @cfg %Brando.Type.VideoConfig{
    upload_path: Path.join("videos", "tests"),
    random_filename: false,
    slugify_filename: true
  }

  describe "handle_upload with a VideoConfig" do
    test "stores the file and creates an :upload Video wrapping it" do
      user = Factory.insert(:random_user)

      tmp = Path.join(System.tmp_dir!(), "upload-test-#{System.unique_integer([:positive])}.mp4")
      File.write!(tmp, :crypto.strong_rand_bytes(1024))
      on_exit(fn -> File.rm(tmp) end)

      meta = %{path: tmp, config_target: "video:Some.Schema:field"}

      entry = %{
        client_name: Path.basename(tmp),
        client_type: "video/mp4",
        client_size: 1024
      }

      assert {:ok, %Brando.Videos.Video{} = video} = Brando.Upload.handle_upload(meta, entry, @cfg, user)

      assert video.type == :upload
      assert video.status == :ready
      assert video.config_target == "video:Some.Schema:field"
      assert video.file_id

      video = Brando.Repo.preload(video, :file)
      assert video.file.mime_type == "video/mp4"
      assert video.file.config_target == "video:Some.Schema:field"
    end

    test "rejects disallowed mimetypes" do
      user = Factory.insert(:random_user)

      tmp = Path.join(System.tmp_dir!(), "upload-test-#{System.unique_integer([:positive])}.exe")
      File.write!(tmp, "nope")
      on_exit(fn -> File.rm(tmp) end)

      meta = %{path: tmp, config_target: "video:Some.Schema:field"}
      entry = %{client_name: Path.basename(tmp), client_type: "application/x-msdownload", client_size: 4}

      assert {:error, :content_type, "application/x-msdownload", _allowed} =
               Brando.Upload.handle_upload(meta, entry, @cfg, user)
    end
  end
end
