defmodule Brando.Field.File.Utils do
  @moduledoc """
  General utilities pertaining to the Files module
  """

  @doc """
  Goes through `file` then passing to `delete_media/2` for removal

  ## Example:

      delete_original(record, :cover)

  """
  @spec delete_original(Image.t(), atom) :: {:ok, Image.t()}
  def delete_original(file, key) do
    f = Map.get(file, key)

    if f do
      delete_media(Map.get(f, :path))
    end

    {:ok, file}
  end

  @doc """
  Deletes `file` after joining it with `media_path`
  """
  @spec delete_media(binary) :: no_return
  def delete_media(nil), do: nil
  def delete_media(""), do: nil

  def delete_media(file) do
    file = Path.join([Brando.config(:media_path), file])
    File.rm(file)
  end
end
