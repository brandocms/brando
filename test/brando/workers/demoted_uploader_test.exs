defmodule Brando.Worker.DemotedUploaderTest do
  # Sizes, the CDN copy and a provider's status report are the system's work
  # on an asset someone uploaded. They finish when the uploader has been
  # demoted to User (or lost their access) after queueing them.
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Factory
  alias Brando.Images
  alias Brando.Images.Image
  alias Brando.Users.User
  alias Brando.Worker.FileUploader
  alias Brando.Worker.ImageProcessor

  # The S3 endpoint, answering a multipart upload; only the socket is replaced
  defmodule S3Stub do
    @moduledoc false
    @behaviour ExAws.Request.HttpClient

    @impl true
    def request(:post, url, _body, _headers, _opts) do
      if String.contains?(url, "uploads") and not String.contains?(url, "uploadId"),
        do: {:ok, %{status_code: 200, headers: [], body: initiated()}},
        else: {:ok, %{status_code: 200, headers: [], body: completed()}}
    end

    def request(:put, _url, _body, _headers, _opts),
      do: {:ok, %{status_code: 200, headers: [{"ETag", ~s("etag")}], body: ""}}

    def request(_method, _url, _body, _headers, _opts), do: {:ok, %{status_code: 200, headers: [], body: ""}}

    defp initiated,
      do:
        ~s(<?xml version="1.0"?><InitiateMultipartUploadResult><Bucket>testbucket</Bucket><Key>k</Key><UploadId>up1</UploadId></InitiateMultipartUploadResult>)

    defp completed,
      do:
        ~s(<?xml version="1.0"?><CompleteMultipartUploadResult><Location>l</Location><Bucket>testbucket</Bucket><Key>k</Key><ETag>"etag"</ETag></CompleteMultipartUploadResult>)
  end

  @cdn %{
    enabled: true,
    bucket: "testbucket",
    media_url: "https://testbucket.example.com",
    s3: %Brando.CDN.S3Config{access_key_id: "KEY", secret_access_key: "SECRET", region: "ams3"},
    keep_local_copy: true
  }

  setup do
    uploader = Factory.insert(:random_user, role: :editor)
    {:ok, uploader: uploader}
  end

  defp demote(user) do
    Brando.Repo.update_all(from(u in User, where: u.id == ^user.id), set: [role: :user])
  end

  # Gone for good, as the trash purge leaves a user deleted long enough ago
  defp delete(user) do
    Brando.Repo.delete_all(from(u in User, where: u.id == ^user.id))
  end

  defp put_media(name) do
    path = Path.join(["images", "demoted", name])
    file = Images.Utils.media_path(path)
    File.mkdir_p!(Path.dirname(file))
    File.cp!(Path.expand("../../fixtures/sample.png", __DIR__), file)
    on_exit(fn -> File.rm(file) end)
    path
  end

  defp stub_s3 do
    previous = Application.get_env(:ex_aws, :http_client)
    Application.put_env(:ex_aws, :http_client, S3Stub)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:ex_aws, :http_client, previous),
        else: Application.delete_env(:ex_aws, :http_client)
    end)
  end

  test "an image's sizes are made after its uploader is demoted", %{uploader: uploader} do
    path = put_media("sizes-#{System.unique_integer([:positive])}.png")
    image = Factory.insert(:image, path: path, sizes: %{}, status: :unprocessed, creator_id: uploader.id)
    demote(uploader)

    assert {:ok, _} =
             perform_job(ImageProcessor, %{
               "image_id" => image.id,
               "config_target" => "default",
               "user_id" => uploader.id,
               "field_full_path" => []
             })

    image = Brando.Repo.get!(Image, image.id)
    assert image.status == :processed
    assert image.sizes != %{}
  end

  # The user who queued the sizes (an admin recreating them, say) is gone;
  # the image is someone else's
  test "an image's sizes are made after the user who queued them is gone", %{uploader: uploader} do
    path = put_media("deleted-#{System.unique_integer([:positive])}.png")
    image = Factory.insert(:image, path: path, sizes: %{}, status: :unprocessed, creator_id: nil)
    delete(uploader)

    assert {:ok, _} =
             perform_job(ImageProcessor, %{
               "image_id" => image.id,
               "config_target" => "default",
               "user_id" => uploader.id,
               "field_full_path" => []
             })

    assert Brando.Repo.get!(Image, image.id).status == :processed
  end

  # An upload processed at once: the sizes are stored as the system, and the
  # completed callback is still the uploader's
  test "an upload processed at once for a demoted uploader still calls back with them", %{uploader: uploader} do
    path = put_media("now-#{System.unique_integer([:positive])}.png")
    image = Factory.insert(:image, path: path, sizes: %{}, status: :unprocessed, creator_id: uploader.id)
    test = self()
    {:ok, cfg} = Images.get_config_for("default")
    cfg = Map.put(cfg, :completed_callback, fn image, user -> send(test, {:completed, image.id, user}) end)
    demote(uploader)

    assert {:ok, %Image{status: :processed}} = Brando.Uploads.Store.process_upload(image, cfg, uploader)
    uploader_id = uploader.id
    image_id = image.id
    assert_received {:completed, ^image_id, %User{id: ^uploader_id}}
  end

  test "an image's CDN copy is marked done after its uploader is demoted", %{uploader: uploader} do
    original = Application.get_env(:brando, Brando.Images, [])
    default_config = original |> Keyword.get(:default_config, %{}) |> Map.new() |> Map.put(:cdn, @cdn)
    put_test_env(Brando.Images, Keyword.put(original, :default_config, default_config))
    stub_s3()

    path = put_media("cdn-#{System.unique_integer([:positive])}.png")
    image = Factory.insert(:image, path: path, sizes: %{}, status: :processed, creator_id: uploader.id)

    # Queued for the uploader, run once they are demoted: the job marks the
    # image done when it is the last of the image's uploads
    Oban.Testing.with_testing_mode(:manual, fn ->
      Brando.CDN.queue_upload(image, uploader)
      demote(uploader)
      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :default)
    end)

    assert Brando.Repo.get!(Image, image.id).cdn
  end

  test "a file's CDN copy is marked done after its uploader is demoted", %{uploader: uploader} do
    put_test_env(Brando.Files, cdn: @cdn)
    stub_s3()

    {:ok, cfg} = Brando.Files.get_config_for("default")
    filename = "file-#{System.unique_integer([:positive])}.png"
    file_path = Images.Utils.media_path(Path.join(cfg.upload_path, filename))
    File.mkdir_p!(Path.dirname(file_path))
    File.cp!(Path.expand("../../fixtures/sample.png", __DIR__), file_path)
    on_exit(fn -> File.rm(file_path) end)

    file =
      Brando.Repo.insert!(%Brando.Files.File{
        filename: filename,
        filesize: 1,
        mime_type: "image/png",
        config_target: "default",
        creator_id: uploader.id
      })

    demote(uploader)

    assert {:ok, _} =
             perform_job(FileUploader, %{
               "file_id" => file.id,
               "config_target" => "default",
               "user_id" => uploader.id,
               "field_full_path" => []
             })

    assert Brando.Repo.get!(Brando.Files.File, file.id).cdn
  end
end
