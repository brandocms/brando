defmodule Brando.Images do
  @moduledoc """
  Context for Images.
  Handles uploads too.
  Interfaces with database
  """

  use Brando.Web, :context

  alias Brando.Image
  alias Brando.ImageCategory
  alias Brando.Images
  alias Brando.ImageSeries

  import Brando.Utils.Schema, only: [put_creator: 2]
  import Ecto.Query

  @type user :: Brando.Users.User.t() | :system
  @type params :: %{binary => term} | %{atom => term}

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

  @doc """
  Create new image
  """
  @spec create_image(params :: params, user :: Brando.Users.User.t()) ::
          {:ok, Image.t()} | {:error, Ecto.Changeset.t()}
  def create_image(params, user) do
    %Image{}
    |> put_creator(user)
    |> Image.changeset(params)
    |> Brando.repo().insert
  end

  @doc """
  Update image
  """
  @spec update_image(schema :: Image.t(), params :: params) ::
          {:ok, Image.t()} | {:error, Ecto.Changeset.t()}
  def update_image(schema, params) do
    schema
    |> Image.changeset(params)
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

  @doc """
  Updates the `schema`'s image JSON field with `title` and `credits`
  """
  @spec update_image_meta(
          schema :: Brando.Image.t(),
          title :: any(),
          credits :: any(),
          focal :: Map.t(),
          user :: user
        ) :: {:ok, Brando.Image.t()} | {:error, Ecto.Changeset.t()}
  def update_image_meta(schema, title, credits, focal, user \\ :system) do
    image =
      schema.image
      |> Map.put(:title, title)
      |> Map.put(:credits, credits)
      |> Map.put(:focal, focal)

    unless Map.equal?(Map.get(schema.image, :focal, nil), focal) do
      updated_schema = put_in(schema.image, image)
      _ = Images.Processing.recreate_sizes_for_image(updated_schema, user)
    end

    update_image(schema, %{"image" => image})
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
    |> put_creator(user)
    |> ImageSeries.changeset(data)
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
        if Ecto.Changeset.get_change(changeset, :slug) ||
             Ecto.Changeset.get_change(changeset, :image_category_id) ||
             Ecto.Changeset.get_change(changeset, :cfg),
           do: Images.Processing.recreate_sizes_for_image_series(inserted_series.id, user)

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
      |> Ecto.Changeset.change(%{cfg: cfg})
      |> Brando.repo().update

    case res do
      {:ok, series} ->
        Images.Processing.recreate_sizes_for_image_series(series.id, user)
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
    with {:ok, series} <- get_series(id) do
      :ok = Images.Utils.delete_images_for(:image_series, series.id)
      series = Brando.repo().preload(series, :image_category)
      Brando.repo().soft_delete!(series)

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
    query =
      from t in ImageCategory,
        where: t.id == ^id and is_nil(t.deleted_at)

    case Brando.repo().one(query) do
      nil -> {:error, {:image_category, :not_found}}
      cat -> {:ok, cat}
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
    {:ok, category} = get_category(id)
    {:ok, category.cfg}
  end

  @doc """
  Get category's config by slug
  """
  def get_category_config_by_slug(slug) do
    {:ok, category} = get_category_by_slug(slug)
    {:ok, category.cfg}
  end

  @doc """
  Get series's config
  """
  def get_series_config(id) do
    case get_series(id) do
      {:ok, series} ->
        {:ok, series.cfg}

      err ->
        err
    end
  end

  @doc """
  Get series by `id`
  """
  def get_series(nil), do: {:error, {:image_series, :not_found}}

  def get_series(id) do
    query =
      from t in ImageSeries,
        where: t.id == ^id and is_nil(t.deleted_at)

    case Brando.repo().one(query) do
      nil -> {:error, {:image_series, :not_found}}
      series -> {:ok, series}
    end
  end

  @doc """
  Get series by category slug and series slug
  """
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
  Get series by category slug and series slug
  """
  def get_series(cat_slug, s_slug) do
    images_query =
      from i in Image,
        where: is_nil(i.deleted_at),
        order_by: [asc: i.sequence]

    series =
      Brando.repo().one(
        from is in ImageSeries,
          join: cat in assoc(is, :image_category),
          where:
            cat.slug == ^cat_slug and
              is.slug == ^s_slug and
              is_nil(is.deleted_at),
          preload: [images: ^images_query]
      )

    case series do
      nil -> {:error, {:image_series, :not_found}}
      _ -> {:ok, series}
    end
  end

  @doc """
  Preload images and category
  """
  def preload_series({:ok, series}) do
    series = Brando.repo().preload(series, [:images, :image_category])
    {:ok, series}
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
  Get all categories with preloaded series and images
  """
  def get_categories_with_series_and_images do
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
    Images.Utils.delete_series_for(:image_category, category.id)
    Brando.repo().soft_delete!(category)

    {:ok, category}
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

    cs = ImageCategory.changeset(%ImageCategory{}, :create, params)
    Brando.repo().insert(cs)
  end

  @doc """
  Count image series in category (by id)
  """
  def image_series_count(category_id) do
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
    categories = Brando.repo().all(ImageCategory)
    series = Brando.repo().all(ImageSeries)
    Images.Utils.get_orphaned_series(categories, series, starts_with: "images/site")
  end
end
