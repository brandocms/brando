defmodule Brando.UploadsTest do
  # sync: the max_concurrent_transfers tests mutate global Application env,
  # which would race concurrent readers under async: true.
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]
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

  defp direct_video_cfg(overrides \\ %{}) do
    cdn = %Brando.CDN.Config{
      enabled: true,
      direct: true,
      bucket: "testbucket",
      media_url: "https://testbucket.ams3.digitaloceanspaces.com",
      s3: @s3_config
    }

    struct(
      Brando.Type.VideoConfig,
      Map.merge(
        %{
          cdn: cdn,
          upload_strategy: :s3,
          upload_path: Path.join("videos", "tests"),
          allowed_mimetypes: ["video/mp4"],
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
      assert limit > Uploads.max_file_size()

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

  describe "validate_provider_video_intake/2" do
    # Credentials for both providers used below, so `validate_provider_credentials/1`
    # is not what these observe. It runs before `validate_intake/4`, so without
    # them every assertion here comes back `{:error, :provider_not_configured}`
    # and the size/extension/MIME rules they exist for are never reached.
    setup do
      put_test_env(Brando.Videos.Uploaders.Mux,
        access_token_id: "id",
        access_token_secret: "secret"
      )

      put_test_env(Brando.Videos.Uploaders.Bunny, api_key: "key")
      :ok
    end

    test "enforces upload gate, strategy, size, extension, and MIME type" do
      cfg = %Brando.Type.VideoConfig{
        upload_strategy: :mux,
        allow_uploads: true,
        size_limit: 10_000,
        allowed_mimetypes: ["video/mp4"]
      }

      assert :ok =
               Uploads.validate_provider_video_intake(cfg, %{
                 name: "clip.mp4",
                 size: 9_000,
                 type: "video/mp4"
               })

      assert {:error, "File is too large" <> _} =
               Uploads.validate_provider_video_intake(cfg, %{
                 name: "clip.mp4",
                 size: 10_001,
                 type: "video/mp4"
               })

      assert {:error, "Rejected file type" <> _} =
               Uploads.validate_provider_video_intake(cfg, %{
                 name: "clip.mp4",
                 size: 9_000,
                 type: "application/pdf"
               })

      assert {:error, "Unsupported video type" <> _} =
               Uploads.validate_provider_video_intake(cfg, %{
                 name: "clip.exe",
                 size: 9_000,
                 type: "video/mp4"
               })

      assert {:error, "Video uploads are disabled" <> _} =
               Uploads.validate_provider_video_intake(%{cfg | allow_uploads: false}, %{
                 name: "clip.mp4",
                 size: 9_000,
                 type: "video/mp4"
               })

      assert {:error, "Video upload strategy" <> _} =
               Uploads.validate_provider_video_intake(%{cfg | upload_strategy: :local}, %{
                 name: "clip.mp4",
                 size: 9_000,
                 type: "video/mp4"
               })
    end

    test "infers the standard MIME type when the browser leaves it blank" do
      cfg = %Brando.Type.VideoConfig{
        upload_strategy: :bunny,
        allowed_mimetypes: ["video/quicktime"]
      }

      assert :ok =
               Uploads.validate_provider_video_intake(cfg, %{
                 name: "clip.mov",
                 size: 100,
                 type: ""
               })
    end

    # The pre-flight credential check. It lives here, beside the other
    # pre-flight validators, rather than in the provider clients' hot path:
    # those raise, and a raise at file-pick time takes a LiveView down with an
    # editor's unsaved work in it. See
    # `test/brando_admin/live/video_picker_credentials_test.exs` for that
    # consequence asserted against a real mounted form.
    test "rejects a provider whose credentials are missing" do
      put_test_env(Brando.Videos.Uploaders.Mux, [])

      cfg = %Brando.Type.VideoConfig{upload_strategy: :mux, allow_uploads: true}

      assert {:error, :provider_not_configured} =
               Uploads.validate_provider_video_intake(cfg, %{
                 name: "clip.mp4",
                 size: 9_000,
                 type: "video/mp4"
               })
    end

    # Ordering is load-bearing in both directions, so both are pinned.
    #
    # An unusable *strategy* is reported on its own terms rather than as a
    # credentials problem — `:local` has no provider credentials to be missing,
    # so "not configured" would send an operator looking for the wrong thing.
    test "reports an unusable strategy before it reports credentials" do
      put_test_env(Brando.Videos.Uploaders.Mux, [])

      cfg = %Brando.Type.VideoConfig{upload_strategy: :local, allow_uploads: true}

      assert {:error, "Video upload strategy" <> _} =
               Uploads.validate_provider_video_intake(cfg, %{
                 name: "clip.mp4",
                 size: 9_000,
                 type: "video/mp4"
               })
    end

    # And credentials are reported before size, because there is no point
    # size-checking an upload that cannot start. This is the ordering choice
    # that broke two existing tests in this file — recorded as a test rather
    # than as a comment, since the fix for those was to add credentials to the
    # setup, which would otherwise quietly hide the decision.
    test "reports missing credentials before an oversized file" do
      put_test_env(Brando.Videos.Uploaders.Mux, [])

      cfg = %Brando.Type.VideoConfig{
        upload_strategy: :mux,
        allow_uploads: true,
        size_limit: 10_000
      }

      assert {:error, :provider_not_configured} =
               Uploads.validate_provider_video_intake(cfg, %{
                 name: "clip.mp4",
                 size: 10_001,
                 type: "video/mp4"
               })
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
    test "signs Content-Type and omits ACLs by default" do
      cfg = direct_cfg()

      assert {:ok, %{upload_url: url, headers: headers}} =
               Uploads.presign_put("media/files/tests/doc.pdf", cfg, mime_type: "application/pdf")

      uri = URI.parse(url)
      query = URI.decode_query(uri.query)

      assert uri.host =~ "digitaloceanspaces.com"
      assert uri.path =~ "testbucket"
      assert uri.path =~ "media/files/tests/doc.pdf"
      assert headers == %{"content-type" => "application/pdf"}
      assert query["X-Amz-SignedHeaders"] =~ "content-type"
      refute query["X-Amz-SignedHeaders"] =~ "x-amz-acl"
      assert query["X-Amz-Expires"] == "600"
      assert query["X-Amz-Signature"]
      assert query["X-Amz-Credential"] =~ "TESTKEY"
    end

    test "signs an ACL header only when explicitly configured" do
      cfg = direct_cfg()
      cfg = %{cfg | cdn: %{cfg.cdn | direct_acl: "public-read"}}

      assert {:ok, %{upload_url: url, headers: headers}} =
               Uploads.presign_put("media/files/tests/doc.pdf", cfg, mime_type: "application/pdf")

      query = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

      assert headers["x-amz-acl"] == "public-read"
      assert query["X-Amz-SignedHeaders"] =~ "x-amz-acl"
      refute Map.has_key?(query, "x-amz-acl")
    end
  end

  describe "validate_direct_object/3" do
    test "accepts matching HEAD metadata" do
      response = %{
        headers: [
          {"Content-Length", "1234"},
          {"Content-Type", "application/pdf; charset=binary"}
        ]
      }

      assert :ok = Uploads.validate_direct_object(response, 1234, "application/pdf")
    end

    test "rejects size and content type mismatches" do
      response = %{headers: [{"content-length", "1234"}, {"content-type", "application/pdf"}]}

      assert {:error, "Uploaded object size mismatch" <> _} =
               Uploads.validate_direct_object(response, 999, "application/pdf")

      assert {:error, "Uploaded object type mismatch" <> _} =
               Uploads.validate_direct_object(response, 1234, "text/plain")
    end
  end

  describe "max_concurrent_transfers/0" do
    test "defaults to 3" do
      assert Uploads.max_concurrent_transfers() == 3
    end

    test "reads from config" do
      put_test_env(Brando.Uploads, max_concurrent_transfers: 1)

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

  describe "direct_video_transport?/1" do
    test "requires the explicit S3 strategy and an enabled direct video CDN" do
      cfg = direct_video_cfg()
      assert Uploads.direct_video_transport?(cfg)
      assert Uploads.video_upload_available?(cfg)

      refute Uploads.direct_video_transport?(%{cfg | upload_strategy: :local})
      refute Uploads.direct_video_transport?(%{cfg | cdn: %{cfg.cdn | direct: false}})
      refute Uploads.direct_video_transport?(%{cfg | cdn: %{cfg.cdn | enabled: false}})
      refute Uploads.direct_video_transport?(%{cfg | cdn: %{cfg.cdn | bucket: nil}})
      refute Uploads.direct_video_transport?(%{cfg | cdn: %{cfg.cdn | media_url: nil}})
    end

    test "presigns video Content-Type against the video config's bucket" do
      cfg = direct_video_cfg()

      assert {:ok, %{upload_url: url, headers: headers}} =
               Uploads.presign_put("media/videos/tests/clip.mp4", cfg, mime_type: "video/mp4")

      query = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

      assert headers == %{"content-type" => "video/mp4"}
      assert query["X-Amz-SignedHeaders"] =~ "content-type"
      assert url =~ "testbucket"
      assert url =~ "media/videos/tests/clip.mp4"
    end
  end
end
