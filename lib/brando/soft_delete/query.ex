defmodule Brando.SoftDelete.Query do
  @moduledoc """
  Query tools for Soft deletion
  """
  alias Brando.Trait
  import Ecto.Query

  @doc """
  Excludes all deleted entries from query
  """
  def exclude_deleted(query), do: from(t in query, where: is_nil(t.deleted_at))

  @doc """
  List all soft delete enabled schemas
  """
  def list_soft_delete_schemas do
    Trait.SoftDelete.list_implementations()
  end

  @doc """
  Check if `schema` is soft deleted
  """
  def soft_delete_schema?(schema), do: schema in list_soft_delete_schemas()

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

    counts =
      union_query
      |> Brando.repo().all()
      |> Enum.reverse()

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

  defp clean_up_schema(schema) do
    query =
      from t in schema,
        where: fragment("? < current_timestamp - interval '30 day'", t.deleted_at)

    Brando.repo().delete_all(query)
  end
end
