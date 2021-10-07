defmodule Brando.Images.Utils do
  @moduledoc """
  General utilities pertaining to the Images module
  """
  @type id :: binary | integer
  @type image_kind :: :image | :image_series | :image_field
  @type image_schema :: Brando.Image.t()
  @type image_series_schema :: Brando.ImageSeries.t()
  @type image_struct :: Brando.Images.Image.t()
  @type user :: Brando.Users.User.t() | :system

  alias Brando.Image
  alias Brando.ImageSeries
  import Brando.Utils
  import Ecto.Query, only: [from: 2]

  @doc """
  Delete all physical images depending on imageserie `series_id`
  """
  @spec clear_media_for(:image_series, series_id :: integer) :: :ok
  def clear_media_for(:image_series, series_id) do
    images =
      Brando.repo().all(
        from i in Image,
          where: i.image_series_id == ^series_id
      )

    for img <- images, do: delete_original_and_sized_images(img, :image)

    :ok
  end

  @doc """
  Goes through `image`, which is a schema with an image_field
  then passing to `delete_media/2` for removal

  ## Example:

      delete_original_and_sized_images(record, :cover)

  """
  @spec delete_original_and_sized_images(schema :: term, key :: atom) :: {:ok, Image.t()}
  def delete_original_and_sized_images(image, key) do
    img = Map.get(image, key)

    if img do
      delete_sized_images(img)
      delete_media(Map.get(img, :path))
    end

    {:ok, image}
  end

  @doc """
  Delete sizes associated with `image`, but keep original.
  """
  @spec delete_sized_images(image_struct :: image_struct) :: any
  def delete_sized_images(nil), do: nil

  def delete_sized_images(image) do
    sizes = Map.get(image, :sizes)

    for {_size, file} <- sizes do
      delete_media(file)
    end
  end

  @doc """
  Deletes `file` after joining it with `media_path`
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

  @doc """
  Soft delete all images depending on imageserie `series_id`
  """
  @spec delete_images_for(:image_series, series_id :: integer) :: :ok
  def delete_images_for(:image_series, series_id) do
    images =
      Brando.repo().all(
        from i in Image,
          where: i.image_series_id == ^series_id
      )

    for img <- images do
      Brando.repo().soft_delete!(img)
    end

    :ok
  end

  @doc """
  Delete all imageseries dependant on `category_id`
  """
  @spec delete_series_for(:image_category, category_id :: integer) :: [
          image_series_schema | no_return
        ]
  def delete_series_for(:image_category, category_id) do
    image_series =
      Brando.repo().all(
        from m in ImageSeries,
          where: m.image_category_id == ^category_id
      )

    for is <- image_series do
      delete_images_for(:image_series, is.id)
      Brando.repo().soft_delete!(is)
    end
  end

  @doc """
  Checks that the existing images' path matches the config. these may differ
  when series has been renamed!
  """
  @spec check_image_paths(module, map | image_series_schema, user) :: :unchanged | :changed
  def check_image_paths(schema, image_series, user) do
    upload_path = image_series.cfg.upload_path

    {_, paths} =
      Enum.map_reduce(image_series.images, [], fn image, acc ->
        case check_image_path(schema, image, upload_path, user) do
          nil -> {image, acc}
          path -> {image, [path | acc]}
        end
      end)

    case paths do
      [] -> :unchanged
      _ -> :changed
    end
  end

  @spec check_image_path(module, map, binary, user) :: Ecto.Schema.t() | nil
  defp check_image_path(schema, image, upload_dirname, user) do
    image_path = image.image.path
    image_dirname = Path.dirname(image.image.path)
    image_basename = Path.basename(image.image.path)

    image_struct =
      do_check_image_path(image, image_path, image_dirname, image_basename, upload_dirname)

    if image_struct != nil do
      # store new image
      image
      |> schema.changeset(%{image: image_struct}, user)
      |> Brando.repo().update!
    end
  end

  defp do_check_image_path(_, _, ".", _, _) do
    # something is wrong, just return nil and don't move anything
    nil
  end

  @spec do_check_image_path(Ecto.Schema.t(), binary, binary, binary, binary) ::
          image_struct
  defp do_check_image_path(image, image_path, image_dirname, image_basename, upload_dirname) do
    media_path = Path.expand(Brando.config(:media_path))

    unless image_dirname == upload_dirname do
      source_file = Path.join(media_path, image_path)
      upload_path = Path.join(media_path, upload_dirname)
      dest_file = Path.join(upload_path, image_basename)
      new_image_path = Path.join(upload_dirname, image_basename)

      File.mkdir_p(upload_path)
      File.cp(source_file, dest_file)

      Map.put(image.image, :path, new_image_path)
    end
  end

  @doc """
  Gets orphaned image_series.
  """
  @spec get_orphaned_series([Ecto.Schema.t()], [Ecto.Schema.t()], Keyword.t()) ::
          [binary] | []
  def get_orphaned_series(categories, series, opts) do
    starts_with = Keyword.fetch!(opts, :starts_with)
    ignored_paths = Keyword.get(opts, :ignored_paths, [])
    media_path = Path.expand(Brando.config(:media_path))
    series_paths = Enum.map(series, &Path.join(media_path, &1.cfg.upload_path))
    category_paths = Enum.map(categories, &Path.join(media_path, &1.cfg.upload_path))
    upload_paths = series_paths ++ category_paths

    check_upload_paths(upload_paths, media_path, starts_with, ignored_paths)
  end

  defp check_upload_paths(upload_paths, media_path, starts_with, ignored_paths) do
    case upload_paths do
      [] ->
        []

      _ ->
        path_to_check = Path.join(media_path, starts_with)
        full_ignored_paths = Enum.map(ignored_paths, &Path.join(path_to_check, &1))

        existing_category_paths = get_existing_category_paths(path_to_check, full_ignored_paths)
        existing_series_paths = get_existing_series_paths(existing_category_paths)
        existing_paths = existing_series_paths ++ existing_category_paths

        existing_paths -- upload_paths
    end
  end

  defp get_existing_category_paths(path_to_check, full_ignored_paths) do
    path_to_check
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.filter(&(&1 not in full_ignored_paths))
  end

  defp get_existing_series_paths(existing_category_paths) do
    existing_category_paths
    |> Enum.map(&Path.wildcard(Path.join(&1, "*")))
    |> List.flatten()
  end
end
