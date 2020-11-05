defmodule Brando.CDN do
  @moduledoc """
  Interfacing with Content Delivery Networks
  """
  require Logger
  alias Ecto.Changeset
  alias ExAws.S3
  alias ExAws.S3.Upload

  @type changeset :: Ecto.Changeset.t()
  @type upload_error :: {:error, {:cdn, {:upload, :failed}}}

  def config(key), do: Keyword.get(Brando.config(Brando.CDN), key, nil)

  def get_prefix, do: config(:media_url)

  @doc """

  """
  @spec upload_file(changeset, atom | binary, map) :: {:ok, :task_started}
  def upload_file(changeset, name, %Brando.Type.Image{} = field) do
    Task.start_link(__MODULE__, :do_upload_image, [{changeset, name, field}])
    {:ok, :task_started}
  end

  def do_upload_image({changeset, name, field}) do
    s3_bucket = config(:bucket)

    # upload original
    original_key = Path.join(["media", field.path])
    Logger.error("==> uploading `#{original_key}` to bucket `#{s3_bucket}`")
    s3_upload(s3_bucket, original_key)

    # upload individual sizes from sizes map
    for {_, path} <- field.sizes do
      sized_key = Path.join(["media", path])
      Logger.error("==> uploading `#{sized_key}` to bucket `#{s3_bucket}`")
      s3_upload(s3_bucket, sized_key)
    end

    changeset
    |> Changeset.put_change(name, put_in(field, [Access.key(:cdn)], true))
    |> Brando.repo().update
  end

  defp s3_upload(s3_bucket, s3_key) do
    s3_key
    |> Upload.stream_file()
    |> S3.upload(s3_bucket, s3_key, acl: :public_read)
    |> ExAws.request()
    |> case do
      {:ok, %{status_code: 200}} ->
        {:ok, s3_key}

      {:error, error} ->
        {:error, error}
    end
  rescue
    e in ExAws.Error ->
      Logger.error(inspect(e))
      Logger.error(e.message)
      {:error, :invalid_bucket}
  end

  @spec ensure_bucket_exists :: {:ok, {:bucket, :exists}} | :no_return
  def ensure_bucket_exists do
    bucket = config(:bucket)

    region = Map.fetch!(Application.get_env(:ex_aws, :s3), :region)

    bucket
    |> S3.get_bucket_location()
    |> ExAws.request()
    |> case do
      {:ok, _result} ->
        :ok

      {:error, _err} ->
        bucket
        |> ExAws.S3.put_bucket(region)
        |> ExAws.request()
        |> case do
          {:ok, _} ->
            :ok

          {:error, err} ->
            raise """

            ==> Bucket #{bucket} not found!"

            #{inspect(err, pretty: true)}

            """
        end
    end

    {:ok, {:bucket, :exists}}
  end

  @doc """
  Check if we use CDN in config
  """
  @spec enabled? :: boolean
  def enabled? do
    (Brando.config(Brando.CDN) && Brando.config(Brando.CDN)[:enabled]) || false
  end
end
