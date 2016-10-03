defmodule Brando.Files.Utils do
  @moduledoc """
  General utilities pertaining to the Images module
  """

  import Brando.Utils
  import Brando.Gettext
  import Ecto.Query, only: [from: 2]

  @doc """
  Goes through `image`, which is a model with a :sizes field
  then passing to `delete_media/2` for removal

  ## Example:

      delete_original_and_sized_images(record, :cover)

  """
  @spec delete_original(Image.t, atom) :: {:ok, Image.t}
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
  @spec delete_media(String.t) :: no_return
  def delete_media(nil), do: nil
  def delete_media(""), do: nil
  def delete_media(file) do
    file = Path.join([Brando.config(:media_path), file])
    File.rm(file)
  end
end
