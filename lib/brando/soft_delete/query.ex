defmodule Brando.SoftDelete.Query do
  @moduledoc """
  Query tools for Soft deletion
  """

  alias Brando.Image
  alias Brando.ImageCategory
  alias Brando.ImageSeries
  alias Brando.Images
  alias Brando.Pages
  alias Brando.Users.User
  alias Brando.Villain
  import Ecto.Query

  @doc """
  Excludes all deleted entries from query
  """
  def exclude_deleted(query), do: from(t in query, where: is_nil(t.deleted_at))

  @doc """
  List all soft delete enabled schemas
  """
  def list_soft_delete_schemas do
    {:ok, app_modules} = :application.get_key(Brando.otp_app(), :modules)

    modules =
      [
        Pages.Page,
        Pages.PageFragment,
        Villain.Template,
        Image,
        ImageCategory,
        ImageSeries,
        User
      ] ++ app_modules

    Enum.filter(modules, &({:__soft_delete__, 0} in &1.__info__(:functions)))
  end

  @doc """
  Count all soft deleted entries per schema
  """
  def count_soft_deletions do
    schemas = list_soft_delete_schemas()

    union_query =
      Enum.reduce(schemas, nil, fn
        schema, nil ->
          from t in schema, select: count(t.id), where: not is_nil(t.deleted_at)

        schema, q ->
          from t in schema, select: count(t.id), where: not is_nil(t.deleted_at), union_all: ^q
      end)

    counts = Brando.repo().all(union_query)
    Enum.zip(schemas, counts)
  end

  @doc """
  List all soft deleted entries across schemas
  """
  def list_soft_deleted_entries do
    schemas = list_soft_delete_schemas()
    Enum.flat_map(schemas, &list_soft_deleted_entries(&1))
  end

  @doc """
  List soft deleted entries for `schema`
  """
  def list_soft_deleted_entries(schema) do
    query = from t in schema, where: not is_nil(t.deleted_at), order_by: [desc: t.deleted_at]
    Brando.repo().all(query)
  end

  @doc """
  Clean up and delete all expired soft deleted entries
  """
  def clean_up_soft_deletions, do: Enum.map(list_soft_delete_schemas(), &clean_up_schema/1)

  defp clean_up_schema(Brando.Image) do
    query =
      from t in Brando.Image,
        where: fragment("? < current_timestamp - interval '30 day'", t.deleted_at)

    for image <- Brando.repo().all(query),
        do: Images.Utils.delete_original_and_sized_images(image, :image)

    Brando.repo().delete_all(query)
  end

  defp clean_up_schema(schema) do
    # check if the schema has image fields
    image_fields =
      if {:__imagefields__, 0} in schema.__info__(:functions) do
        Keyword.keys(schema.__imagefields__)
      else
        nil
      end

    # check if the schema has galleries
    galleries =
      if {:__gallery_fields__, 0} in schema.__info__(:functions) do
        schema.__gallery_fields__()
      else
        nil
      end

    query =
      from t in schema,
        where: fragment("? < current_timestamp - interval '30 day'", t.deleted_at)

    rows = Brando.repo().all(query)

    if image_fields do
      for row <- rows do
        Enum.map(image_fields, &Images.Utils.delete_original_and_sized_images(row, &1))
      end
    end

    if galleries do
      # Though the image_series is already marked for deletion,
      # we need to clear out its files
      for row <- rows do
        Enum.map(galleries, fn gallery_field ->
          field =
            gallery_field
            |> to_string
            |> Kernel.<>("_id")
            |> String.to_atom()

          series_id = Map.get(row, field)

          Images.Utils.clear_media_for(:image_series, series_id)
        end)
      end
    end

    Brando.repo().delete_all(query)
  end
end
