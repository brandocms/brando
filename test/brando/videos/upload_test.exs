defmodule Brando.Videos.UploadTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory

  @cfg %Brando.Type.VideoConfig{
    upload_path: Path.join("videos", "tests"),
    random_filename: false,
    slugify_filename: true
  }

  defmodule DirectVideoAssets do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Videos",
      schema: "DirectVideoAssets",
      singular: "direct_video_asset",
      plural: "direct_video_assets",
      gettext_module: Brando.Gettext

    identifier false
    persist_identifier false

    assets do
      asset :clip, :video,
        cfg: %{
          upload_strategy: :s3,
          upload_path: "videos/direct",
          allowed_mimetypes: ["video/mp4"],
          cdn: %Brando.CDN.Config{
            enabled: true,
            direct: true,
            bucket: "video-bucket",
            media_url: "https://media.example.com",
            s3: %Brando.CDN.S3Config{
              access_key_id: "TESTKEY",
              secret_access_key: "TESTSECRET",
              scheme: "https://",
              host: "s3.example.com",
              region: "test-region"
            }
          }
        }
    end
  end

  def completed_callback(video, user, pid) do
    send(pid, {:video_completed, video, user})
  end

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

    test "runs an MFA callback after a local video is ready" do
      user = Factory.insert(:random_user)
      tmp = Path.join(System.tmp_dir!(), "upload-callback-#{System.unique_integer([:positive])}.mp4")
      File.write!(tmp, :crypto.strong_rand_bytes(128))
      on_exit(fn -> File.rm(tmp) end)

      config = %{@cfg | completed_callback: {__MODULE__, :completed_callback, [self()]}}
      meta = %{path: tmp, config_target: "video:Some.Schema:field"}
      entry = %{client_name: Path.basename(tmp), client_type: "video/mp4", client_size: 128}

      assert {:ok, video} = Brando.Upload.handle_upload(meta, entry, config, user)
      assert_received {:video_completed, ^video, ^user}
    end

    test "creates an S3-backed File and ready Video after a verified direct upload" do
      user = Factory.insert(:random_user)

      folder =
        %Brando.Media.Folder{}
        |> Brando.Media.Folder.changeset(%{
          scope: "video",
          name: "Direct video",
          path: "videos/direct"
        })
        |> Brando.Repo.insert!()

      config = %{
        @cfg
        | upload_strategy: :s3,
          completed_callback: {__MODULE__, :completed_callback, [self()]}
      }

      upload = %{
        cfg: config,
        meta: %{
          key: "media/videos/tests/direct-clip.mp4",
          config_target: "video:Some.Schema:field",
          folder_id: folder.id
        },
        upload_entry: %{
          client_name: "direct clip.mp4",
          client_type: "video/mp4",
          client_size: 2048
        }
      }

      assert {:ok, video} = Brando.Upload.handle_upload_type(upload, user, :direct_to_s3)
      assert video.type == :upload
      assert video.status == :ready
      assert video.folder_id == folder.id
      assert video.config_target == "video:Some.Schema:field"
      assert_received {:video_completed, ^video, ^user}

      video = Brando.Repo.preload(video, :file)
      assert video.file.filename == "direct-clip.mp4"
      assert video.file.filesize == 2048
      assert video.file.mime_type == "video/mp4"
      assert video.file.cdn
      assert video.file.folder_id == folder.id
    end
  end

  test "the video schema accepts Bunny provider records" do
    changeset = Brando.Videos.Video.changeset(%Brando.Videos.Video{}, %{type: :bunny, creator_id: 1})

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :type) == :bunny
  end

  test "the video schema accepts Cloudflare Stream provider records" do
    changeset =
      Brando.Videos.Video.changeset(%Brando.Videos.Video{}, %{type: :cloudflare, creator_id: 1})

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :type) == :cloudflare
  end

  test "video browser filtering accepts canonical string config targets" do
    user = Factory.insert(:random_user)
    target = "gallery:Elixir.Brando.GalleryConfigTest.Schema:media"
    matching = Factory.insert(:video, creator: user, config_target: target)
    _other = Factory.insert(:video, creator: user, config_target: "default")

    assert {:ok, videos} = Brando.Videos.list_videos(%{filter: %{config_target: target}})
    assert Enum.map(videos, & &1.id) == [matching.id]
  end

  test "registered S3 video configs select direct transport and resolve CDN playback URLs" do
    target = Brando.Assets.ConfigTarget.serialize({:video, DirectVideoAssets, :clip})

    assert {:ok, {:direct, direct}} =
             Brando.Uploads.initiate(
               :video,
               target,
               %{name: "My Clip.mp4", size: 1024, type: "video/mp4"},
               nil
             )

    assert direct.key =~ "media/videos/direct/my-clip-"
    assert direct.key =~ ".mp4"
    assert direct.upload_headers == %{"content-type" => "video/mp4"}
    assert direct.resolved_target == target

    file = %Brando.Files.File{
      filename: "clip.mp4",
      config_target: target,
      cdn: true
    }

    assert Brando.Utils.media_url(file) ==
             "https://media.example.com/media/videos/direct/clip.mp4"
  end

  test "provider upload availability requires the complete webhook and playback configuration" do
    mux = Brando.Videos.Uploaders.Mux
    bunny = Brando.Videos.Uploaders.Bunny
    cloudflare = Brando.Videos.Uploaders.Cloudflare
    previous_mux = Application.get_env(:brando, mux)
    previous_bunny = Application.get_env(:brando, bunny)
    previous_cloudflare = Application.get_env(:brando, cloudflare)

    on_exit(fn ->
      restore_env(mux, previous_mux)
      restore_env(bunny, previous_bunny)
      restore_env(cloudflare, previous_cloudflare)
    end)

    Application.put_env(:brando, mux, access_token_id: "id", access_token_secret: "secret")
    refute Brando.Videos.upload_available?(:mux)

    Application.put_env(:brando, mux,
      access_token_id: "id",
      access_token_secret: "secret",
      webhook_secret: "webhook"
    )

    assert Brando.Videos.upload_available?(:mux)

    Application.put_env(:brando, bunny,
      api_key: "api",
      library_id: "133",
      cdn_hostname: "video.example.com"
    )

    refute Brando.Videos.upload_available?(:bunny)

    Application.put_env(:brando, bunny,
      api_key: "api",
      library_id: "133",
      cdn_hostname: "video.example.com",
      webhook_secret: "read-only"
    )

    assert Brando.Videos.upload_available?(:bunny)

    Application.put_env(:brando, cloudflare,
      account_id: "account",
      api_token: "token"
    )

    refute Brando.Videos.upload_available?(:cloudflare)

    Application.put_env(:brando, cloudflare,
      account_id: "account",
      api_token: "token",
      webhook_secret: "webhook"
    )

    assert Brando.Videos.upload_available?(:cloudflare)
  end

  defp restore_env(module, nil), do: Application.delete_env(:brando, module)
  defp restore_env(module, value), do: Application.put_env(:brando, module, value)
end
