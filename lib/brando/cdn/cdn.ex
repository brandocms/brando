defmodule Brando.CDN do
  @moduledoc """
  Interfacing with Content Delivery Networks
  """

  alias ExAws.S3

  @type upload_error :: {:error, {:cdn, {:upload, :failed}}}

  def config(key), do: Keyword.get(Brando.config(Brando.CDN), key, nil)

  @doc """

  """
  @spec upload_file(file :: binary) :: {:ok, cdn_key :: binary} | upload_error
  def upload_file(_file) do
    # hepp
    {:ok, "hepp"}
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
