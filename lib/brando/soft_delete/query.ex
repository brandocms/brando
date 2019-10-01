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
  def exclude_deleted(query), do: where(query, [t], is_nil(t.deleted_at))

  @doc """
  List all soft delete marked schemas
  """
  def list_all_soft_delete_schemas do
    {:ok, app_modules} = :application.get_key(Brando.otp_app(), :modules)

    modules =
      app_modules ++
        [
          Pages.Page,
          Pages.PageFragment,
          Villain.Template,
          Image,
          ImageCategory,
          ImageSeries,
          User
        ]

    Enum.filter(modules, &({:__soft_delete__, 0} in &1.__info__(:functions)))
  end

  def clean_up_soft_deletions, do: Enum.map(list_all_soft_delete_schemas(), &clean_up_schema/1)

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

    query =
      from t in schema,
        where: fragment("? < current_timestamp - interval '30 day'", t.deleted_at)

    if image_fields do
      rows = Brando.repo().all(query)

      for row <- rows do
        Enum.map(image_fields, &Images.Utils.delete_original_and_sized_images(row, &1))
      end
    end

    Brando.repo().delete_all(query)
  end
end
