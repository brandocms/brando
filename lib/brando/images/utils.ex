defmodule Brando.Images.Utils do
  @moduledoc """
  General utilities pertaining to the Images module

  TODO: Create a Processing module.
        Split out create_image_struct, create_image_sizes, etc...
  """
  @type id :: String.t() | integer
  @type user :: Brando.User.t() | :system
  @type image_schema :: Brando.Image.t()
  @type image_series_schema :: Brando.ImageSeries.t()
  @type image_struct :: Brando.Type.Image.t()
  @type image_kind :: :image | :image_series | :image_field

  import Brando.Utils
  import Ecto.Query, only: [from: 2]

  alias Brando.Image
  alias Brando.Images
  alias Brando.ImageSeries
  alias Brando.Progress
  alias Brando.Type
  alias Brando.Upload

  @doc """
  Create an image struct from upload, cfg and extra info
  """
  @spec create_image_struct(upload :: Upload.t(), user :: user) ::
          {:ok, image_struct}
          | {:error, {:create_image_sizes, any()}}
  def create_image_struct(
        %Upload{plug: %{uploaded_file: file}, cfg: cfg, extra_info: %{focal: focal}},
        user
      ) do
    {_, filename} = split_path(file)
    upload_path = Map.get(cfg, :upload_path)
    new_path = Path.join([upload_path, filename])

    try do
      image_info =
        new_path
        |> media_path()
        |> Mogrify.open()
        |> Mogrify.verbose()

      image_struct =
        %Brando.Type.Image{}
        |> Map.put(:path, new_path)
        |> Map.put(:width, image_info.width)
        |> Map.put(:height, image_info.height)
        |> Map.put(:focal, focal)

      {:ok, image_struct}
    rescue
      e in File.Error ->
        Progress.hide_progress(user)
        {:error, {:create_image_sizes, e}}

      e ->
        Progress.hide_progress(user)
        {:error, {:create_image_sizes, e}}
    end
  end

  @doc """
  Deletes all image's sizes and recreates them.
  """
  defmacro recreate_sizes_for(_, _, _) do
    raise """
    recreate_sizes_for(:image | :image_field | :image_series, _, _) has been deprecated.

    use

        recreate_sizes_for_image()
        recreate_sizes_for_image_series()

    instead.
    """
  end

  defmacro recreate_sizes_for(_, _, _, _) do
    raise """
    recreate_sizes_for(:image_field_record, _, _, _) has been deprecated.

    use

        recreate_sizes_for_image_field_record()

    instead.
    """
  end

  @spec recreate_sizes_for_image(
          image_schema :: image_schema,
          user :: user
        ) :: {:ok, image_schema} | {:error, Ecto.Changeset.t()}
  def recreate_sizes_for_image(img_schema, user \\ :system) do
    {:ok, img_cfg} = Images.get_series_config(img_schema.image_series_id)
    img_schema = reset_optimized_flag(img_schema)
    delete_sized_images(img_schema.image)

    with {:ok, operations} <-
           Images.Operations.create_operations(img_schema.image, img_cfg, user, img_schema.id),
         {:ok, [result]} <- Images.Operations.perform_operations(operations, user) do
      img_schema
      |> Image.changeset(:update, %{image: result.img_struct})
      |> Images.Optimize.optimize(:image, force: true)
      |> Brando.repo().update
    else
      err ->
        require Logger
        Logger.error("==> recreate_sizes_for(:image, ...) failed")
        Logger.error(inspect(err))
        err
    end
  end

  @spec recreate_sizes_for_image_series(
          image_series_id :: id,
          user :: user
        ) :: [{:ok, image_schema} | {:error, Ecto.Changeset.t()}]
  def recreate_sizes_for_image_series(image_series_id, user \\ :system) do
    query =
      from is in ImageSeries,
        preload: :images,
        where: is.id == ^image_series_id

    image_series = Brando.repo().one!(query)

    # check if the paths have changed. if so, reload series
    image_series =
      case check_image_paths(Image, image_series) do
        :changed -> Brando.repo().one!(query)
        :unchanged -> image_series
      end

    images = image_series.images

    # build operations
    operations =
      Enum.flat_map(images, fn img_schema ->
        img_schema.image
        |> Images.Operations.create_operations(image_series.cfg, user, img_schema.id)
        |> elem(1)
      end)

    {:ok, operation_results} = Images.Operations.perform_operations(operations, user)

    for result <- operation_results do
      img_schema = Enum.find(images, &(&1.id == result.id))
      Images.update_image(img_schema, %{image: result.img_struct})
    end
  end

  @doc """
  Recreates sizes for an image field.

  This applies to ALL records with matching schema/field
  """
  @spec recreate_sizes_for_image_field(
          schema :: any,
          field_name :: atom | String.t(),
          user_id :: id | atom
        ) :: [any()]
  def recreate_sizes_for_image_field(schema, field_name, user_id \\ :system) do
    rows = Brando.repo().all(schema)
    {:ok, cfg} = schema.get_image_cfg(field_name)

    operations =
      Enum.flat_map(rows, fn row ->
        img_field = Map.get(row, field_name)

        if img_field do
          delete_sized_images(img_field)

          img_field
          |> Images.Operations.create_operations(cfg, user_id, row.id)
          |> elem(1)
        else
          []
        end
      end)

    {:ok, operation_results} = Images.Operations.perform_operations(operations, user_id)

    for result <- operation_results do
      rows
      |> Enum.find(&(&1.id == result.id))
      |> Ecto.Changeset.change(Map.put(%{}, field_name, result.img_struct))
      |> Brando.Images.Optimize.optimize(field_name)
      |> Brando.repo().update
    end
  end

  @doc """
  Recreate sizes for image field record.
  Usually used when changing focal point

  ## Example:

      recreate_sizes_for_image_field_record(changeset, :cover, user)
  """
  @spec recreate_sizes_for_image_field_record(
          changeset :: Ecto.Changeset.t(),
          field_name :: atom,
          user :: user
        ) :: {:ok, Ecto.Changeset.t()} | {:error, Ecto.Changeset.t()}
  def recreate_sizes_for_image_field_record(changeset, field_name, user \\ :system) do
    img_struct = Ecto.Changeset.get_change(changeset, field_name)
    schema = changeset.data.__struct__
    delete_sized_images(img_struct)

    {:ok, cfg} = schema.get_image_cfg(field_name)

    with {:ok, operations} <- Images.Operations.create_operations(img_struct, cfg, user),
         {:ok, results} <- Images.Operations.perform_operations(operations, user) do
      updated_img_struct =
        results
        |> List.first()
        |> Map.get(:img_struct)

      {:ok, Ecto.Changeset.put_change(changeset, field_name, updated_img_struct)}
    else
      err ->
        require Logger
        Logger.error("==> recreate_sizes_for(:image_field_record, ...) failed")
        Logger.error(inspect(err))
        err
    end
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
  @spec delete_media(file_name :: String.t()) :: any
  def delete_media(nil), do: nil
  def delete_media(""), do: nil

  def delete_media(file) do
    file = Path.join([Brando.config(:media_path), file])
    optimized_file = Brando.Images.Utils.optimized_filename(file)
    File.rm(optimized_file)
    File.rm(file)
  end

  @doc """
  Splits `file` with `split_path/1`, adds `size` to the path before
  concatenating it with the filename.

  ## Example

      iex> get_sized_path("test/dir/filename.jpg", :thumb)
      "test/dir/thumb/filename.jpg"

  """
  @spec get_sized_path(path :: String.t(), size :: atom | String.t()) :: String.t()
  def get_sized_path(path, size) when is_binary(size) do
    {dir, filename} = split_path(path)
    Path.join([dir, size, filename])
  end

  def get_sized_path(file, size) when is_atom(size) do
    get_sized_path(file, Atom.to_string(size))
  end

  @doc """
  Adds `size` to the path before

  ## Example

      iex> get_sized_dir("test/dir/filename.jpg", :thumb)
      "test/dir/thumb"

  """
  @spec get_sized_dir(path :: String.t(), size :: atom | String.t()) :: String.t()
  def get_sized_dir(path, size) when is_binary(size) do
    {dir, _} = split_path(path)
    Path.join([dir, size])
  end

  def get_sized_dir(file, size) when is_atom(size) do
    get_sized_dir(file, Atom.to_string(size))
  end

  @doc """
  Reset image field's `:optimized` flag
  """
  @spec reset_optimized_flag(img_schema :: image_schema | image_struct) ::
          image_schema | image_struct
  def reset_optimized_flag(%Image{} = img_schema) do
    put_in(img_schema.image.optimized, false)
  end

  def reset_optimized_flag(%Type.Image{} = img_struct) do
    put_in(img_struct.optimized, false)
  end

  @doc """
  Returns image type atom.
  """
  @spec image_type(filename :: String.t()) :: atom
  def image_type(filename) do
    case String.downcase(Path.extname(filename)) do
      ".jpg" -> :jpeg
      ".jpeg" -> :jpeg
      ".png" -> :png
      ".gif" -> :gif
      ".bmp" -> :bmp
      ".tif" -> :tiff
      ".tiff" -> :tiff
      ".psd" -> :psd
      ".svg" -> :svg
      ".crw" -> :crw
      ".webp" -> :webp
    end
  end

  @doc """
  Return joined path of `file` and the :media_path config option
  as set in your app's config.exs.
  """

  @spec media_path() :: String.t()
  @spec media_path(nil | binary) :: String.t()
  def media_path, do: Brando.config(:media_path)
  def media_path(nil), do: Brando.config(:media_path)
  def media_path(file), do: Path.join([Brando.config(:media_path), file])

  @doc """
  Add `-optimized` between basename and ext of `file`.
  """
  @spec optimized_filename(file :: String.t()) :: String.t()
  def optimized_filename(file) do
    {path, filename} = split_path(file)
    {basename, ext} = split_filename(filename)

    Path.join([path, "#{basename}-optimized#{ext}"])
  end

  @doc """
  Delete all images depending on imageserie `series_id`
  """
  @spec delete_images_for(:image_series, series_id :: integer) :: :ok
  def delete_images_for(:image_series, series_id) do
    images =
      Brando.repo().all(
        from i in Image,
          where: i.image_series_id == ^series_id
      )

    for img <- images do
      delete_original_and_sized_images(img, :image)
      Brando.repo().delete!(img)
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
      Brando.repo().delete!(is)
    end
  end

  @doc """
  Checks that the existing images' path matches the config. these may differ
  when series has been renamed!
  """
  @spec check_image_paths(module, map | image_series_schema) :: :unchanged | :changed
  def check_image_paths(schema, image_series) do
    upload_path = image_series.cfg.upload_path

    {_, paths} =
      Enum.map_reduce(image_series.images, [], fn image, acc ->
        case check_image_path(schema, image, upload_path) do
          nil -> {image, acc}
          path -> {image, [path | acc]}
        end
      end)

    case paths do
      [] -> :unchanged
      _ -> :changed
    end
  end

  @spec check_image_path(module, map, String.t()) :: Ecto.Schema.t() | nil
  defp check_image_path(schema, image, upload_dirname) do
    image_path = image.image.path
    image_dirname = Path.dirname(image.image.path)
    image_basename = Path.basename(image.image.path)

    img_struct =
      do_check_image_path(image, image_path, image_dirname, image_basename, upload_dirname)

    if img_struct != nil do
      # store new image
      image
      |> schema.changeset(:update, %{image: img_struct})
      |> Brando.repo().update!
    end
  end

  defp do_check_image_path(_, _, ".", _, _) do
    # something is wrong, just return nil and don't move anything
    nil
  end

  @spec do_check_image_path(Ecto.Schema.t(), String.t(), String.t(), String.t(), String.t()) ::
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
          [String.t()] | []
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
