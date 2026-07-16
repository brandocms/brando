defmodule Brando.UploadsTest do
  # sync: the max_concurrent_transfers tests mutate global Application env,
  # which would race concurrent readers under async: true.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Brando.Uploads

  @s3_config %Brando.CDN.S3Config{
    access_key_id: "TESTKEY",
    secret_access_key: "TESTSECRET",
    scheme: "https://",
    host: "ams3.digitaloceanspaces.com",
    region: "ams3"
  }

  defp direct_cfg(overrides \\ %{}) do
    cdn = %Brando.CDN.Config{
      enabled: true,
      direct: true,
      bucket: "testbucket",
      media_url: "https://testbucket.ams3.digitaloceanspaces.com",
      s3: @s3_config
    }

    struct(
      Brando.Type.FileConfig,
      Map.merge(
        %{
          cdn: cdn,
          upload_path: Path.join("files", "tests"),
          allowed_mimetypes: ["application/pdf"],
          random_filename: false,
          slugify_filename: true
        },
        overrides
      )
    )
  end

  describe "validate_intake/4" do
    test "rejects files over the global max when no config limit is given" do
      assert {:error, "File is too large" <> _} =
               Uploads.validate_intake(:file, "big.pdf", Uploads.max_file_size() + 1)
    end

    test "rejects files over an explicit config size_limit" do
      assert {:error, message} = Uploads.validate_intake(:file, "big.pdf", 5_000_001, 5_000_000)
      assert message =~ "File is too large"

      assert :ok = Uploads.validate_intake(:file, "small.pdf", 4_999_999, 5_000_000)
    end

    test "rejects unknown image extensions" do
      assert {:error, "Unsupported image type" <> _} =
               Uploads.validate_intake(:image, "evil.exe", 100)
    end

    test "accepts allowed image extensions and any file type" do
      assert :ok = Uploads.validate_intake(:image, "photo.JPG", 100)
      assert :ok = Uploads.validate_intake(:file, "archive.zip", 100)
    end
  end

  describe "manager_max_file_size/0" do
    test "is a transport envelope above the fallback intake limit" do
      assert Uploads.manager_max_file_size() > Uploads.max_file_size()
      assert Uploads.manager_max_file_size() >= Brando.Type.FileConfig.default_config().size_limit

      assert Uploads.manager_max_file_size() >=
               Brando.Type.VideoConfig.default_config().size_limit
    end

    test "can be raised for installations with unusually large source media" do
      previous = Application.get_env(:brando, Brando.Uploads)
      Application.put_env(:brando, Brando.Uploads, manager_max_file_size: 12_000_000_000)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:brando, Brando.Uploads, previous),
          else: Application.delete_env(:brando, Brando.Uploads)
      end)

      assert Uploads.manager_max_file_size() == 12_000_000_000
    end
  end

  describe "initiate/4" do
    test "images are always server transport" do
      assert {:ok, :server} =
               Uploads.initiate(
                 :image,
                 "default",
                 %{name: "a.jpg", size: 1, type: "image/jpeg"},
                 nil
               )
    end

    test "files with non-direct config are server transport" do
      # test env has no direct: true file CDN config
      assert {:ok, :server} =
               Uploads.initiate(
                 :file,
                 "default",
                 %{name: "a.pdf", size: 1, type: "application/pdf"},
                 nil
               )
    end

    test "enforces the resolved image config's size_limit at intake" do
      limit = Brando.config(Brando.Images)[:default_config][:size_limit]
      assert is_integer(limit)

      assert {:error, "File is too large" <> _} =
               Uploads.initiate(
                 :image,
                 "default",
                 %{name: "big.jpg", size: limit + 1, type: "image/jpeg"},
                 nil
               )

      assert {:ok, :server} =
               Uploads.initiate(
                 :image,
                 "default",
                 %{name: "ok.jpg", size: limit, type: "image/jpeg"},
                 nil
               )
    end

    test "enforces the resolved file config's size_limit at intake" do
      # no file default_config in test env → FileConfig.default_config() applies
      limit = Brando.Type.FileConfig.default_config().size_limit
      assert is_integer(limit) and limit > Uploads.max_file_size()

      assert {:error, "File is too large" <> _} =
               Uploads.initiate(
                 :file,
                 "default",
                 %{name: "big.pdf", size: limit + 1, type: "application/pdf"},
                 nil
               )

      # config limit wins over the lower global default ceiling
      assert {:ok, :server} =
               Uploads.initiate(
                 :file,
                 "default",
                 %{name: "ok.pdf", size: Uploads.max_file_size() + 1, type: "application/pdf"},
                 nil
               )
    end
  end

  describe "resolve_video_config/1" do
    # Regression: the fallback returned the raw configured default, which can
    # be a plain map — a non-struct cfg misses handle_upload_type's
    # VideoConfig clause and local video uploads fall into the generic image
    # path ("Failed to read image dimensions").
    test "always resolves to a VideoConfig struct" do
      assert {%Brando.Type.VideoConfig{}, "default"} =
               Uploads.resolve_video_config("bogus-target")

      assert {%Brando.Type.VideoConfig{}, "default"} = Uploads.resolve_video_config(nil)
    end
  end

  describe "store_upload/4" do
    # Regression: handle_upload/4 leaks 3/4-tuple errors ({:error, :content_type,
    # type, allowed} etc.) — an unnormalized shape crashed the sticky manager
    # mid-consume, killing every in-flight upload.
    test "normalizes a consume-time mimetype rejection to {:error, message}" do
      cfg =
        struct(Brando.Type.FileConfig, %{
          upload_path: Path.join("files", "tests"),
          allowed_mimetypes: ["application/pdf"]
        })

      meta = %{path: "/nonexistent/never-copied.exe", config_target: "default"}
      entry = %{client_name: "evil.exe", client_type: "application/x-msdownload", client_size: 4}

      log =
        capture_log(fn ->
          assert {:error, message} = Uploads.store_upload(meta, entry, cfg, nil)
          assert message =~ "Rejected type [application/x-msdownload]"
        end)

      assert log =~ "store_upload failed"
    end

    test "normalizes an empty filename to {:error, message}" do
      cfg = struct(Brando.Type.FileConfig, %{upload_path: Path.join("files", "tests")})
      meta = %{path: "/nonexistent", config_target: "default"}
      entry = %{client_name: "", client_type: "application/pdf", client_size: 4}

      log =
        capture_log(fn ->
          assert {:error, "Empty filename"} = Uploads.store_upload(meta, entry, cfg, nil)
        end)

      assert log =~ "store_upload failed"
    end
  end

  describe "presign_put/2" do
    test "generates a signed short-lived PUT URL with public-read acl" do
      cfg = direct_cfg()

      assert {:ok, url} = Uploads.presign_put("media/files/tests/doc.pdf", cfg)

      uri = URI.parse(url)
      query = URI.decode_query(uri.query)

      assert uri.host =~ "digitaloceanspaces.com"
      assert uri.path =~ "testbucket"
      assert uri.path =~ "media/files/tests/doc.pdf"
      assert query["x-amz-acl"] == "public-read"
      assert query["X-Amz-Expires"] == "600"
      assert query["X-Amz-Signature"]
      assert query["X-Amz-Credential"] =~ "TESTKEY"
    end
  end

  describe "max_concurrent_transfers/0" do
    test "defaults to 3" do
      assert Uploads.max_concurrent_transfers() == 3
    end

    test "reads from config" do
      Application.put_env(:brando, Brando.Uploads, max_concurrent_transfers: 1)
      on_exit(fn -> Application.delete_env(:brando, Brando.Uploads) end)

      assert Uploads.max_concurrent_transfers() == 1
    end
  end

  describe "direct_transport?/1" do
    test "true for enabled + direct configs without content_disposition" do
      assert Uploads.direct_transport?(direct_cfg())
    end

    test "false when the CDN config is not direct" do
      cfg = direct_cfg()
      cfg = %{cfg | cdn: %{cfg.cdn | direct: false}}
      refute Uploads.direct_transport?(cfg)
    end

    test "false when the CDN config is disabled" do
      cfg = direct_cfg()
      cfg = %{cfg | cdn: %{cfg.cdn | enabled: false}}
      refute Uploads.direct_transport?(cfg)
    end

    test "false when content_disposition is set (header can't ride an unsigned presign)" do
      refute Uploads.direct_transport?(direct_cfg(%{content_disposition: :attachment}))
    end
  end
end
