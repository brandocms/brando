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
