defmodule Brando.Images do
  @moduledoc """
  Context for Images.
  Handles uploads too.
  Interfaces with database
  """

  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Ecto.Changeset
  alias Brando.Image
  alias Brando.ImageCategory
  alias Brando.Images
  alias Brando.ImageSeries
  alias Brando.Users.User

  @type id :: binary | integer
  @type changeset :: changeset
  @type params :: map
  @type user :: User.t()

  @doc """
  Dataloader initializer
  """
  def data(_) do
    Dataloader.Ecto.new(
      Brando.repo(),
      query: &query/2
    )
  end

  @doc """
  Dataloader queries
  """
  def query(Image = query, _) do
    query
    |> where([i], is_nil(i.deleted_at))
    |> order_by([i], asc: i.sequence, desc: i.updated_at)
  end

  def query(ImageSeries = query, %{limit: limit, offset: offset}) do
    query
    |> order_by([is], asc: fragment("lower(?)", is.name))
    |> where([is], is_nil(is.deleted_at))
    |> limit([is], ^limit)
    |> offset([is], ^offset)
  end

  def query(queryable, _), do: queryable

  query :single, ImageCategory, do: fn query -> from(t in query, where: is_nil(t.deleted_at)) end

  matches ImageCategory do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id

      {:slug, slug}, query ->
        from t in query, where: t.slug == ^slug
    end
  end

  query :single, ImageSeries, do: fn query -> from(t in query, where: is_nil(t.deleted_at)) end

  matches ImageSeries do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id

      {:slug, slug}, query ->
        from t in query, where: t.slug == ^slug
    end
  end

  query :single, Image, do: fn query -> from(t in query, where: is_nil(t.deleted_at)) end

  matches Image do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id
    end
  end

  @doc """
  Create new image
  """
  @spec create_image(params, user) :: {:ok, Image.t()} | {:error, changeset}
  def create_image(params, user) do
    %Image{}
    |> Image.changeset(params, user)
    |> Brando.repo().insert
  end

  @doc """
  Update image
  """
  @spec update_image(schema :: Image.t(), params, user) :: {:ok, Image.t()} | {:error, changeset}
  def update_image(schema, params, user) do
    schema
    |> Image.changeset(params, user)
    |> Brando.repo().update
  end

  @doc """
  Get image.
  Raises on failure
  """
  def get_image!(id) do
    query =
      from t in Image,
        where: t.id == ^id and is_nil(t.deleted_at)

    Brando.repo().one!(query)
  end

  @doc """
  Get category id by slug
  """
  def get_category_id_by_slug(slug) do
    query =
      from t in ImageCategory,
        where: t.slug == ^slug and is_nil(t.deleted_at)

    case Brando.repo().one(query) do
      nil ->
        {:error, {:image_category, :not_found}}

      category ->
        {:ok, category.id}
    end
  end

  @doc """
  Get or create category id by slug
  """
  def get_or_create_category_id_by_slug(slug, user) do
    query =
      from t in ImageCategory,
        where: t.slug == ^slug and is_nil(t.deleted_at)

    case Brando.repo().one(query) do
      nil ->
        create_category(%{name: slug, slug: slug}, user)

      category ->
        {:ok, category}
    end
  end

  @spec update_image_meta(schema :: Image.t(), params, user) ::
          {:ok, Image.t()} | {:error, changeset}
  def update_image_meta(schema, params, user \\ :system)

  def update_image_meta(schema, %{focal: new_focal} = params, user) do
    image = Map.merge(schema.image, params)
    org_focal = Map.get(schema.image, :focal, %{})

    unless Map.equal?(org_focal, new_focal) do
      updated_schema = put_in(schema.image, image)
      _ = Images.Processing.recreate_sizes_for_image(updated_schema, user)
    end

    update_image(schema, %{"image" => image}, user)
  end

  def update_image_meta(schema, params, user) do
    image = Map.merge(schema.image, params)
    update_image(schema, %{"image" => image}, user)
  end

  @doc """
  Delete `ids` from database
  Also deletes all dependent image sizes.
  """
  def delete_images(ids) when is_list(ids) do
    q = from m in Image, where: m.id in ^ids
    Brando.repo().soft_delete_all(q)
  end

  @doc """
  Create image series
  """
  def create_series(data, user) do
    %ImageSeries{}
    |> ImageSeries.changeset(data, user)
    |> Brando.repo().insert()
  end

  @doc """
  Update image series.
  If slug or category has changed, we redo all the images
  """
  def update_series(id, data, user \\ :system) do
    query =
      from t in ImageSeries,
        where: t.id == ^id and is_nil(t.deleted_at)

    changeset =
      query
      |> Brando.repo().one!()
      |> ImageSeries.changeset(data)

    changeset
    |> Brando.repo().update()
    |> case do
      {:ok, inserted_series} ->
        # if slug is changed we recreate all the image sizes to reflect the new path
        if Changeset.get_change(changeset, :slug) ||
             Changeset.get_change(changeset, :image_category_id) ||
             Changeset.get_change(changeset, :cfg),
           do: Images.Processing.recreate_sizes_for_series(inserted_series.id, user)

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
        where: is.image_category_id == ^cat_id and is_nil(is.deleted_at)
    )
  end

  @doc """
  Update series's config
  """
  def update_series_config(id, cfg, user \\ :system) do
    query =
      from t in ImageSeries,
        where: t.id == ^id and is_nil(t.deleted_at)

    res =
      query
      |> Brando.repo().one!()
      |> Changeset.change(%{cfg: cfg})
      |> Brando.repo().update

    case res do
      {:ok, series} ->
        Images.Processing.recreate_sizes_for_series(series.id, user)
        {:ok, series}

      err ->
        err
    end
  end

  @doc """
  Delete image series.
  Also deletes all images depending on the series and executes any callbacks
  """
  def delete_series(nil), do: :ok

  def delete_series(id) do
    with {:ok, series} <- get_image_series(%{matches: [id: id]}) do
      :ok = Images.Utils.delete_images_for(:image_series, series.id)

      series
      |> Brando.repo().preload(:image_category)
      |> Brando.repo().soft_delete()
    end
  end

  @doc """
  Create a new category
  """
  def create_category(data, user) do
    %ImageCategory{}
    |> ImageCategory.changeset(data, user)
    |> Brando.repo().insert()
  end

  @doc """
  Update category with `id` with `data`.
  If `slug` is changed in data, return {:propagate, category}, else return {:ok, category} or error
  """
  def update_category(id, data, user \\ :system) do
    changeset =
      ImageCategory
      |> Brando.repo().get_by(id: id)
      |> ImageCategory.changeset(data, user)

    changeset
    |> Brando.repo().update()
    |> case do
      {:ok, updated_category} ->
        if Changeset.get_change(changeset, :slug) do
          {:propagate, updated_category}
        else
          {:ok, updated_category}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Get category by `slug`
  """
  def get_category_by_slug(slug) do
    query =
      from t in ImageCategory,
        where: t.slug == ^slug and is_nil(t.deleted_at)

    case Brando.repo().one(query) do
      nil -> {:error, {:image_category, :not_found}}
      cat -> {:ok, cat}
    end
  end

  @doc """
  Get category's config
  """
  def get_category_config(id) do
    {:ok, %{cfg: cfg}} = get_image_category(%{matches: [id: id]})
    {:ok, cfg}
  end

  @doc """
  Get category's config by slug
  """
  def get_category_config_by_slug(slug) do
    {:ok, %{cfg: cfg}} = get_category_by_slug(slug)
    {:ok, cfg}
  end

  @doc """
  Get series's config
  """
  def get_series_config(id) do
    case get_image_series(%{matches: [id: id]}) do
      {:ok, series} -> {:ok, series.cfg}
      err -> err
    end
  end

  @doc """
  Get series by category slug and series slug
  """
  def get_series_by_slug(c_slug, s_slug) do
    images_query =
      from i in Image,
        where: is_nil(i.deleted_at),
        order_by: [asc: i.sequence]

    series =
      Brando.repo().one(
        from is in ImageSeries,
          join: cat in assoc(is, :image_category),
          where:
            is.slug == ^s_slug and
              is_nil(is.deleted_at) and
              cat.slug == ^c_slug and
              is_nil(cat.deleted_at),
          preload: [:image_category, images: ^images_query]
      )

    case series do
      nil -> {:error, {:image_series, :not_found}}
      _ -> {:ok, series}
    end
  end

  def get_series_by_slug(s_slug) do
    images_query =
      from i in Image,
        where: is_nil(i.deleted_at),
        order_by: [asc: i.sequence]

    series =
      Brando.repo().one(
        from is in ImageSeries,
          join: cat in assoc(is, :image_category),
          where:
            is.slug == ^s_slug and
              is_nil(is.deleted_at),
          preload: [:image_category, images: ^images_query]
      )

    case series do
      nil -> {:error, {:image_series, :not_found}}
      _ -> {:ok, series}
    end
  end

  @doc """
  List categories by name
  """
  def list_categories do
    categories =
      Brando.repo().all(
        from category in ImageCategory,
          where: is_nil(category.deleted_at),
          order_by: fragment("lower(?) ASC", category.name)
      )

    {:ok, categories}
  end

  @doc """
  Update category's config
  """
  def update_category_config(id, cfg) do
    ImageCategory
    |> Brando.repo().get_by!(id: id)
    |> Changeset.change(%{cfg: cfg})
    |> Brando.repo().update
  end

  @doc """
  Propagate category's configuration to all dependent image series
  """
  @spec propagate_category_config(id) :: [any]
  def propagate_category_config(id) do
    category =
      ImageCategory
      |> Brando.repo().get_by!(id: id)
      |> Brando.repo().preload(:image_series)

    for series <- category.image_series do
      # ensure we keep the old upload_path, or else everything gets
      # written to the path specified in the category config!
      old_upload_path = series.cfg.upload_path
      new_config = put_in(category.cfg, [Access.key(:upload_path)], old_upload_path)

      series
      |> Changeset.change(%{cfg: new_config})
      |> Brando.repo().update
    end
  end

  @doc """
  Deletes category with id `id`.
  Also deletes all series depending on the category.
  """
  def delete_category(id) do
    category = Brando.repo().get_by!(ImageCategory, id: id)
    Images.Utils.delete_series_for(:image_category, category.id)
    Brando.repo().soft_delete(category)
  end

  @doc """
  Duplicate category with id `id`.
  """
  def duplicate_category(id, user) do
    cat = Brando.repo().get_by!(ImageCategory, id: id)

    params = %{
      name: cat.name <> " kopi",
      slug: cat.slug <> "-kopi",
      creator_id: user.id,
      cfg: Map.put(cat.cfg, :upload_path, "images/site/" <> cat.slug <> "-kopi")
    }

    cs = ImageCategory.changeset(%ImageCategory{}, params)
    Brando.repo().insert(cs)
  end

  @doc """
  Count image series in category (by id)
  """
  def count_image_series(category_id) do
    Brando.repo().one(
      from is in ImageSeries,
        select: count(is.id),
        where: is.image_category_id == ^category_id and is_nil(is.deleted_at)
    )
  end

  @doc """
  Get all portfolio image series that are orphaned
  """
  def get_all_orphaned_series do
    categories = Brando.repo().all(from t in ImageCategory, where: not is_nil(t.deleted_at))
    series = Brando.repo().all(from t in ImageSeries, where: not is_nil(t.deleted_at))
    Images.Utils.get_orphaned_series(categories, series, starts_with: "images/site")
  end

  @spec get_image_orientation(integer, integer) :: binary
  def get_image_orientation(width, height) do
    (width > height && "landscape") || (width == height && "square") ||
      "portrait"
  end

  @spec get_image_orientation(map) :: binary
  def get_image_orientation(%{width: width, height: height}) do
    (width > height && "landscape") || (width == height && "square") ||
      "portrait"
  end
end
