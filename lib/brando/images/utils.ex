defmodule Brando.Images.Utils do
  @moduledoc """
  General utilities pertaining to the Images module
  """
  @type id :: binary | integer
  @type image_struct :: Brando.Images.Image.t()
  @type user :: Brando.Users.User.t() | :system

  alias Brando.Image
  import Brando.Utils

  @doc """
  Goes through `image` then passes to `delete_media/2` for removal

  ## Example:

      delete_original_and_sized_images(image)

  """
  @spec delete_original_and_sized_images(Image.t()) :: {:ok, Image.t()}
  def delete_original_and_sized_images(image) do
    delete_sized_images(image)
    delete_media(Map.get(image, :path))

    {:ok, image}
  end

  @doc """
  Delete sizes associated with `image`, but keep original.
  """
  @spec delete_sized_images(Image.t()) :: any
  def delete_sized_images(nil), do: nil

  def delete_sized_images(%{formats: formats, sizes: sizes} = image) do
    for {_size, file} <- sizes do
      delete_media(file)
    end
  end

  @doc """
  Deletes `file` after joining it with `media_path`
  # TODO: Check for `cdn` key and handle
  """
  @spec delete_media(file_name :: binary) :: any
  def delete_media(nil), do: nil
  def delete_media(""), do: nil

  def delete_media(file) do
    file = Path.join([Brando.config(:media_path), file])
    File.rm(file)
  end

  @doc """
  Splits `file` with `split_path/1`, adds `size` to the path before
  concatenating it with the filename.

  ## Example

      iex> get_sized_path("test/dir/filename.jpg", :thumb)
      "test/dir/thumb/filename.jpg"

      iex> get_sized_path("test/dir/filename.jpeg", :thumb)
      "test/dir/thumb/filename.jpg"

  """
  @spec get_sized_path(path :: binary, size :: atom | binary, type :: atom | nil) ::
          binary
  def get_sized_path(path, size, type \\ nil)

  def get_sized_path(path, :original, _type) do
    path
  end

  def get_sized_path(path, size, type) when is_binary(size) do
    {dir, filename} = split_path(path)
    filename = ensure_correct_extension(filename, type)
    Path.join([dir, size, filename])
  end

  def get_sized_path(file, size, type) when is_atom(size),
    do: get_sized_path(file, Atom.to_string(size), type)

  @doc """
  Adds `size` to the path before

  ## Example

      iex> get_sized_dir("test/dir/filename.jpg", :thumb)
      "test/dir/thumb"

  """
  @spec get_sized_dir(path :: binary, size :: atom | binary) :: binary
  def get_sized_dir(path, size) when is_binary(size) do
    {dir, _} = split_path(path)
    Path.join([dir, size])
  end

  def get_sized_dir(file, size) when is_atom(size), do: get_sized_dir(file, Atom.to_string(size))

  @doc """
  Returns image type atom.
  """
  @spec image_type(filename :: binary) :: atom | no_return()
  def image_type(filename) do
    filename
    |> Path.extname()
    |> String.downcase()
    |> do_image_type()
  end

  defp do_image_type(".jpg"), do: :jpg
  defp do_image_type(".jpeg"), do: :jpg
  defp do_image_type(".png"), do: :png
  defp do_image_type(".gif"), do: :gif
  defp do_image_type(".bmp"), do: :bmp
  defp do_image_type(".tif"), do: :tiff
  defp do_image_type(".tiff"), do: :tiff
  defp do_image_type(".psd"), do: :psd
  defp do_image_type(".svg"), do: :svg
  defp do_image_type(".crw"), do: :crw
  defp do_image_type(".webp"), do: :webp
  defp do_image_type(".avif"), do: :avif
  defp do_image_type(ext), do: raise("Unknown image type #{ext}")

  @doc """
  Return joined path of `file` and the :media_path config option
  as set in your app's config.exs.
  """

  @spec media_path() :: binary
  @spec media_path(nil | binary) :: binary
  def media_path, do: Brando.config(:media_path)
  def media_path(nil), do: Brando.config(:media_path)
  def media_path(file), do: Path.join([Brando.config(:media_path), file])
end
