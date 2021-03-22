defmodule Brando.Files.Upload.Field do
  import Brando.Upload
  alias Brando.Utils
  alias Brando.Images

  @doc """
  Handles the upload by starting a chain of operations on the plug.
  This function handles upload when we have an file field on a schema.

  ## Parameters

    * `name`:
    * `plug`: a Plug.Upload struct.
    * `cfg`: the field's cfg from has_image_field

  """
  @spec handle_upload(atom, Plug.Upload.t() | map, Brando.Type.FileConfig.t()) ::
          {:ok, {:handled, Brando.Type.File}}
          | {:ok, {:unhandled, atom, term}}
          | {:error, {atom, {:error, binary}}}
  def handle_upload(name, %Plug.Upload{} = plug, cfg) do
    with {:ok, upload} <- process_upload(plug, cfg),
         {:ok, field} <- create_struct(upload) do
      {:ok, {:handled, name, field}}
    else
      err -> {:error, {name, handle_upload_error(err)}}
    end
  end

  def handle_file_upload(name, file, _) do
    {:ok, {:unhandled, name, file}}
  end

  @doc """
  Creates a File{} struct pointing to the copied uploaded file.
  """
  @spec create_struct(Brando.Upload.t()) :: {:ok, Brando.Type.File.t()}
  def create_struct(%Brando.Upload{
        plug: %{uploaded_file: file, content_type: mime_type},
        cfg: cfg
      }) do
    {_, filename} = Utils.split_path(file)
    upload_path = Map.get(cfg, :upload_path)

    file_path = Path.join([upload_path, filename])

    file_stat =
      file_path
      |> Images.Utils.media_path()
      |> File.stat!()

    file_struct =
      %Brando.Type.File{}
      |> Map.put(:path, file_path)
      |> Map.put(:size, file_stat.size)
      |> Map.put(:mimetype, mime_type)

    {:ok, file_struct}
  end
end
