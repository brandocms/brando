defmodule Brando.Images do
  @moduledoc """
  Context for Images.
  Handles uploads too.
  Interfaces with database
  """
  
  alias Brando.{ImageCategory, ImageSeries, Image}

  import Brando.Upload
  import Brando.Images.Utils, only: [
    create_image_sizes: 1,
    delete_original_and_sized_images: 2,
    fix_size_cfg_vals: 1,
    recreate_sizes_for: 2
  ]
  import Brando.Utils.Schema, only: [put_creator: 2]
  import Ecto.Query

  @doc """
  Create new image
  """
  @spec create_image(%{binary => term} | %{atom => term}, Brando.User.t) :: {:ok, Image.t} | {:error, Keyword.t}
  def create_image(params, user) do
    %Image{}
    |> put_creator(user)
    |> Image.changeset(:create, params)
    |> Brando.repo.insert
  end

  @doc """
  Update image
  """
  def update_image(schema, params) do
    schema
    |> Image.changeset(:update, params)
    |> Brando.repo.update
  end

  @doc """
  Get image.
  Raises on failure
  """
  def get_image!(id) do
    Brando.repo.get!(Image, id)
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
    q    = from m in Image, where: m.id in ^ids
    imgs = Brando.repo.all(q)

    for img <- imgs, do:
      {:ok, _} = delete_original_and_sized_images(img, :image)

    Brando.repo.delete_all(q)
  end

  @doc """
  Create image series
  """
  def create_series(data, user) do
    %ImageSeries{}
    |> put_creator(user)
    |> ImageSeries.changeset(:create, data)
    |> Brando.repo.insert()
  end

  @doc """
  Update image series.
  If slug or category has changed, we redo all the images
  """
  def update_series(id, data) do
    changeset =
      ImageSeries
      |> Brando.repo.get_by!(id: id)
      |> ImageSeries.changeset(:update, data)

    changeset
    |> Brando.repo.update()
    |> case do
      {:ok, inserted_series} ->
        # if slug is changed we recreate all the image sizes to reflect the new path
        if Ecto.Changeset.get_change(changeset, :slug) ||
           Ecto.Changeset.get_change(changeset, :image_category_id), do:
          recreate_sizes_for(:image_series, inserted_series.id)

        {:ok, Brando.repo.preload(inserted_series, :image_category)}
      error ->
        error
    end
  end

  @doc """
  Get all image series belonging to `cat_id`
  """
  def get_series_for(category_id: cat_id) do
    Brando.repo.all(
      from is in Brando.ImageSeries,
        where: is.image_category_id == ^cat_id
    )
  end

  @doc """
  Update image series config
  """
  def update_series_config(id, cfg, sizes) do
    series = Brando.repo.get_by!(Brando.ImageSeries, id: id)
    sizes  = fix_size_cfg_vals(sizes)

    new_cfg =
      (Map.get(series, :cfg) || %Brando.Type.ImageConfig{})
      |> Map.put(:allowed_mimetypes, String.split(cfg["allowed_mimetypes"], ", "))
      |> Map.put(:default_size, cfg["default_size"])
      |> Map.put(:size_limit, String.to_integer(cfg["size_limit"]))
      |> Map.put(:upload_path, cfg["upload_path"])
      |> Map.put(:sizes, sizes)

    series
    |> ImageSeries.changeset(:update, %{cfg: new_cfg})
    |> Brando.repo.update()
  end

  @doc """
  Delete image series.
  Also deletes all images depending on the series and executes any callbacks
  """
  def delete_series(id) do
    series = Brando.repo.get_by!(ImageSeries, id: id)
    :ok    = Brando.Images.Utils.delete_images_for(:image_series, series.id)

    series = Brando.repo.preload(series, :image_category)
    Brando.repo.delete!(series)

    {:ok, series}
  end

  @doc """
  Create a new category
  """
  def create_category(data, user) do
    %ImageCategory{}
    |> put_creator(user)
    |> ImageCategory.changeset(:create, data)
    |> Brando.repo.insert()
  end

  @doc """
  Update category with `id` with `data`.
  If `slug` is changed in data, return {:propagate, category}, else return {:ok, category} or error
  """
  def update_category(id, data) do
    changeset =
      ImageCategory
      |> Brando.repo.get_by(id: id)
      |> ImageCategory.changeset(:update, data)

    changeset
    |> Brando.repo.update()
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
    Brando.repo.get(ImageCategory, id)
  end

  @doc """
  Get all categories with preloaded series and images
  """
  def get_categories_with_series_and_images() do
    ImageCategory
    |> ImageCategory.with_image_series_and_images
    |> Brando.repo.all
  end

  @doc """
  Update category's config
  """
  def update_category_config(id, cfg, sizes) do
    img_cat = Brando.repo.get_by!(ImageCategory, id: id)
    sizes  = fix_size_cfg_vals(sizes)

    new_cfg =
      img_cat.cfg
      |> Map.put(:allowed_mimetypes, String.split(cfg["allowed_mimetypes"], ", "))
      |> Map.put(:default_size, cfg["default_size"])
      |> Map.put(:size_limit, String.to_integer(cfg["size_limit"]))
      |> Map.put(:upload_path, cfg["upload_path"])
      |> Map.put(:sizes, sizes)

    img_cat
    |> ImageCategory.changeset(:update, %{cfg: new_cfg})
    |> Brando.repo.update
  end

  @doc """
  Deletes category with id `id`.
  Also deletes all series depending on the category.
  """
  def delete_category(id) do
    category = Brando.repo.get_by!(ImageCategory, id: id)
    Brando.Images.Utils.delete_series_for(:image_category, category.id)
    Brando.repo.delete!(category)
  end

  @doc """
  Get all portfolio image series that are orphaned
  """
  def get_all_orphaned_series() do
    categories = Brando.repo.all(ImageCategory)
    series = Brando.repo.all(ImageSeries)
    Brando.Images.Utils.get_orphaned_series(categories, series, starts_with: "images/site")
  end

  @doc """
  Checks `params` for Plug.Upload fields and passes them on.
  Fields in the `put_fields` map are added to the schema.
  Returns {:ok, schema} or raises
  """
  def check_for_uploads(params, current_user, cfg, put_fields \\ nil) do
    Enum.reduce(filter_plugs(params), [], fn (named_plug, _) ->
      handle_upload(named_plug,
                    &create_image_struct/1,
                    current_user,
                    put_fields,
                    cfg)
    end)
  end

  @doc """
  Handles Plug.Upload for our modules.
  This is the handler for Brando.Image and Brando.Portfolio.Image
  """
  def handle_upload({name, plug}, process_fn, user, put_fields, cfg) do
    with {:ok, upload} <- process_upload(plug, cfg),
         {:ok, processed_field} <- process_fn.(upload)
    do
      params = Map.put(put_fields, name, processed_field)
      create_image(params, user)
    else
      err -> handle_upload_error(err)
    end
  end

  @doc """
  Passes upload to create_image_sizes.
  """
  def create_image_struct(upload) do
    create_image_sizes(upload)
  end
end
