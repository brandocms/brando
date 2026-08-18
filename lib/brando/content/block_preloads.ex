defmodule Brando.Content.BlockPreloads do
  @moduledoc """
  Builds preload queries for Blueprint block fields and nested block trees.

  This module contains only preload construction and loading. Keeping it apart
  from `Brando.Content.Blocks` prevents generic Blueprint entry reads from
  depending on block mutation, rendering, and worker orchestration.
  """

  import Ecto.Query

  alias Brando.Content.Block
  alias Brando.Content.Ref
  alias Brando.Content.TableRow
  alias Brando.Content.Var
  alias Brando.Repo

  @doc """
  Returns the complete block-field preloads for `schema`.
  """
  @spec for_schema(module()) :: list()
  def for_schema(schema) do
    if schema.has_trait(Brando.Trait.Blocks) do
      vars_query = block_vars_query()
      table_row_query = block_table_rows_query()
      refs_query = block_refs_query()

      Enum.reduce(schema.__blocks_fields__(), [], fn %{name: assoc_name}, acc ->
        field_as_module =
          assoc_name
          |> to_string()
          |> Macro.camelize()
          |> then(&:"#{&1}")

        join_schema = Module.concat([schema, field_as_module])
        entry_assoc_name = :"entry_#{assoc_name}"

        acc ++
          [
            {entry_assoc_name,
             from(j in join_schema,
               order_by: [asc: :sequence],
               preload: [
                 block: [
                   :parent,
                   :container,
                   :module,
                   :palette,
                   block_identifiers: :identifier,
                   vars: ^vars_query,
                   refs: ^refs_query,
                   table_rows: ^table_row_query,
                   # Ecto runs custom preload functions in their own processes,
                   # which do not inherit the tenant prefix from the process
                   # dictionary. Captured here, where the prefix is still set.
                   children: ^Brando.Tenant.capture_context(&__MODULE__.preload_child_trees/1)
                 ]
               ]
             )}
          ]
      end)
    else
      []
    end
  end

  @doc """
  Loads and stitches the complete descendant trees for the given parent IDs.

  Ecto uses the returned direct children for each parent and receives every
  deeper level already attached, avoiding a query per nesting level.
  """
  @spec preload_child_trees([integer()]) :: [struct()]
  def preload_child_trees([]), do: []

  def preload_child_trees(parent_ids) do
    initial = from(b in Block, where: b.parent_id in ^parent_ids)

    recursion =
      from(b in Block,
        inner_join: descendant in "block_descendants",
        on: b.parent_id == descendant.id
      )

    descendants_query = union_all(initial, ^recursion)

    descendants =
      {"block_descendants", Block}
      |> recursive_ctes(true)
      |> with_cte("block_descendants", as: ^descendants_query)
      |> Repo.all()
      |> Enum.map(&put_in(&1.__meta__.source, "content_blocks"))
      |> Repo.preload([
        :palette,
        :container,
        :module,
        block_identifiers: :identifier,
        vars: block_vars_query(),
        refs: block_refs_query(),
        table_rows: block_table_rows_query()
      ])

    by_parent = Enum.group_by(descendants, & &1.parent_id)

    parent_ids
    |> Enum.flat_map(&Map.get(by_parent, &1, []))
    |> Enum.sort_by(& &1.sequence)
    |> Enum.map(&attach_child_tree(&1, by_parent))
  end

  defp attach_child_tree(block, by_parent) do
    children =
      by_parent
      |> Map.get(block.id, [])
      |> Enum.sort_by(& &1.sequence)
      |> Enum.map(&attach_child_tree(&1, by_parent))

    %{block | children: children}
  end

  defp block_vars_query do
    from variable in Var,
      order_by: [asc: :sequence],
      preload: ^Var.preloads()
  end

  defp block_table_rows_query do
    vars_query = block_vars_query()

    from table_row in TableRow,
      order_by: [asc: :sequence],
      preload: [vars: ^vars_query]
  end

  defp block_refs_query do
    from ref in Ref,
      order_by: [asc: :sequence],
      preload: [
        :image,
        :file,
        video: [:thumbnail, :file],
        gallery: [gallery_objects: [:image, video: [:thumbnail, :file]]]
      ]
  end
end
