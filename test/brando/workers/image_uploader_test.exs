defmodule Brando.Worker.ImageUploaderTest do
  # An image is on the CDN (`cdn: true`) only once every one of its files is:
  # a size that failed would otherwise be served from a bucket without it.
  # Until then its files stay in the media folder, even with
  # `keep_local_copy: false`, and the image is served from there.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Images.Image
  alias Brando.Tenant.Storage

  # Answers ExAws's multipart upload calls, refusing every request for a key
  # that contains the failing marker
  defmodule FakeS3 do
    @behaviour ExAws.Request.HttpClient

    @impl true
    def request(method, url, _body, _headers, _opts) do
      %URI{path: path, query: query} = URI.parse(url)
      completes? = method == :post and String.contains?(query || "", "uploadId")
      Agent.update(__MODULE__, &[{if(completes?, do: :complete, else: method), path} | &1])

      cond do
        path =~ "failing" or (path =~ "flaky" and :persistent_term.get({__MODULE__, :flaky}, false)) ->
          {:ok, %{status_code: 403, headers: [], body: "<Error><Code>AccessDenied</Code></Error>"}}

        method == :post and String.starts_with?(query || "", "uploads") ->
          {:ok, %{status_code: 200, headers: [], body: initiated()}}

        method == :put ->
          {:ok, %{status_code: 200, headers: [{"ETag", "\"etag\""}], body: ""}}

        true ->
          {:ok, %{status_code: 200, headers: [], body: completed()}}
      end
    end

    defp initiated,
      do:
        "<InitiateMultipartUploadResult><Bucket>bucket</Bucket><Key>k</Key><UploadId>U1</UploadId></InitiateMultipartUploadResult>"

    defp completed,
      do:
        "<CompleteMultipartUploadResult><Location>l</Location><Bucket>bucket</Bucket><Key>k</Key><ETag>e</ETag></CompleteMultipartUploadResult>"

    def keys, do: __MODULE__ |> Agent.get(& &1) |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    # The objects whose upload completed (`POST ?uploadId=`), in order
    def completed_keys,
      do: __MODULE__ |> Agent.get(&Enum.reverse/1) |> Enum.filter(&match?({:complete, _}, &1)) |> Enum.map(&elem(&1, 1))
  end

  setup do
    start_supervised!(%{id: FakeS3, start: {Agent, :start_link, [fn -> [] end, [name: FakeS3]]}})

    ex_aws = Application.get_all_env(:ex_aws)
    images = Application.get_env(:brando, Brando.Images)

    cdn = %Brando.CDN.Config{
      enabled: true,
      bucket: "bucket",
      keep_local_copy: false,
      s3: %Brando.CDN.S3Config{access_key_id: "K", secret_access_key: "S", host: "s3.example.test", region: "r"}
    }

    Application.put_env(:ex_aws, :http_client, FakeS3)
    Application.put_env(:ex_aws, :retries, max_attempts: 1)
    Application.put_env(:brando, Brando.Images, Keyword.put(images, :cdn, cdn))

    on_exit(fn ->
      :persistent_term.erase({FakeS3, :flaky})
      Application.put_env(:brando, Brando.Images, images)
      for {key, _} <- Application.get_all_env(:ex_aws), do: Application.delete_env(:ex_aws, key)
      for {key, value} <- ex_aws, do: Application.put_env(:ex_aws, key, value)
    end)

    dir = "images/cdn-upload/#{System.unique_integer([:positive])}"
    on_exit(fn -> File.rm_rf(Path.join(Storage.current_media_root(), dir)) end)
    {:ok, dir: dir}
  end

  defp image_with_files(dir, sizes) do
    root = Storage.current_media_root()
    paths = [Path.join(dir, "original.jpg") | Enum.map(sizes, &Path.join([dir, &1, "original.jpg"]))]

    for path <- paths do
      File.mkdir_p!(Path.dirname(Path.join(root, path)))
      File.write!(Path.join(root, path), "JPEG")
    end

    Factory.insert(:image,
      path: hd(paths),
      sizes: Map.new(Enum.zip(sizes, tl(paths))),
      status: :processed,
      cdn: false
    )
  end

  defp local?(path), do: File.exists?(Path.join(Storage.current_media_root(), path))

  test "an image whose files are all uploaded is on the CDN, and its local files go", %{dir: dir} do
    image = image_with_files(dir, ["thumb", "large"])

    {:ok, _job} = Brando.CDN.queue_upload(image, :system, [])

    assert Repo.get!(Image, image.id).cdn
    assert Enum.sort(FakeS3.keys()) == Enum.sort(Enum.map(Brando.CDN.image_keys(image), &"/bucket/#{&1}"))
    refute Enum.any?([image.path | Map.values(image.sizes)], &local?/1)
  end

  test "an image with a size that fails to upload stays off the CDN, with its files", %{dir: dir} do
    image = image_with_files(dir, ["thumb", "failing"])

    {:ok, job} = Brando.CDN.queue_upload(image, :system, [])

    refute job.state == "completed"
    refute Repo.get!(Image, image.id).cdn
    assert Enum.all?([image.path | Map.values(image.sizes)], &local?/1)
  end

  test "an image whose path leaves the media root is cancelled, not uploaded" do
    image = Factory.insert(:image, path: "../../../etc/passwd", sizes: %{}, status: :processed, cdn: false)

    {:ok, job} = Brando.CDN.queue_upload(image, :system, [])

    assert job.state == "cancelled"
    refute Repo.get!(Image, image.id).cdn
    assert FakeS3.keys() == []
  end

  test "a retry after a failed file puts the image on the CDN", %{dir: dir} do
    image = image_with_files(dir, ["thumb", "flaky"])
    :persistent_term.put({FakeS3, :flaky}, true)

    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, job} = Brando.CDN.queue_upload(image, :system, [])

      assert {:error, _} = Oban.Testing.perform_job(Brando.Worker.ImageUploader, job.args, repo: Brando.Repo.repo())
      refute Repo.get!(Image, image.id).cdn
      assert local?(image.path)

      :persistent_term.put({FakeS3, :flaky}, false)
      assert {:ok, _} = Oban.Testing.perform_job(Brando.Worker.ImageUploader, job.args, repo: Brando.Repo.repo())
    end)

    assert Repo.get!(Image, image.id).cdn
    refute local?(image.path)
  end

  # Before, each file had a job: the first to run uploads the image and
  # deletes the rest, which would each upload it again.
  test "per-file jobs queued before upload the image once", %{dir: dir} do
    image = image_with_files(dir, ["thumb", "large"])

    Oban.Testing.with_testing_mode(:manual, fn ->
      [first | _] =
        for key <- Brando.CDN.image_keys(image) do
          %{
            src_key: key,
            dest_key: key,
            image_id: image.id,
            config_target: image.config_target,
            user_id: nil,
            field_full_path: []
          }
          |> Brando.Tenant.Job.attach()
          |> Brando.Worker.ImageUploader.new(tags: ["image_upload_#{image.id}"])
          |> Oban.insert!()
        end

      assert {:ok, _} = Oban.Testing.perform_job(Brando.Worker.ImageUploader, first.args, repo: Brando.Repo.repo())
      # (`perform_job/3` leaves the job it runs `available`; a running one is
      # `executing`, which stays)
      uploads = for job <- Repo.all(Oban.Job), "image_upload_#{image.id}" in job.tags, do: job.id
      assert uploads -- [first.id] == []
    end)

    assert Repo.get!(Image, image.id).cdn
    assert length(FakeS3.completed_keys()) == length(Brando.CDN.image_keys(image))
  end
end
