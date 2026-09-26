defmodule Brando.Content.Proposals.BlockTree do
  @moduledoc """
  The shape of one block field while a proposal is validated: which blocks
  exist, their parents and the order of each parent's children.

  `Brando.Content.Proposals` starts from the saved field and replays the
  operations on it in order, so an operation is checked against the field as
  the operations before it leave it — a block the proposal deletes cannot be
  edited afterwards, and a block it inserts can be moved or filled.

  Root blocks have the parent `nil`.
  """

  defstruct nodes: %{}, order: %{nil => []}

  @type uid :: String.t()
  @type block :: %{
          uid: uid(),
          parent: uid() | nil,
          type: atom(),
          module: {atom(), integer()} | nil,
          multi: boolean(),
          slot_module_set: String.t() | nil
        }
  @type t :: %__MODULE__{nodes: %{uid() => block()}, order: %{(uid() | nil) => [uid()]}}

  @doc "The tree of a saved block field, from its join rows (or blocks)."
  @spec from_saved([struct()]) :: t()
  def from_saved(roots) do
    roots
    |> Enum.map(&Map.get(&1, :block, &1))
    |> Enum.reduce(%__MODULE__{}, &add_saved(&2, &1, nil))
  end

  defp add_saved(tree, block, parent) do
    node = %{
      uid: block.uid,
      parent: parent,
      type: block.type,
      module: block.module_id && {block.module_origin || :local, block.module_id},
      multi: !!block.multi,
      slot_module_set: block.slot_module_set
    }

    tree = put(tree, node, parent, :append)
    Enum.reduce(saved_children(block), tree, &add_saved(&2, &1, block.uid))
  end

  defp saved_children(%{children: children}) when is_list(children), do: children
  defp saved_children(_), do: []

  @doc "The block `uid`, or `nil`."
  @spec fetch(t(), uid()) :: block() | nil
  def fetch(tree, uid), do: Map.get(tree.nodes, uid)

  @doc "The children of `parent` (`nil` for the root), in order."
  @spec children(t(), uid() | nil) :: [uid()]
  def children(tree, parent), do: Map.get(tree.order, parent, [])

  @doc "Whether `anchor` is a sibling of a block placed under `parent`."
  @spec sibling?(t(), uid() | nil, uid()) :: boolean()
  def sibling?(tree, parent, anchor), do: anchor in children(tree, parent)

  @doc """
  Place `node` under `parent`: `:append` or `{:into, _}` (last),
  `{:before, uid}` or `{:after, uid}` where `uid` is a sibling.
  """
  @spec put(t(), block(), uid() | nil, term()) :: t()
  def put(tree, node, parent, placement) do
    node = %{node | parent: parent}
    siblings = children(tree, parent)

    %{
      tree
      | nodes: Map.put(tree.nodes, node.uid, node),
        order: Map.put(tree.order, parent, insert_at(siblings, node.uid, placement))
    }
  end

  @doc """
  Move `uid` under `parent` (`nil` for the root) at `placement`. `{:into, _}`
  places it last.
  """
  @spec move(t(), uid(), uid() | nil, term()) :: t()
  def move(tree, uid, parent, placement) do
    %{parent: from} = node = fetch(tree, uid)
    order = Map.update(tree.order, from, [], &List.delete(&1, uid))
    siblings = Map.get(order, parent, [])

    %{
      tree
      | nodes: Map.put(tree.nodes, uid, %{node | parent: parent}),
        order: Map.put(order, parent, insert_at(siblings, uid, placement))
    }
  end

  @doc """
  Copy `uid` and the blocks below it under `parent` at `placement`. The copy
  is `copy`; each block below takes `copy_uid(copy, original)`.
  """
  @spec copy(t(), uid(), uid(), uid() | nil, term()) :: t()
  def copy(tree, uid, copy, parent, placement), do: copy_from(tree, tree, uid, copy, parent, placement)

  @doc "Copy `uid` of `source` into `tree`, as `copy/5` does within one tree."
  @spec copy_from(t(), t(), uid(), uid(), uid() | nil, term()) :: t()
  def copy_from(source, tree, uid, copy, parent, placement) do
    tree
    |> put(%{fetch(source, uid) | uid: copy}, parent, placement)
    |> copy_children(source, uid, copy, copy)
  end

  defp copy_children(tree, source, original, parent, root) do
    Enum.reduce(children(source, original), tree, fn child, tree ->
      uid = copy_uid(root, child)

      tree
      |> put(%{fetch(source, child) | uid: uid}, parent, :append)
      |> copy_children(source, child, uid, root)
    end)
  end

  @doc """
  The uid a copy `copy` gives to `original`, a block below the copied one.
  Derived rather than random, so every materialization of a proposal builds
  the same tree.
  """
  @spec copy_uid(uid(), uid()) :: uid()
  def copy_uid(copy, original) do
    :sha256
    |> :crypto.hash(copy <> ":" <> original)
    |> Base.encode32(case: :lower, padding: false)
    |> binary_part(0, 22)
  end

  @doc "Every uid below `uid`."
  @spec descendants(t(), uid()) :: [uid()]
  def descendants(tree, uid), do: Enum.flat_map(children(tree, uid), &[&1 | descendants(tree, &1)])

  @doc "Whether `uid` is `ancestor` or below it."
  @spec within?(t(), uid(), uid()) :: boolean()
  def within?(_tree, ancestor, ancestor), do: true

  def within?(tree, ancestor, uid) do
    case fetch(tree, uid) do
      %{parent: nil} -> false
      %{parent: parent} -> within?(tree, ancestor, parent)
      nil -> false
    end
  end

  @doc "Remove `uid` and everything below it."
  @spec delete(t(), uid()) :: t()
  def delete(tree, uid) do
    %{parent: parent} = fetch(tree, uid)
    removed = descendants(tree, uid)

    %{
      tree
      | nodes: Map.drop(tree.nodes, [uid | removed]),
        order: tree.order |> Map.drop([uid | removed]) |> Map.update(parent, [], &List.delete(&1, uid))
    }
  end

  @doc "Insert `uid` into `list` at `placement`; an anchor missing from `list` appends."
  @spec insert_at([term()], term(), term(), (term() -> term())) :: [term()]
  def insert_at(list, item, placement, key \\ & &1)
  def insert_at(list, item, :append, _key), do: list ++ [item]
  def insert_at(list, item, {:into, _}, _key), do: list ++ [item]

  def insert_at(list, item, {side, anchor}, key) do
    case Enum.find_index(list, &(key.(&1) == anchor)) do
      nil -> list ++ [item]
      index -> List.insert_at(list, if(side == :before, do: index, else: index + 1), item)
    end
  end

  @doc """
  Find the saved block `uid` anywhere under `roots` (join rows or blocks).
  Returns `{block, parent_block | nil, index}` or `nil`.
  """
  @spec find_saved([struct()], uid()) :: {struct(), struct() | nil, non_neg_integer()} | nil
  def find_saved(roots, uid), do: roots |> Enum.map(&Map.get(&1, :block, &1)) |> find_in(uid, nil)

  defp find_in(blocks, uid, parent) do
    blocks
    |> Enum.with_index()
    |> Enum.find_value(fn {block, index} ->
      if block.uid == uid, do: {block, parent, index}, else: find_in(saved_children(block), uid, block)
    end)
  end
end
