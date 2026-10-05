defmodule Brando.FrontendEdit.Targets do
  @moduledoc """
  Resolves a block clicked on the frontend to the block the editor opens, and
  that block to the entry and field that own it.

  A click selects the nearest module:

    * a block inside a module's region or footnote collection (a `:slot`)
      selects the module that owns the collection, since the collection is
      edited inside that module;
    * an entry of a multi module selects the multi module;
    * otherwise the closest module in the chain from the clicked block up to
      its root, or the clicked container or fragment block when no module
      is involved.

  The frontend outlines what a click would open from the manifest, and the
  editor resolves the same uid again, so both follow these rules.
  """

  import Ecto.Query

  @type chain_block :: %{
          id: integer(),
          uid: binary(),
          type: atom(),
          parent_id: integer() | nil,
          module_id: integer() | nil,
          module_origin: atom() | nil,
          container_id: integer() | nil,
          fragment_id: integer() | nil,
          source: binary() | nil
        }

  @doc """
  Loads each uid's block and every ancestor up to its root, nearest first.
  Returns `%{uid => [chain_block]}`; uids with no block are left out.
  """
  @spec chains([binary()]) :: %{optional(binary()) => [chain_block()]}
  def chains([]), do: %{}

  def chains(uids) when is_list(uids) do
    # The tenant's prefix goes on the table itself: on the query it would also
    # qualify the CTE's name.
    prefix = Brando.Tenant.current_prefix()

    base_case =
      from block in "content_blocks",
        prefix: ^prefix,
        where: block.uid in ^uids,
        select: %{origin: block.uid, id: block.id, parent_id: block.parent_id, depth: 0}

    recursive_case =
      from block in "content_blocks",
        prefix: ^prefix,
        join: chain in "frontend_edit_chain",
        on: block.id == chain.parent_id,
        select: %{origin: chain.origin, id: block.id, parent_id: block.parent_id, depth: chain.depth + 1}

    rows =
      "frontend_edit_chain"
      |> recursive_ctes(true)
      |> with_cte("frontend_edit_chain", as: ^union_all(base_case, ^recursive_case))
      |> select([chain], {chain.origin, chain.id, chain.depth})
      |> Brando.RuntimeConfig.get(:repo_module).all()

    blocks =
      rows
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> load_blocks()

    rows
    |> Enum.group_by(&elem(&1, 0), fn {_, id, depth} -> {depth, id} end)
    |> Map.new(fn {uid, entries} ->
      chain =
        entries
        |> Enum.sort()
        |> Enum.map(fn {_, id} -> Map.fetch!(blocks, id) end)

      {uid, chain}
    end)
  end

  defp load_blocks(ids) do
    from(block in "content_blocks",
      where: block.id in ^ids,
      select: %{
        id: block.id,
        uid: block.uid,
        type: block.type,
        parent_id: block.parent_id,
        module_id: block.module_id,
        module_origin: block.module_origin,
        container_id: block.container_id,
        fragment_id: block.fragment_id,
        source: block.source
      }
    )
    |> Brando.Repo.all()
    |> Map.new(fn block ->
      {block.id, %{block | type: to_atom(block.type), module_origin: to_atom(block.module_origin)}}
    end)
  end

  defp to_atom(nil), do: nil
  defp to_atom(value) when is_atom(value), do: value
  defp to_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  @doc """
  The block a click on the first block of `chain` opens. `chain` runs from
  the clicked block up to its root.
  """
  @spec target(nonempty_list(chain_block())) :: chain_block()
  def target([clicked | _] = chain) do
    candidates =
      case chain |> Enum.with_index() |> Enum.filter(fn {block, _} -> block.type == :slot end) |> List.last() do
        nil -> chain
        {_slot, index} -> Enum.drop(chain, index + 1)
      end

    Enum.find(candidates, &(&1.type == :module)) ||
      Enum.find(candidates, &(&1.type in [:container, :fragment])) ||
      List.first(candidates) ||
      clicked
  end

  @doc "The top-level block of `chain`, the one without a parent."
  @spec root([chain_block()]) :: chain_block() | nil
  def root(chain), do: Enum.find(chain, &is_nil(&1.parent_id))

  @doc """
  The uids from the root down to `target`, excluding it, in `chain`.
  """
  @spec ancestors(nonempty_list(chain_block()), chain_block()) :: [binary()]
  def ancestors(chain, target) do
    chain
    |> Enum.drop_while(&(&1.id != target.id))
    |> tl()
    |> Enum.reverse()
    |> Enum.map(& &1.uid)
  end

  @doc """
  Resolves `uid` for the editor: the block to open, its root and ancestors,
  and the entry and block field that own it.
  """
  @spec resolve(binary()) ::
          {:ok,
           %{
             clicked: chain_block(),
             target: chain_block(),
             root: chain_block(),
             path: [binary()],
             owner: {module(), integer(), atom()}
           }}
          | {:error, :not_found}
  def resolve(uid) when is_binary(uid) do
    with [_ | _] = chain <- Map.get(chains([uid]), uid),
         root = root(chain),
         {:ok, owner} <- owner(root) do
      target = target(chain)
      {:ok, %{clicked: hd(chain), target: target, root: root, path: ancestors(chain, target), owner: owner}}
    else
      _ -> {:error, :not_found}
    end
  end

  def resolve(_), do: {:error, :not_found}

  @doc """
  The entry and block field a root block belongs to. A root reaches its
  entry through the join table named by its `source`.
  """
  @spec owner(chain_block()) :: {:ok, {module(), integer(), atom()}} | :error
  def owner(%{id: id, source: source}) when is_binary(source) do
    join_schema = Module.concat([source])

    with true <- Code.ensure_loaded?(join_schema) and function_exported?(join_schema, :__changeset__, 0),
         {:assoc, %{queryable: schema}} <- Map.get(join_schema.__changeset__(), :entry),
         %{name: field} <- Enum.find(schema.__blocks_fields__(), &(join_source(schema, &1.name) == join_schema)),
         entry_id when not is_nil(entry_id) <-
           Brando.Repo.one(from(join in join_schema, where: join.block_id == ^id, select: join.entry_id, limit: 1)) do
      {:ok, {schema, entry_id, field}}
    else
      _ -> :error
    end
  end

  def owner(_), do: :error

  @doc "How many entries hold a block embedding the fragment `id`."
  @spec fragment_usage(integer()) :: non_neg_integer()
  def fragment_usage(id) do
    from(block in "content_blocks", where: block.fragment_id == ^id, select: block.uid)
    |> Brando.Repo.all()
    |> chains()
    |> Enum.flat_map(fn {_uid, chain} ->
      case owner(root(chain)) do
        {:ok, {schema, entry_id, _field}} -> [{schema, entry_id}]
        :error -> []
      end
    end)
    |> Enum.uniq()
    |> length()
  end

  defp join_source(schema, field), do: Module.concat([schema, field |> to_string() |> Macro.camelize()])
end
