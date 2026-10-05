defmodule Brando.Uploads.DirectImageTest do
  @moduledoc """
  Images uploaded straight from a browser to the bucket, through
  `Brando.Uploads.Direct` — the path a site's own form takes for its
  visitors, without an admin user or the UploadManager.

  What it pins:

    * an image field whose CDN config is direct now presigns instead of
      always going through the server, and one that is not still does not;
    * completing fetches the original back, creates an unprocessed `Image`
      row on it and queues processing — run as `:system`, so no admin user is
      needed anywhere in the job chain;
    * only what presign recorded is trusted: an unknown ref finalizes
      nothing, and the bucket's metadata must match;
    * `hidden_folder` files the image where the media library, the alt-text
      page and the pickers don't look.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Mox

  alias Brando.CDN.Client
  alias Brando.Images.Image
  alias Brando.Media.Folder
  alias Brando.Uploads
  alias Brando.Uploads.Direct

  @fixture Path.expand("../../fixtures/sample.jpg", __DIR__)

  @s3_config %Brando.CDN.S3Config{
    access_key_id: "TESTKEY",
    secret_access_key: "TESTSECRET",
    scheme: "https://",
    host: "ams3.digitaloceanspaces.com",
    region: "ams3"
  }

  @cdn %{
    enabled: true,
    direct: true,
    bucket: "testbucket",
    media_url: "https://testbucket.ams3.digitaloceanspaces.com",
    s3: @s3_config,
    keep_local_copy: false
  }

  setup :verify_on_exit!

  defp put_image_config(overrides) do
    original = Application.get_env(:brando, Brando.Images, [])

    config =
      Map.merge(
        %{
          upload_path: "images/visitors",
          allowed_mimetypes: ["image/jpeg"],
          random_filename: false,
          size_limit: 5_000_000,
          sizes: %{"thumb" => %{"size" => "150x150", "quality" => 70, "crop" => true}}
        },
        overrides
      )

    put_test_env(Brando.Images, Keyword.put(original, :default_config, config))
  end

  defp head_response(size, mime_type) do
    %{status_code: 200, headers: [{"content-length", to_string(size)}, {"content-type", mime_type}]}
  end

  defp meta(overrides \\ %{}) do
    Map.merge(%{name: "photo.jpg", size: File.stat!(@fixture).size, type: "image/jpeg"}, overrides)
  end

  describe "presign/4" do
    test "an image field with a direct CDN presigns a PUT under media/<upload_path>" do
      put_image_config(%{cdn: @cdn})

      assert {:ok, upload} = Direct.presign(:image, "default", meta())
      # Direct keys are always made unique: the bucket cannot be checked cheaply
      assert upload.key =~ ~r"^media/images/visitors/photo-\w+\.jpg$"
      assert upload.upload_url =~ "testbucket"
      assert upload.upload_url =~ "X-Amz-Signature"
      assert Uploads.get_pending_intent(upload.ref).asset_type == :image
    end

    test "without a direct CDN the image goes through the server, as before" do
      put_image_config(%{})

      assert {:ok, :server} = Direct.presign(:image, "default", meta())
    end

    test "a type the field does not take is refused before anything is presigned" do
      put_image_config(%{cdn: @cdn})

      assert {:error, message} = Direct.presign(:image, "default", meta(%{type: "image/png", name: "x.png"}))
      assert message =~ "Rejected"
      assert BrandoIntegration.Repo.all(Brando.Uploads.PendingIntent) == []
    end
  end

  describe "complete/2" do
    setup do
      on_exit(fn -> File.rm_rf(Path.join(Brando.Tenant.Storage.current_media_root(), "images/visitors")) end)
    end

    test "fetches the original, creates the image as :system and queues processing" do
      put_image_config(%{cdn: @cdn})
      body = File.read!(@fixture)
      {:ok, upload} = Direct.presign(:image, "default", meta())

      expect(Client.Mock, :head_object, fn "testbucket", key, _ ->
        assert key == upload.key
        {:ok, head_response(byte_size(body), "image/jpeg")}
      end)

      expect(Client.Mock, :get_object, fn "testbucket", key, _ ->
        assert key == upload.key
        {:ok, %{status_code: 200, body: body}}
      end)

      {:ok, image} =
        Oban.Testing.with_testing_mode(:manual, fn -> Direct.complete(upload.ref) end)

      assert %Image{status: :unprocessed, creator_id: nil} = image
      assert "media/" <> image.path == upload.key
      assert image.width > 0
      assert File.exists?(Path.join(Brando.Tenant.Storage.current_media_root(), image.path))

      # No admin user: the job records none, and the worker reads that as :system
      assert_enqueued(worker: Brando.Worker.ImageProcessor, args: %{image_id: image.id, user_id: nil})

      # Done with: the ref cannot be completed twice
      assert Uploads.get_pending_intent(upload.ref) == nil
      assert {:error, :not_found} = Direct.complete(upload.ref)
    end

    test "an object the bucket reports differently is not trusted" do
      put_image_config(%{cdn: @cdn})
      {:ok, upload} = Direct.presign(:image, "default", meta())

      expect(Client.Mock, :head_object, fn _, _, _ -> {:ok, head_response(12_000_000, "image/jpeg")} end)

      assert {:error, message} = Direct.complete(upload.ref)
      assert message =~ "size"
      assert BrandoIntegration.Repo.all(Image) == []
      # Kept, so a retry can complete it or the reaper can remove it
      assert Uploads.get_pending_intent(upload.ref)
    end

    test "an unknown ref completes nothing" do
      assert {:error, :not_found} = Direct.complete(Ecto.UUID.generate())
      assert {:error, :not_found} = Direct.complete("not-a-uuid")
    end
  end

  describe "hidden_folder" do
    setup do
      on_exit(fn -> File.rm_rf(Path.join(Brando.Tenant.Storage.current_media_root(), "images/visitors")) end)
    end

    test "files the image in a non-library folder the library queries leave out" do
      put_image_config(%{cdn: @cdn, hidden_folder: "visitors"})
      body = File.read!(@fixture)
      {:ok, upload} = Direct.presign(:image, "default", meta())

      expect(Client.Mock, :head_object, fn _, _, _ -> {:ok, head_response(byte_size(body), "image/jpeg")} end)
      expect(Client.Mock, :get_object, fn _, _, _ -> {:ok, %{status_code: 200, body: body}} end)

      {:ok, image} = Oban.Testing.with_testing_mode(:manual, fn -> Direct.complete(upload.ref) end)

      folder = BrandoIntegration.Repo.get!(Folder, image.folder_id)
      assert folder.name == "visitors"
      assert folder.library == false

      # The same folder for the next upload
      assert Brando.Media.Folders.hidden_folder_id("visitors") == folder.id

      library = Brando.Factory.insert(:image, %{status: :processed, path: "images/site/a.jpg"})
      {:ok, _} = Brando.Images.update_image(image, %{status: :processed}, :system)

      {:ok, listed} = Brando.Images.list_images(%{filter: %{library: true}})
      ids = Enum.map(listed, & &1.id)
      assert library.id in ids
      refute image.id in ids

      refute image.id in Enum.map(Brando.Images.AltText.missing(), & &1.id)
    end
  end

  describe "job users" do
    test ":system is recorded as nil and read back as :system" do
      assert Brando.Users.job_user_id(:system) == nil
      assert Brando.Users.job_user_id(%{id: 7}) == 7
      assert Brando.Users.get_job_user(nil) == {:ok, :system}
    end
  end
end
