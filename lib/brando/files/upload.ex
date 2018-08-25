defmodule Brando.Files.Upload do
  @moduledoc """
  Processing function for file uploads.
  """
  alias Brando.Upload
  import Brando.Utils
  import Brando.Images.Utils, only: [media_path: 1]

  @doc """
  Creates a File{} struct pointing to the copied uploaded file.
  """
  @spec create_file_struct(Brando.Upload.t()) :: {:ok, Brando.Type.File.t()}
  def create_file_struct(%Upload{plug: %{uploaded_file: file, content_type: mime_type}, cfg: cfg}) do
    require Logger
    Logger.error("-- creating file struct")
    {_, filename} = split_path(file)
    upload_path = Map.get(cfg, :upload_path)

    file_path = Path.join([upload_path, filename])

    file_stat =
      file_path
      |> media_path()
      |> File.stat!()

    file_struct =
      %Brando.Type.File{}
      |> Map.put(:path, file_path)
      |> Map.put(:size, file_stat.size)
      |> Map.put(:mimetype, mime_type)

    {:ok, file_struct}
  end
end
