defmodule Brando.Content.BlockReferences do
  @moduledoc """
  Resolves block references back to the Blueprint entries that own them.

  The queries intentionally operate on the stable content tables and dynamic
  entry schemas. This keeps datasource invalidation independent of the much
  broader block rendering and mutation context.
  """

  import Ecto.Query

  alias Brando.RuntimeConfig

  @doc """
  Lists block ids using the exact datasource tuple or datasource schema.
  """
  @spec list_block_ids_using_datamodule(module() | {module(), atom(), atom()}) :: [integer()]
  def list_block_ids_using_datamodule(datasource)

  def list_block_ids_using_datamodule({datasource_module, datasource_type, datasource_query}) do
    list_module_ids(
      datasource_module: to_string(datasource_module),
      datasource_type: to_string(datasource_type),
      datasource_query: to_string(datasource_query)
    )
    |> list_block_ids_using_modules()
  end

  def list_block_ids_using_datamodule(datasource_module) do
    list_module_ids(datasource_module: to_string(datasource_module))
    |> list_block_ids_using_modules()
  end

  @doc """
  Lists block ids backed by any module id in `module_ids`.
  """
  @spec list_block_ids_using_modules([integer()]) :: [integer()]
  def list_block_ids_using_modules(module_ids) when is_list(module_ids) do
    query = from block in "content_blocks", where: block.module_id in ^module_ids, select: block.id
    repo().all(query)
  end

  @doc """
  Lists blocks referencing a file through refs, block vars, or table-row vars.
  """
  @spec list_block_ids_using_file(integer()) :: [integer()]
  def list_block_ids_using_file(file_id) do
    refs =
      from ref in "content_refs",
        where: ref.file_id == ^file_id and not is_nil(ref.block_id),
        select: ref.block_id

    vars =
      from var in "content_vars",
        left_join: row in "content_table_rows",
        on: row.id == var.table_row_id,
        where: var.file_id == ^file_id,
        where: not is_nil(var.block_id) or not is_nil(row.block_id),
        select: coalesce(var.block_id, row.block_id)

    refs |> union(^vars) |> repo().all()
  end

  @doc """
  Resolves root block ids, grouped by join schema, to owning entry ids.
  """
  @spec list_entry_ids_for_root_blocks_by_source(%{optional(module()) => [integer()]}) :: %{
          optional(module()) => [integer()]
        }
  def list_entry_ids_for_root_blocks_by_source(source_map) do
    Enum.reduce(source_map, %{}, fn
      {nil, _ids}, entries_by_schema ->
        entries_by_schema

      {join_source, ids}, entries_by_schema ->
        {schema, entry_ids} = list_entry_ids(join_source, ids)
        Map.put(entries_by_schema, schema, entry_ids)
    end)
  end

  @doc """
  Walks parent links and groups the root ids for `block_ids` by join schema.
  """
  @spec list_root_block_ids_by_source([integer()]) :: %{optional(module()) => [integer()]}
  def list_root_block_ids_by_source(block_ids) when is_list(block_ids) do
    base_case =
      from block in "content_blocks",
        select: %{id: block.id, parent_id: block.parent_id, source: block.source},
        where: block.id in ^block_ids

    recursive_case =
      from block in "content_blocks",
        select: %{id: block.id, parent_id: block.parent_id, source: block.source},
        join: parent in "parent_blocks",
        on: parent.parent_id == block.id

    query = union_all(base_case, ^recursive_case)

    "parent_blocks"
    |> recursive_ctes(true)
    |> with_cte("parent_blocks", as: ^query)
    |> where([block], is_nil(block.parent_id))
    |> select([block], %{id: block.id, source: block.source})
    |> distinct(true)
    |> repo().all()
    |> Enum.reduce(%{}, fn %{id: id, source: source}, roots_by_schema ->
      schema = Module.concat([source])
      Map.update(roots_by_schema, schema, [id], &(&1 ++ [id]))
    end)
  end

  @doc """
  Resolves `block_ids` to owning entries and removes `entry` from the result.
  """
  @spec reject_blocks_belonging_to_entry([integer()], struct() | nil) :: %{
          optional(module()) => [integer()]
        }
  def reject_blocks_belonging_to_entry([], _entry), do: %{}

  def reject_blocks_belonging_to_entry(block_ids, entry) do
    entries_by_schema =
      block_ids
      |> list_root_block_ids_by_source()
      |> list_entry_ids_for_root_blocks_by_source()

    reject_entry(entries_by_schema, entry)
  end

  defp list_module_ids(filters) do
    Enum.reduce(filters, from(module in "content_modules"), fn {field_name, value}, query ->
      from module in query, where: field(module, ^field_name) == ^value
    end)
    |> where([module], module.datasource == true and is_nil(module.deleted_at))
    |> select([module], module.id)
    |> repo().all()
  end

  defp list_entry_ids(join_source, block_ids) do
    {:assoc, %{queryable: schema}} = Map.fetch!(join_source.__changeset__(), :entry)

    query =
      from join_entry in join_source,
        join: entry in ^schema,
        on: entry.id == join_entry.entry_id,
        where: join_entry.block_id in ^block_ids,
        select: join_entry.entry_id,
        distinct: true

    query = maybe_reject_deleted(query, schema)
    {schema, repo().all(query)}
  end

  defp maybe_reject_deleted(query, schema) do
    if :deleted_at in schema.__schema__(:fields) do
      from [_join_entry, entry] in query, where: is_nil(entry.deleted_at)
    else
      query
    end
  end

  defp reject_entry(entries_by_schema, nil), do: entries_by_schema

  defp reject_entry(entries_by_schema, entry) do
    entry_schema = entry.__struct__

    case Enum.reject(Map.get(entries_by_schema, entry_schema, []), &(&1 == entry.id)) do
      [] -> Map.delete(entries_by_schema, entry_schema)
      filtered_ids -> Map.put(entries_by_schema, entry_schema, filtered_ids)
    end
  end

  defp repo, do: RuntimeConfig.get(:repo_module)
end
