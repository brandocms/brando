defmodule Brando.Images.Processing do
  require Logger

  alias Brando.Image
  alias Brando.ImageSeries
  alias Brando.Images
  alias Brando.Images.Focal
  alias Brando.Images.Operations
  alias BrandoAdmin.Progress
  alias Brando.Upload
  alias Brando.Users.User
  alias Ecto.Changeset

  @type changeset :: Changeset.t()
  @type id :: binary | integer
  @type image_schema :: Image.t()
  @type image_series_schema :: ImageSeries.t()
  @type image_kind :: :image | :image_series | :image_field
  @type upload :: Upload.t()
  @type user :: User.t()

  @default_focal %Focal{x: 50, y: 50}

  @doc """
  Create an image struct from upload, cfg and extra info
  """
  def create_image_type_struct(
        %Upload{upload_entry: %{uploaded_file: file}, cfg: cfg},
        user,
        extra_params \\ %{}
      ) do
    {_, filename} = Brando.Utils.split_path(file)
    upload_path = Map.get(cfg, :upload_path)
    new_path = Path.join([upload_path, filename])

    new_path
    |> Images.Utils.media_path()
    |> Fastimage.size()
    |> case do
      {:ok, %{width: width, height: height}} ->
        dominant_color = Images.Operations.Info.get_dominant_color(new_path)

        {:ok,
         %Images.Image{
           path: new_path,
           width: width,
           height: height,
           dominant_color: dominant_color,
           alt: Map.get(extra_params, :alt),
           title: Map.get(extra_params, :title),
           focal: Map.get(extra_params, :focal, @default_focal)
         }}

      {:error, _} ->
        Progress.hide(user)
        {:error, {:create_image_type_struct, "Fastimage.size() failed."}}
    end
  end

  @doc """
  Deletes all image's sizes and recreates them.
  """
  @spec recreate_sizes_for_image(image_schema, user) :: {:ok, image_schema} | {:error, changeset}
  def recreate_sizes_for_image(img_schema, user) do
    {:ok, img_cfg} = Images.get_series_config(img_schema.image_series_id)
    Images.Utils.delete_sized_images(img_schema.image)

    with {:ok, operations} <- Operations.create(img_schema.image, img_cfg, img_schema.id, user),
         {:ok, [result]} <- Operations.perform(operations, user) do
      img_schema
      |> Image.changeset(%{image: result.image_struct})
      |> Brando.repo().update
    else
      err ->
        Logger.error("""

        ==> recreate_sizes_for(:image, ...) failed
        #{inspect(err)}

        """)

        err
    end
  end

  @spec recreate_sizes_for_category(id, user) :: [{:ok, image_schema} | {:error, changeset}]
  def recreate_sizes_for_category(category_id, user) do
    {:ok, category} =
      Images.get_image_category(%{matches: [id: category_id], preload: [:image_series]})

    for is <- category.image_series do
      recreate_sizes_for_series(is.id, user)
    end
  end

  @spec recreate_sizes_for_series(id, user) :: [{:ok, image_schema} | {:error, changeset}]
  def recreate_sizes_for_series(series_id, user) do
    opts = %{matches: [id: series_id], preload: [:images]}
    {:ok, image_series} = Images.get_image_series(opts)

    # check if the paths have changed. if so, reload series
    {:ok, image_series} =
      case Images.Utils.check_image_paths(Image, image_series, user) do
        :changed -> Images.get_image_series(opts)
        :unchanged -> {:ok, image_series}
      end

    images = image_series.images

    # build operations
    operations =
      images
      |> Enum.filter(&(&1.deleted_at == nil))
      |> Enum.flat_map(fn img_schema ->
        {:ok, operations} =
          Operations.create(
            img_schema.image,
            image_series.cfg,
            img_schema.id,
            user
          )

        operations
      end)

    {:ok, operation_results} = Operations.perform(operations, user)

    for result <- operation_results do
      img_schema = Enum.find(images, &(&1.id == result.id))
      Images.update_image(img_schema, %{image: result.image_struct}, user)
    end
  end

  @doc """
  Recreates sizes for an image field.

  This applies to ALL records with matching schema/field
  """
  @spec recreate_sizes_for_image_field(
          schema :: any,
          field_name :: atom | binary,
          user
        ) :: [any()]
  def recreate_sizes_for_image_field(schema, field_name, user) do
    rows = Brando.repo().all(schema)

    %{cfg: cfg} = schema.__asset_opts__(field_name)

    operations =
      Enum.flat_map(rows, fn row ->
        img_field = Map.get(row, field_name)

        if img_field do
          Images.Utils.delete_sized_images(img_field)

          {:ok, operations} =
            Operations.create(
              img_field,
              cfg,
              row.id,
              user
            )

          operations
        else
          []
        end
      end)

    {:ok, operation_results} = Operations.perform(operations, user)

    for result <- operation_results do
      rows
      |> Enum.find(&(&1.id == result.id))
      |> Changeset.change(Map.put(%{}, field_name, result.image_struct))
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
          changeset :: changeset,
          field_name :: atom,
          user
        ) :: {:ok, changeset} | {:error, changeset}
  def recreate_sizes_for_image_field_record(changeset, field_name, user) do
    image_struct = Changeset.get_field(changeset, field_name)
    Images.Utils.delete_sized_images(image_struct)

    schema = changeset.data.__struct__

    %{cfg: cfg} = schema.__asset_opts__(field_name)

    with {:ok, operations} <- Operations.create(image_struct, cfg, nil, user),
         {:ok, results} <- Operations.perform(operations, user) do
      updated_image_struct =
        results
        |> List.first()
        |> Map.get(:image_struct)

      updated_changeset = Changeset.put_embed(changeset, field_name, updated_image_struct)

      {:ok, updated_changeset}
    else
      err ->
        Logger.error("""

        ==> recreate_sizes_for(:image_field_record, ...) failed"
        #{inspect(err)}

        """)

        err
    end
  end
end
