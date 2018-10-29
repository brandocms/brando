defmodule Brando.Images do
  @moduledoc """
  Context for Images.
  Handles uploads too.
  Interfaces with database
  """

  alias Brando.{ImageCategory, ImageSeries, Image}

  import Brando.Upload
  import Brando.Images.Utils,
    only: [
      create_image_sizes: 2,
      delete_original_and_sized_images: 2,
      recreate_sizes_for: 2
    ]
  import Brando.Utils.Schema, only: [put_creator: 2]
  import Ecto.Query

  @doc """
  Create new image
  """
  @spec create_image(%{binary => term} | %{atom => term}, Brando.User.t()) ::
          {:ok, Image.t()} | {:error, Keyword.t()}
  def create_image(params, user) do
    %Image{}
    |> put_creator(user)
    |> Image.changeset(:create, params)
    |> Brando.repo().insert
  end

  @doc """
  Update image
  """
  def update_image(schema, params) do
    schema
    |> Image.changeset(:update, params)
    |> Brando.repo().update
  end

  @doc """
  Get image.
  Raises on failure
  """
  def get_image!(id) do
    Brando.repo().get!(Image, id)
  end

  def get_category_id_by_slug(slug) do
    category = Brando.repo().get_by(ImageCategory, slug: slug)
    {:ok, category.id}
  end

  @doc """
  Updates the `schema`'s image JSON field with `title` and `credits`
  """
  def update_image_meta(schema, title, credits) do
    image =
      schema.image
      |> Map.put(:title, title)
      |> Map.put(:credits, credits)

    update_image(schema, %{"image" => image})
  end

  @doc """
  Delete `ids` from database
  Also deletes all dependent image sizes.
  """
  def delete_images(ids) when is_list(ids) do
    q = from m in Image, where: m.id in ^ids
    imgs = Brando.repo().all(q)

    for img <- imgs, do: {:ok, _} = delete_original_and_sized_images(img, :image)

    Brando.repo().delete_all(q)
  end

  @doc """
  Create image series
  """
  def create_series(data, user) do
    %ImageSeries{}
    |> put_creator(user)
    |> ImageSeries.changeset(:create, data)
    |> Brando.repo().insert()
  end

  @doc """
  Update image series.
  If slug or category has changed, we redo all the images
  """
  def update_series(id, data) do
    changeset =
      ImageSeries
      |> Brando.repo().get_by!(id: id)
      |> ImageSeries.changeset(:update, data)

    changeset
    |> Brando.repo().update()
    |> case do
      {:ok, inserted_series} ->
        # if slug is changed we recreate all the image sizes to reflect the new path
        if Ecto.Changeset.get_change(changeset, :slug) ||
             Ecto.Changeset.get_change(changeset, :image_category_id),
           do: recreate_sizes_for(:image_series, inserted_series.id)

        {:ok, Brando.repo().preload(inserted_series, :image_category)}

      error ->
        error
    end
  end

  @doc """
  Get all image series belonging to `cat_id`
  """
  def get_series_for(category_id: cat_id) do
    Brando.repo().all(
      from is in Brando.ImageSeries,
        where: is.image_category_id == ^cat_id
    )
  end

  @doc """
  Update series's config
  """
  def update_series_config(id, cfg) do
    res =
      ImageSeries
      |> Brando.repo().get_by!(id: id)
      |> Ecto.Changeset.change(%{cfg: cfg})
      |> Brando.repo().update

    case res do
      {:ok, series} ->
        recreate_sizes_for(:image_series, series.id)
        {:ok, series}

      err ->
        err
    end
  end

  @doc """
  Delete image series.
  Also deletes all images depending on the series and executes any callbacks
  """
  def delete_series(id) do
    with {:ok, series} <- get_series(id) do
      :ok = Brando.Images.Utils.delete_images_for(:image_series, series.id)
      series = Brando.repo().preload(series, :image_category)
      Brando.repo().delete!(series)

      {:ok, series}
    end
  end

  @doc """
  Create a new category
  """
  def create_category(data, user) do
    %ImageCategory{}
    |> put_creator(user)
    |> ImageCategory.changeset(:create, data)
    |> Brando.repo().insert()
  end

  @doc """
  Update category with `id` with `data`.
  If `slug` is changed in data, return {:propagate, category}, else return {:ok, category} or error
  """
  def update_category(id, data) do
    changeset =
      ImageCategory
      |> Brando.repo().get_by(id: id)
      |> ImageCategory.changeset(:update, data)

    changeset
    |> Brando.repo().update()
    |> case do
      {:ok, updated_category} ->
        if Ecto.Changeset.get_change(changeset, :slug) do
          {:propagate, updated_category}
        else
          {:ok, updated_category}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Get category by `id`
  """
  def get_category(id) do
    case Brando.repo().get(ImageCategory, id) do
      nil -> {:error, {:image_category, :not_found}}
      cat -> {:ok, cat}
    end
  end

  @doc """
  Get category's config
  """
  def get_category_config(id) do
    {:ok, category} = get_category(id)
    {:ok, category.cfg}
  end

  @doc """
  Get series's config
  """
  def get_series_config(id) do
    {:ok, series} = get_series(id)
    {:ok, series.cfg}
  end

  @doc """
  Get series by `id`
  """
  def get_series(id) do
    case Brando.repo().get(ImageSeries, id) do
      nil -> {:error, {:image_series, :not_found}}
      series -> {:ok, series}
    end
  end

  @doc """
  Get series by category slug and series slug
  """
  def get_series(cat_slug, s_slug) do
    images_query =
      from i in Image,
        order_by: [asc: i.sequence]

    series =
      Brando.repo().one(
        from is in ImageSeries,
          join: cat in assoc(is, :image_category),
          where: cat.slug == ^cat_slug and is.slug == ^s_slug,
          preload: [images: ^images_query]
      )

    case series do
      nil -> {:error, {:image_series, :not_found}}
      _ -> {:ok, series}
    end
  end

  def preload_series({:ok, series}) do
    series = Brando.repo().preload(series, [:images, :image_category])
    {:ok, series}
  end

  def list_categories do
    categories =
      Brando.repo().all(
        from category in ImageCategory,
          order_by: fragment("lower(?) ASC", category.name)
      )

    {:ok, categories}
  end

  @doc """
  Get all categories with preloaded series and images
  """
  def get_categories_with_series_and_images() do
    ImageCategory
    |> ImageCategory.with_image_series_and_images()
    |> Brando.repo().all
  end

  @doc """
  Update category's config
  """
  def update_category_config(id, cfg) do
    ImageCategory
    |> Brando.repo().get_by!(id: id)
    |> Ecto.Changeset.change(%{cfg: cfg})
    |> Brando.repo().update
  end

  @doc """
  Deletes category with id `id`.
  Also deletes all series depending on the category.
  """
  def delete_category(id) do
    category = Brando.repo().get_by!(ImageCategory, id: id)
    Brando.Images.Utils.delete_series_for(:image_category, category.id)
    Brando.repo().delete!(category)

    {:ok, category}
  end

  def image_series_count(category_id) do
    Brando.repo().one(
      from is in ImageSeries,
        select: count(is.id),
        where: is.image_category_id == ^category_id
    )
  end

  @doc """
  Get all portfolio image series that are orphaned
  """
  def get_all_orphaned_series() do
    categories = Brando.repo().all(ImageCategory)
    series = Brando.repo().all(ImageSeries)
    Brando.Images.Utils.get_orphaned_series(categories, series, starts_with: "images/site")
  end

  @doc """
  Checks `params` for Plug.Upload fields and passes them on.
  Fields in the `put_fields` map are added to the schema.
  Returns {:ok, schema} or raises
  """
  def check_for_uploads(params, current_user, cfg, put_fields \\ nil) do
    Enum.reduce(filter_plugs(params), [], fn named_plug, _ ->
      handle_upload(
        named_plug,
        &create_image_struct/2,
        current_user,
        put_fields,
        cfg
      )
    end)
  end

  @doc """
  Handles Plug.Upload for our modules.
  This is the handler for Brando.Image and Brando.Portfolio.Image
  """
  def handle_upload({name, plug}, process_fn, user, put_fields, cfg) do
    with {:ok, upload} <- process_upload(plug, cfg),
         {:ok, processed_field} <- process_fn.(upload, :system) do
      params = Map.put(put_fields, name, processed_field)
      create_image(params, user)
    else
      err -> handle_upload_error(err)
    end
  end

  @doc """
  Passes upload to create_image_sizes.
  """
  def create_image_struct(upload, user) do
    create_image_sizes(upload, user)
  end
end
