defmodule Brando.SoftDelete.Query do
  @moduledoc """
  Query tools for Soft deletion
  """
  import Ecto.Query
  alias Brando.Repo
  alias Brando.Trait

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
      |> Repo.all()
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
    Repo.all(query)
  end

  @doc """
  Clean up and delete all expired soft deleted entries
  """
  def clean_up_soft_deletions, do: Enum.map(list_soft_delete_schemas(), &clean_up_schema/1)

  # Handle Video schema specially to support remote deletion on purge
  defp clean_up_schema(Brando.Videos.Video = schema) do
    query =
      from t in schema,
        where: fragment("? < current_timestamp - interval '30 day'", t.deleted_at)

    # Check timing per video since different videos may have different providers
    {on_purge, others} =
      query |> Repo.all() |> Enum.split_with(&(Brando.Videos.Uploader.get_delete_timing(&1) == :on_purge))

    # Each row is purged while its video's lock is held, so another
    # environment's purge of the same video, waiting for the lock, no longer
    # finds it among the holders and deletes the video at the provider. The
    # provider is asked once the row is gone, and not when the delete, still
    # filtered on expiry, leaves it: a restore from the trash takes no lock,
    # so the record may have been restored, or restored and deleted again,
    # since it was read. A video whose holders could not be read
    # (`Brando.Videos.ProviderHoldings`), or whose lock an add or another
    # delete held too long, is still at its provider. Its row stays for the
    # next run to try again; deleting it would leave the provider video behind
    # for good.
    purged =
      Enum.count(on_purge, fn video ->
        result =
          Brando.Videos.Uploader.delete_remote(video, fn ->
            match?({1, _}, Repo.delete_all(from t in query, where: t.id == ^video.id))
          end)

        result not in [{:error, :holdings_unavailable}, {:error, :busy}, {:error, :not_purged}]
      end)

    {count, nil} = Repo.delete_all(from t in query, where: t.id in ^Enum.map(others, & &1.id))
    {count + purged, nil}
  end

  defp clean_up_schema(schema) do
    query =
      from t in schema,
        where: fragment("? < current_timestamp - interval '30 day'", t.deleted_at)

    Repo.transaction(fn ->
      purged = if Brando.Activity.logged?(schema), do: Repo.all(query), else: []

      ids = query |> select([t], t.id) |> Repo.all()

      if schema.__trait__(Brando.Trait.Revisioned) do
        Enum.each(ids, &Brando.Revisions.delete_entry_revisions(schema, &1))
      end

      Brando.Notes.entries_purged(schema, ids)

      result = Repo.delete_all(query)
      Enum.each(purged, &Brando.Activity.deleted(&1, :system, false, %{"purged" => true}))
      result
    end)
  end
end
