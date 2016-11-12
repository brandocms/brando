defmodule Brando.Files.Upload do
  @moduledoc """
  Processing function for file uploads.
  """
  alias Brando.Upload
  import Brando.Utils

  @doc """
  Creates a File{} struct pointing to the copied uploaded file.
  """
  @spec create_file_struct(Brando.Upload.t) :: {:ok, Brando.Type.File.t}
  def create_file_struct(%Upload{plug: %{uploaded_file: file}, cfg: cfg}) do
    {_, filename} = split_path(file)
    upload_path   = Map.get(cfg, :upload_path)

    file_struct =
      %Brando.Type.File{}
      |> Map.put(:path, Path.join([upload_path, filename]))

    {:ok, file_struct}
  end
end
