defmodule Brando.CDN do
  @moduledoc """
  Interfacing with Content Delivery Networks
  """

  alias ExAws.S3
  alias ExAws.S3.Upload

  @type upload_error :: {:error, {:cdn, {:upload, :failed}}}

  def config(key), do: Keyword.get(Brando.config(Brando.CDN), key, nil)

  @doc """

  """
  @spec upload_file(binary) :: {:ok, cdn_key :: binary} | upload_error
  def upload_file(file_path) do
    s3_bucket = config(:bucket)
    s3_key = Path.join(["media", file_path])

    require Logger
    Logger.error(inspect(s3_bucket, pretty: true))
    Logger.error(inspect(file_path, pretty: true))

    #   file
    #   |> Upload.stream_file()
    #   |> S3.upload(s3_bucket, file_path, s3_options)
    #   |> ExAws.request()
    #   |> case do
    #     {:ok, %{status_code: 200}} -> {:ok, file.file_name}
    #     {:ok, :done} -> {:ok, file.file_name}
    #     {:error, error} -> {:error, error}
    #   end
    # rescue
    #   e in ExAws.Error ->
    #     Logger.error(inspect e)
    #     Logger.error(e.message)
    #     {:error, :invalid_bucket}
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
