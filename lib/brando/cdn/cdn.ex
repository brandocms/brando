defmodule Brando.CDN do
  @moduledoc """
  Interfacing with Content Delivery Networks

  ## Configure

  Example configuration (in runtime.exs)

  ```elixir
  config :brando, Brando.Images, cdn: [
    enabled: true,
    media_url: System.get_env("BRANDO_CDN_FILES_MEDIA_URL") || "https://mybucket.ams3.digitaloceanspaces.com",
    bucket: System.get_env("BRANDO_CDN_FILES_BUCKET"),
    s3: %{
      access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
      scheme: "https://",
      host: "ams3.digitaloceanspaces.com",
      region: "ams3"
    }
  ]

  """
  require Logger
  import Ecto.Query
  alias Brando.Worker
  alias Ecto.Changeset
  alias ExAws.S3
  alias ExAws.S3.Upload

  @type changeset :: Ecto.Changeset.t()
  @type upload_error :: {:error, {:cdn, {:upload, :failed}}}

  def config(module, key) do
    cdn_config = Brando.config(module, :cdn) || []
    Keyword.get(cdn_config, key, nil)
  end

  def get_prefix(module), do: config(module, :media_url)

  def queue_upload(%Brando.Files.File{} = file, user, field_full_path \\ []) do
    args = %{
      file_id: file.id,
      config_target: file.config_target,
      user_id: user.id,
      field_full_path: field_full_path
    }

    Brando.repo().delete_all(
      from j in Oban.Job,
        where: fragment("? @> ?", j.args, ^args)
    )

    args
    |> Worker.FileUploader.new(replace_args: true)
    |> Oban.insert()
  end

  @doc """

  """
  @spec upload_file(any, any) :: {:ok, binary}
  def upload_file(%Brando.Files.File{} = file, config) do
    s3_bucket = config(Brando.Files, :bucket)

    # upload original
    local_path = config.upload_path
    filename = file.filename
    original_key = Path.join(["media", local_path, filename])
    Logger.error("==> uploading `#{original_key}` to bucket `#{s3_bucket}`")
    s3_config = Brando.CDN.config(Brando.Files, :s3) |> Map.to_list()

    case s3_upload(s3_bucket, original_key, s3_config) do
      {:ok, s3_key} ->
        Logger.error("==> uploaded as #{s3_key}")
        {:ok, s3_key}

      {:error, {:http_error, 403, err}} ->
        Logger.error("==> Error uploading file. 403 from AMAZON")
        Logger.error(inspect(err, pretty: true))
        {:error, "S3 Upload failed"}
    end
  end

  def do_upload_image({changeset, name, field}) do
    s3_bucket = config(Brando.Images, :bucket)

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

  defp s3_upload(s3_bucket, s3_key, s3_config \\ []) do
    s3_key
    |> Upload.stream_file()
    |> S3.upload(s3_bucket, s3_key, acl: :public_read)
    |> ExAws.request(s3_config)
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

  @spec ensure_bucket_exists(module) :: {:ok, {:bucket, :exists}} | :no_return
  def ensure_bucket_exists(module) do
    bucket = config(module, :bucket)
    s3_config = config(module, :s3)

    bucket
    |> S3.get_bucket_location()
    |> ExAws.request(s3_config)
    |> case do
      {:ok, _result} ->
        :ok

      {:error, _err} ->
        bucket
        |> ExAws.S3.put_bucket(s3_config.region)
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
  Check if we use CDN for the module
  """
  @spec enabled?(module) :: boolean
  def enabled?(module) when is_atom(module) do
    cdn_config = Brando.config(module, :cdn) || []
    !!Keyword.get(cdn_config, :enabled, false)
  rescue
    _ -> false
  end
end
