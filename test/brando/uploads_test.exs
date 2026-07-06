defmodule Brando.UploadsTest do
  use ExUnit.Case, async: true

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

  describe "validate_intake/3" do
    test "rejects files over the max size" do
      assert {:error, "File is too large" <> _} =
               Uploads.validate_intake(:file, "big.pdf", Uploads.max_file_size() + 1)
    end

    test "rejects unknown image extensions" do
      assert {:error, "Unsupported image type" <> _} = Uploads.validate_intake(:image, "evil.exe", 100)
    end

    test "accepts allowed image extensions and any file type" do
      assert :ok = Uploads.validate_intake(:image, "photo.JPG", 100)
      assert :ok = Uploads.validate_intake(:file, "archive.zip", 100)
    end
  end

  describe "initiate/4" do
    test "images are always server transport" do
      assert {:ok, :server} = Uploads.initiate(:image, "default", %{name: "a.jpg", size: 1, type: "image/jpeg"}, nil)
    end

    test "files with non-direct config are server transport" do
      # test env has no direct: true file CDN config
      assert {:ok, :server} = Uploads.initiate(:file, "default", %{name: "a.pdf", size: 1, type: "application/pdf"}, nil)
    end

    test "oversize files are rejected before transport decision" do
      assert {:error, _} =
               Uploads.initiate(
                 :file,
                 "default",
                 %{name: "a.pdf", size: Uploads.max_file_size() + 1, type: "application/pdf"},
                 nil
               )
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
