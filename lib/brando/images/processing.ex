defmodule Brando.Images.Processing do
  alias Brando.Image
  alias Brando.ImageSeries
  alias Brando.Images
  alias Brando.Progress
  alias Brando.Upload

  import Ecto.Query, only: [from: 2]

  @type id :: String.t() | integer
  @type user :: Brando.User.t() | :system
  @type image_schema :: Brando.Image.t()
  @type image_series_schema :: Brando.ImageSeries.t()
  @type image_struct :: Brando.Type.Image.t()
  @type image_kind :: :image | :image_series | :image_field

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
    {_, filename} = Brando.Utils.split_path(file)
    upload_path = Map.get(cfg, :upload_path)
    new_path = Path.join([upload_path, filename])

    new_path
    |> Images.Utils.media_path()
    |> Fastimage.size()
    |> case do
      {:ok, size_struct} ->
        image_struct =
          %Brando.Type.Image{}
          |> Map.put(:path, new_path)
          |> Map.put(:width, size_struct.width)
          |> Map.put(:height, size_struct.height)
          |> Map.put(:focal, focal)

        {:ok, image_struct}

      {:error, _} ->
        Progress.hide_progress(user)
        {:error, {:create_image_sizes, "Fastimage.size() failed."}}
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
    img_schema = Images.Utils.reset_optimized_flag(img_schema)
    Images.Utils.delete_sized_images(img_schema.image)

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
      case Images.Utils.check_image_paths(Image, image_series) do
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
          Images.Utils.delete_sized_images(img_field)

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
    Images.Utils.delete_sized_images(img_struct)

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
end
