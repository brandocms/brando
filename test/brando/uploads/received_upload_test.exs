defmodule Brando.Uploads.ReceivedUploadTest do
  @moduledoc """
  What the server checks once an upload's bytes have arrived: where the file
  lands, how large it really is and what it really holds, whatever the client
  declared when it asked to upload.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Mox

  alias Brando.CDN.Client
  alias Brando.Factory
  alias Brando.Images.Utils
  alias Brando.Tenant.Storage
  alias Brando.Type.FileConfig
  alias Brando.Type.ImageConfig
  alias Brando.Type.VideoConfig
  alias Brando.Uploads
  alias Brando.Uploads.Direct

  @jpg Path.expand("../../fixtures/sample.jpg", __DIR__)
  @png Path.expand("../../fixtures/sample.png", __DIR__)
  @svg ~s(<svg xmlns="http://www.w3.org/2000/svg" width="10" height="20"></svg>)
  @upload_path "received_upload_test"

  @cdn %{
    enabled: true,
    direct: true,
    bucket: "testbucket",
    media_url: "https://testbucket.ams3.digitaloceanspaces.com",
    s3: %Brando.CDN.S3Config{
      access_key_id: "TESTKEY",
      secret_access_key: "TESTSECRET",
      scheme: "https://",
      host: "ams3.digitaloceanspaces.com",
      region: "ams3"
    },
    keep_local_copy: false
  }

  setup :verify_on_exit!

  setup do
    root = Storage.current_media_root()
    dir = Path.join(System.tmp_dir!(), "brando_received_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    on_exit(fn ->
      File.rm_rf(dir)
      File.rm_rf(Path.join(root, @upload_path))
    end)

    user = Factory.insert(:random_user)

    {:ok, dir: dir, root: root, target_dir: Path.join(root, @upload_path), user: user}
  end

  defp temp(dir, content) do
    path = Path.join(dir, "upload-#{System.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end

  defp meta(path), do: %{path: path, config_target: "default"}
  defp entry(name, type, size \\ 1), do: %{client_name: name, client_type: type, client_size: size}

  defp image_cfg(overrides \\ %{}) do
    struct(
      %ImageConfig{upload_path: @upload_path, random_filename: false, slugify_filename: true, size_limit: 5_000_000},
      overrides
    )
  end

  defp file_cfg(overrides) do
    struct(
      %FileConfig{
        upload_path: @upload_path,
        allowed_mimetypes: ["*"],
        random_filename: false,
        slugify_filename: true,
        size_limit: 5_000_000
      },
      overrides
    )
  end

  defp stored(%{target_dir: dir}),
    do:
      dir
      |> File.ls()
      |> then(fn
        {:ok, l} -> l
        _ -> []
      end)

  describe "a client name never selects a directory" do
    test "with slugify off, dot-dot segments stay inside the upload path", %{dir: dir, root: root, user: user} = ctx do
      name = "../../received_upload_escape_#{System.unique_integer([:positive])}.txt"
      cfg = file_cfg(%{slugify_filename: false})

      assert {:ok, file} = Uploads.store_upload(meta(temp(dir, "marker")), entry(name, "text/plain"), cfg, user)

      assert file.filename == Path.basename(name)
      assert stored(ctx) == [Path.basename(name)]
      refute File.exists?(Path.expand(Path.join([root, @upload_path, name])))
    end

    test "with slugify and overwrite off an existing file outside the root is untouched", %{
      dir: dir,
      root: root,
      user: user
    } do
      victim = Path.join(Path.dirname(root), "received_upload_victim_#{System.unique_integer([:positive])}.txt")
      File.write!(victim, "original")
      on_exit(fn -> File.rm(victim) end)

      name = "../../" <> Path.basename(victim)
      cfg = file_cfg(%{slugify_filename: false, overwrite: true})

      assert {:ok, _} = Uploads.store_upload(meta(temp(dir, "marker")), entry(name, "text/plain"), cfg, user)
      assert File.read!(victim) == "original"
    end

    test "a name that is only dots is refused", %{dir: dir, user: user} = ctx do
      cfg = file_cfg(%{slugify_filename: false})

      assert {:error, _} = Uploads.store_upload(meta(temp(dir, "x")), entry("a/..", "text/plain"), cfg, user)
      assert stored(ctx) == []
    end

    test "an upload path that climbs out of the root is refused", %{dir: dir, root: root, user: user} do
      escape = "../received_upload_climb_#{System.unique_integer([:positive])}"
      on_exit(fn -> File.rm_rf(Path.expand(Path.join(root, escape))) end)
      cfg = file_cfg(%{upload_path: escape})

      assert {:error, _} = Uploads.store_upload(meta(temp(dir, "x")), entry("a.txt", "text/plain"), cfg, user)
      refute File.exists?(Path.expand(Path.join(root, escape)))
    end

    test "a direct key keeps the name in the upload path" do
      put_test_env(
        Brando.Files,
        Keyword.put(Application.get_env(:brando, Brando.Files, []), :default_config, %{
          upload_path: @upload_path,
          allowed_mimetypes: ["application/pdf"],
          random_filename: false,
          slugify_filename: false,
          cdn: @cdn
        })
      )

      assert {:ok, %{key: key}} =
               Direct.presign(:file, "default", %{name: "../../other/victim.pdf", size: 10, type: "application/pdf"})

      assert key =~ ~r"^media/#{@upload_path}/victim-\w+\.pdf$"
    end
  end

  describe "size, read from the bytes that arrived" do
    test "over the limit is refused and nothing is written, whatever the entry says", %{dir: dir, user: user} = ctx do
      cfg = image_cfg(%{size_limit: 100})
      path = temp(dir, File.read!(@jpg))

      assert {:error, message} = Uploads.store_upload(meta(path), entry("big.jpg", "image/jpeg", 10), cfg, user)
      assert is_binary(message)
      assert stored(ctx) == []
    end

    test "the file row records the real size, not the declared one", %{dir: dir, user: user} do
      path = temp(dir, "twelve bytes")

      assert {:ok, file} = Uploads.store_upload(meta(path), entry("a.txt", "text/plain", 1), file_cfg(%{}), user)
      assert file.filesize == 12
    end

    test "an image extension outside the list is refused", %{dir: dir, user: user} = ctx do
      path = temp(dir, File.read!(@jpg))

      assert {:error, _} = Uploads.store_upload(meta(path), entry("orphan.html", "image/jpeg"), image_cfg(), user)
      assert stored(ctx) == []
    end
  end

  describe "image type, read from the bytes that arrived" do
    test "markup declared as a jpeg is refused and nothing is written", %{dir: dir, user: user} = ctx do
      path = temp(dir, "<html><body></body></html>")

      assert {:error, _} = Uploads.store_upload(meta(path), entry("a.jpg", "image/jpeg"), image_cfg(), user)
      assert stored(ctx) == []
    end

    test "an SVG declared as a png does not get past a list without SVG", %{dir: dir, user: user} = ctx do
      cfg = image_cfg(%{allowed_mimetypes: ["image/png"]})

      assert {:error, _} = Uploads.store_upload(meta(temp(dir, @svg)), entry("a.png", "image/png"), cfg, user)
      assert stored(ctx) == []
    end

    test "markup declared as an SVG is refused and nothing is written", %{dir: dir, user: user} = ctx do
      path = temp(dir, "<html><body></body></html>")

      assert {:error, _} = Uploads.store_upload(meta(path), entry("a.svg", "image/svg+xml"), image_cfg(), user)
      assert stored(ctx) == []
    end

    test "a jpeg declared as an SVG is refused", %{dir: dir, user: user} = ctx do
      path = temp(dir, File.read!(@jpg))

      assert {:error, _} = Uploads.store_upload(meta(path), entry("a.svg", "image/svg+xml"), image_cfg(), user)
      assert stored(ctx) == []
    end

    test "an SVG declaring entities is refused and does not crash", %{dir: dir, user: user} = ctx do
      path = temp(dir, ~s(<!DOCTYPE svg [<!ENTITY a "aaaa">]><svg width="1" height="1"></svg>))

      assert {:error, _} = Uploads.store_upload(meta(path), entry("a.svg", "image/svg+xml"), image_cfg(), user)
      assert stored(ctx) == []
    end

    test "a png named .jpg keeps working when the list allows png", %{dir: dir, user: user} do
      path = temp(dir, File.read!(@png))

      assert {:ok, image} = Uploads.store_upload(meta(path), entry("really-png.jpg", "image/jpeg"), image_cfg(), user)
      assert image.width > 0
    end

    test "a damaged image is refused and leaves nothing behind", %{dir: dir, user: user} = ctx do
      path = temp(dir, <<0xFF, 0xD8, 0xFF, 0xE0, "not really a jpeg">>)

      assert {:error, _} = Uploads.store_upload(meta(path), entry("a.jpg", "image/jpeg"), image_cfg(), user)
      assert stored(ctx) == []
    end

    test "a damaged image does not replace a stored original", %{dir: dir, target_dir: target_dir, user: user} do
      File.mkdir_p!(target_dir)
      original = File.read!(@jpg)
      File.write!(Path.join(target_dir, "a.jpg"), original)
      path = temp(dir, <<0xFF, 0xD8, 0xFF, 0xE0, "not really a jpeg">>)

      assert {:error, _} =
               Uploads.store_upload(meta(path), entry("a.jpg", "image/jpeg"), image_cfg(%{overwrite: true}), user)

      assert File.read!(Path.join(target_dir, "a.jpg")) == original
    end
  end

  describe "images, SVGs, files and videos keep working" do
    test "a jpeg", %{dir: dir, user: user} do
      path = temp(dir, File.read!(@jpg))

      assert {:ok, %{status: :unprocessed}} =
               Uploads.store_upload(meta(path), entry("a.jpg", "image/jpeg"), image_cfg(), user)
    end

    test "an SVG, with its declared size", %{dir: dir, user: user} do
      assert {:ok, image} =
               Uploads.store_upload(meta(temp(dir, @svg)), entry("a.svg", "image/svg+xml"), image_cfg(), user)

      assert {image.width, image.height} == {10, 20}
    end

    test "an SVG with a viewBox only", %{dir: dir, user: user} do
      svg = ~s(<?xml version="1.0"?>\n<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 480"></svg>)

      assert {:ok, image} = Uploads.store_upload(meta(temp(dir, svg)), entry("a.svg", "image/svg+xml"), image_cfg(), user)
      assert {image.width, image.height} == {640, 480}
    end

    test "any bytes as a file", %{dir: dir, user: user} do
      assert {:ok, _} =
               Uploads.store_upload(meta(temp(dir, <<0, 1, 2>>)), entry("a.bin", "application/x-x"), file_cfg(%{}), user)
    end

    test "a video refuses bytes that are no video, and takes one that is", %{dir: dir, user: user} do
      cfg = %VideoConfig{
        upload_path: @upload_path,
        allowed_mimetypes: ["video/mp4"],
        upload_strategy: :local,
        allow_uploads: true
      }

      mp4 = File.read!(Path.expand("../../../e2e/playwright/fixtures/video.mp4", __DIR__))

      assert {:error, _} = Uploads.store_upload(meta(temp(dir, "<html></html>")), entry("a.mp4", "video/mp4"), cfg, user)

      assert {:error, _} =
               Uploads.store_upload(
                 meta(temp(dir, <<0x1A, 0x45, 0xDF, 0xA3, 0::64>>)),
                 entry("a.mp4", "video/mp4"),
                 cfg,
                 user
               )

      assert {:ok, video} = Uploads.store_upload(meta(temp(dir, mp4)), entry("a.mp4", "video/mp4"), cfg, user)
      assert video.status == :ready
    end
  end

  describe "direct images, checked on the body fetched back" do
    setup do
      original = Application.get_env(:brando, Brando.Images, [])

      put = fn overrides ->
        config =
          Map.merge(
            %{
              upload_path: @upload_path,
              allowed_mimetypes: ["image/jpeg", "image/svg+xml"],
              random_filename: false,
              size_limit: 5_000_000,
              sizes: %{"thumb" => %{"size" => "150x150", "quality" => 70, "crop" => true}},
              cdn: @cdn
            },
            overrides
          )

        put_test_env(Brando.Images, Keyword.put(original, :default_config, config))
      end

      {:ok, put_config: put}
    end

    defp head_reply(size, type),
      do: %{status_code: 200, headers: [{"content-length", to_string(size)}, {"content-type", type}]}

    defp complete_with(body, name, type, declared_size) do
      {:ok, upload} = Direct.presign(:image, "default", %{name: name, size: declared_size, type: type})

      expect(Client.Mock, :head_object, fn _, _, _ -> {:ok, head_reply(declared_size, type)} end)
      expect(Client.Mock, :get_object, fn _, _, _ -> {:ok, %{status_code: 200, body: body}} end)

      Oban.Testing.with_testing_mode(:manual, fn -> Direct.complete(upload.ref) end)
    end

    test "a body larger than the object the HEAD saw is refused", %{put_config: put} = ctx do
      put.(%{size_limit: 100})

      assert {:error, _} = complete_with(File.read!(@jpg), "a.jpg", "image/jpeg", 50)
      assert stored(ctx) == []
    end

    test "a body that is not what was declared is refused", %{put_config: put} = ctx do
      put.(%{})
      body = "<html><body></body></html>"

      assert {:error, _} = complete_with(body, "a.jpg", "image/jpeg", byte_size(body))
      assert stored(ctx) == []
    end

    test "an SVG is stored with its declared size", %{put_config: put} do
      put.(%{})

      assert {:ok, image} = complete_with(@svg, "a.svg", "image/svg+xml", byte_size(@svg))
      assert {image.width, image.height} == {10, 20}
    end

    test "a jpeg keeps working", %{put_config: put} do
      put.(%{})
      body = File.read!(@jpg)

      assert {:ok, %{status: :unprocessed}} = complete_with(body, "a.jpg", "image/jpeg", byte_size(body))
    end
  end

  describe "svg_size/1 creates no atoms" do
    test "a file of unique names leaves the atom table as it was", %{dir: dir} do
      # Warm the code paths, so loading a module does not count as growth
      Utils.svg_size(temp(dir, @svg))

      prefix = "svgatom#{System.unique_integer([:positive])}"
      names = for n <- 1..2_000, do: "#{prefix}n#{n}"
      attributes = Enum.map_join(names, " ", &~s(#{&1}a="1"))
      elements = Enum.map_join(names, "", &"<#{&1}/>")
      path = temp(dir, ~s(<svg width="3" height="4" #{attributes}>#{elements}</svg>))

      before = :erlang.system_info(:atom_count)
      assert Utils.svg_size(path) == %{width: 3, height: 4}
      assert :erlang.system_info(:atom_count) == before

      assert_raise ArgumentError, fn -> String.to_existing_atom("#{prefix}n1") end
      assert_raise ArgumentError, fn -> String.to_existing_atom("#{prefix}n1a") end
    end

    test "uploading such a file leaves the atom table as it was", %{dir: dir, user: user} do
      Uploads.store_upload(meta(temp(dir, @svg)), entry("warm.svg", "image/svg+xml"), image_cfg(), user)

      prefix = "svgatom#{System.unique_integer([:positive])}"
      elements = Enum.map_join(1..2_000, "", &"<#{prefix}n#{&1}/>")
      path = temp(dir, ~s(<svg width="3" height="4">#{elements}</svg>))

      before = :erlang.system_info(:atom_count)
      assert {:ok, _} = Uploads.store_upload(meta(path), entry("names.svg", "image/svg+xml"), image_cfg(), user)
      assert :erlang.system_info(:atom_count) == before
    end
  end
end
