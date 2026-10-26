defmodule Brando.Worker.ImageUploaderTest do
  # An image is on the CDN (`cdn: true`) only once every one of its files is:
  # a size that failed would otherwise be served from a bucket without it.
  # Until then its files stay in the media folder, even with
  # `keep_local_copy: false`, and the image is served from there.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

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

  defp image_with_files(dir, sizes, formats \\ [:jpg]) do
    root = Storage.current_media_root()
    paths = [Path.join(dir, "original.jpg") | Enum.map(sizes, &Path.join([dir, &1, "original.jpg"]))]

    for path <- paths, format <- formats do
      file = Path.join(root, Brando.Utils.change_extension(path, to_string(format)))
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, "IMAGE")
    end

    Factory.insert(:image,
      path: hd(paths),
      sizes: Map.new(Enum.zip(sizes, tl(paths))),
      formats: formats,
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

  # `<picture>` has a source per format
  test "each size goes up in each of the image's formats", %{dir: dir} do
    image = image_with_files(dir, ["thumb"], [:jpg, :webp])

    {:ok, _job} = Brando.CDN.queue_upload(image, :system, [])

    assert Repo.get!(Image, image.id).cdn

    assert Enum.sort(FakeS3.completed_keys()) ==
             Enum.sort([
               "/bucket/media/#{dir}/original.jpg",
               "/bucket/media/#{dir}/thumb/original.jpg",
               "/bucket/media/#{dir}/thumb/original.webp"
             ])
  end

  # Processed again while it ran (a new crop): the job queued then uploads
  # the new files, so this one neither marks the image nor removes them.
  test "an upload with another one waiting leaves the image to it", %{dir: dir} do
    image = image_with_files(dir, ["thumb"])

    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, running} = Brando.CDN.queue_upload(image, :system, [])

      {:ok, _waiting} =
        %{image_id: image.id, config_target: image.config_target, user_id: nil, field_full_path: [], files: 2}
        |> Brando.Tenant.Job.attach()
        |> Brando.Worker.ImageUploader.new(tags: ["image_upload_#{image.id}"])
        |> Oban.insert()

      assert :ok = Brando.Worker.ImageUploader.perform(Repo.get!(Oban.Job, running.id))
    end)

    refute Repo.get!(Image, image.id).cdn
    assert local?(image.path)
  end

  # A processor that fails to write a format logs it and goes on
  test "a size missing in another format is skipped", %{dir: dir} do
    image = image_with_files(dir, ["thumb"])
    image = image |> Ecto.Changeset.change(formats: [:jpg, :avif]) |> Repo.update!()

    {:ok, _job} = Brando.CDN.queue_upload(image, :system, [])

    assert Repo.get!(Image, image.id).cdn
    refute Enum.any?(FakeS3.keys(), &String.ends_with?(&1, ".avif"))
  end

  defp processing_job(image, state) do
    job =
      %{image_id: image.id, user_id: nil, field_full_path: [], config_target: image.config_target}
      |> Brando.Tenant.Job.attach()
      |> Brando.Worker.ImageProcessor.new()
      |> Oban.insert!()

    Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [state: state])
    job
  end

  # Its files are changing, and processing queues an upload when it is done
  test "an upload waits for the image's processing to finish", %{dir: dir} do
    image = image_with_files(dir, ["thumb"])

    Oban.Testing.with_testing_mode(:manual, fn ->
      processing = processing_job(image, "executing")
      {:ok, upload} = Brando.CDN.queue_upload(image, :system, [])

      assert {:snooze, _} = Brando.Worker.ImageUploader.perform(Repo.get!(Oban.Job, upload.id))
      assert FakeS3.keys() == []

      Repo.update_all(from(j in Oban.Job, where: j.id == ^processing.id), set: [state: "completed"])
      assert {:ok, _} = Brando.Worker.ImageUploader.perform(Repo.get!(Oban.Job, upload.id))
    end)

    assert Repo.get!(Image, image.id).cdn
  end

  # A job that snoozes never runs out of attempts
  test "an upload stops waiting for processing after a while", %{dir: dir} do
    image = image_with_files(dir, ["thumb"])

    Oban.Testing.with_testing_mode(:manual, fn ->
      _stuck = processing_job(image, "executing")
      {:ok, upload} = Brando.CDN.queue_upload(image, :system, [])
      job = %{Repo.get!(Oban.Job, upload.id) | meta: %{"snoozed" => 120}}
      assert {:ok, _} = Brando.Worker.ImageUploader.perform(job)
    end)

    assert Repo.get!(Image, image.id).cdn
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

      assert {:error, _} = Brando.Worker.ImageUploader.perform(Repo.get!(Oban.Job, job.id))
      refute Repo.get!(Image, image.id).cdn
      assert local?(image.path)

      :persistent_term.put({FakeS3, :flaky}, false)
      assert {:ok, _} = Brando.Worker.ImageUploader.perform(Repo.get!(Oban.Job, job.id))
    end)

    assert Repo.get!(Image, image.id).cdn
    refute local?(image.path)
  end

  # Before, each file had a job. The first to run after an upgrade queues one
  # for the image, which doesn't upload again what an earlier per-file job
  # uploaded and removed (`keep_local_copy: false`).
  test "per-file jobs queued before an upgrade upload the rest of the image once", %{dir: dir} do
    image = image_with_files(dir, ["thumb", "large"])
    [original | sizes] = Brando.CDN.image_keys(image)
    # The original's job ran before the upgrade
    File.rm!(Path.join(Storage.current_media_root(), image.path))

    Oban.Testing.with_testing_mode(:manual, fn ->
      [first | _] =
        for key <- sizes do
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

      assert :ok = Brando.Worker.ImageUploader.perform(Repo.get!(Oban.Job, first.id))

      # (`perform/1` leaves the job's row `available`, which the new job's
      # queueing deletes; a running one is `executing`, which stays)
      [whole] = for job <- Repo.all(Oban.Job), "image_upload_#{image.id}" in job.tags, job.id != first.id, do: job
      assert whole.args["files"] == 3
      assert {:ok, _} = Brando.Worker.ImageUploader.perform(whole)
    end)

    assert Repo.get!(Image, image.id).cdn
    assert FakeS3.completed_keys() == Enum.map(sizes, &"/bucket/#{&1}")
    refute "/bucket/#{original}" in FakeS3.keys()
  end
end
