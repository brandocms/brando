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
  def upload_file(file) do
    # hepp
  end

  @spec ensure_bucket_exists :: {:ok, {:bucket, :exists}} | {:error, {:bucket, any}}
  def ensure_bucket_exists do
    bucket = config(:bucket)

    bucket
    |> S3.get_bucket_location()
    |> ExAws.request()
    |> case do
      {:ok, _result} ->
        {:ok, {:bucket, :exists}}

      {:error, _err} ->
        bucket
        |> ExAws.S3.put_bucket("fra1")
        |> ExAws.request()
        |> case do
          {:ok, _} ->
            {:ok, {:bucket, :exists}}

          {:error, err} ->
            {:error, {:bucket, err}}
        end
    end
  end

  @doc """
  Check if we use CDN in config
  """
  @spec enabled? :: boolean
  def enabled? do
    (Brando.config(Brando.CDN) && Brando.config(Brando.CDN)[:enabled]) || false
  end
end
