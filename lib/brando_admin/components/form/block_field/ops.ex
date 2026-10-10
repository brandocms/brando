defmodule BrandoAdmin.Components.Form.BlockField.Ops do
  @moduledoc """
  Pure operation reducer for a block field's block-tree state.

  Phase 3 of the block editor refactor replaces changesets-travelling-between-
  components with small named operations applied by one owner (BlockField).
  This module is that owner's state + reducer: root order, parent/child
  structure, a uid-keyed param-diff store and per-uid statuses, mutated
  exclusively through `apply_op/2`. Being pure, every structural/content
  mutation the LiveView layer performs becomes unit-testable here.

  The store is the ONLY structural state: BlockField renders root shells
  straight from `order` (via its `root_order` projection) and parent blocks
  render children from their `block_list` (mirrored here via child ops);
  seed forms are uid-keyed mount-time snapshots, never an order source.
  `materialize_root/2` builds save-ready params from the store for save,
  preview, share, restore and the outline alike.

  ## Semantics

  * `order` (roots) and `child_order` (per parent) are the source of truth
    for sequence and nesting. Diffs may carry stale `"sequence"`/`"children"`
    keys (children restamp forms after reorders; roots stamp `children: []`);
    both are ignored at materialization — the tree wins.
  * `diffs` hold a block's *changes vs. its persisted data* as params (see
    `changes_to_params/1`) — `Ecto.Changeset.cast/4` skips absent keys, so
    untouched fields never travel. Root diffs are entry-block shaped
    (`%{"block" => ...}`), child diffs are block shaped.
  * `{:update, ...}` stores roots and children differently, because the two
    `validate_block` clauses produce differently-scoped diffs. A ROOT rebases
    on `changeset.data`, so its diff is cumulative vs. the DB and REPLACES the
    stored one. A CHILD rebases on `apply_changes/1`, so its diff is only the
    delta since the previous validate and is deep-MERGED onto the stored one.
    Getting this backwards loses data either way: replacing child diffs drops
    every edit but the newest, and merging root diffs resurrects values the
    user has since reverted.
  * `carry/3` is the exception for roots. It carries one state's diffs onto
    another's, and when that is live session state (a rejoin, a recovery
    copy) the target's root diff holds other editors' work, not an earlier
    diff of the same editor. So a carried root diff is merged into it field
    by field, the carried fields winning, as for children; for a rejoin,
    its row lists merge by row as well (`carry/4`, `lists: :merge`). A field the carried diff lacks keeps the
    target's value, including one its editor set back to the saved value
    with a whole-form `{:update, ...}`, which sends no key for it. A
    recovery copy holds each root it changed whole (`restore_draft`), so it
    still sets every field of such a root.
  * Inserted params may carry a nested children tree (duplicate/paste/
    recovery); `apply_op/2` splits it into per-uid diffs and registers the
    structure, keeping the one-diff-per-uid invariant.
  * Deleting a `:persisted` block records it (and its persisted descendants)
    in `deleted`; `:inserted` blocks just drop. `bin_snapshot/2` captured
    before the delete + `{:restore, snapshot}` undo one, subtree and all.

  ## One reducer, several copies

  The same reducer runs in the entry's `Brando.EditSession` (the authority,
  which orders every op and gives it a revision) and in every editor's
  BlockField (a replica that applies the session's broadcast ops). Because
  `apply_op/2` is pure, applying the same ops in the same order gives the
  same state everywhere. Ops therefore never depend on anything outside the
  state: no process, no database, no clock.
  """

  alias BrandoAdmin.Components.Form.BlockField.FractionalKey
  alias Ecto.Changeset

  defstruct order: [],
            parents: %{},
            child_order: %{},
            diffs: %{},
            statuses: %{},
            db_ids: %{},
            rel_ids: %{},
            row_order: %{},
            keys: %{},
            deleted: []

  @type uid :: String.t()
  @type params :: %{optional(String.t()) => term()}
  @type status :: :persisted | :inserted

  @type t :: %__MODULE__{
          order: [uid()],
          parents: %{optional(uid()) => uid()},
          child_order: %{optional(uid()) => [uid()]},
          diffs: %{optional(uid()) => params()},
          statuses: %{optional(uid()) => status()},
          db_ids: %{optional(uid()) => {entry_block_id :: term() | nil, block_id :: term() | nil}},
          rel_ids: %{optional(uid()) => %{optional({String.t(), String.t()}) => term()}},
          row_order: %{optional(uid()) => %{optional(String.t()) => [term()]}},
          keys: %{optional(uid()) => FractionalKey.t()},
          deleted: [uid()]
        }

  @typedoc """
  Where a block goes among its siblings: an index, the end, or a fractional
  key (`FractionalKey`). Editors send keys, so an insert lands between the
  neighbours it was put between whatever else moved in the meantime.
  """
  @type position :: non_neg_integer() | :end | {:key, FractionalKey.t()}

  @typedoc """
  Where one field sits in a block's diff: map keys, list items by identity
  (`{:at, key, identity, skeleton}`, the skeleton being the whole list's
  identities in case the diff has no list yet) and `{:map, key, default}`
  for a map the diff may lack (an embed, whose default is its full value).
  """
  @type field_path :: [String.t() | {:at, String.t(), term(), [map()]} | {:map, String.t(), map()}]

  @type op ::
          {:insert, uid(), position(), params()}
          | {:insert_child, parent :: uid(), uid(), position(), params()}
          | {:update, uid(), params()}
          | {:set_field, uid(), field_path(), term(), rev :: non_neg_integer() | nil}
          | {:set_fields, uid(), [{field_path(), term()}], rev :: non_neg_integer() | nil}
          | {:move, uid(), position()}
          | {:reorder, [uid()]}
          | {:reorder_children, parent :: uid(), [uid()]}
          | {:move_to_parent, uid(), new_parent :: uid(), position()}
          | {:remap_slot, uid(), uid() | nil, params()}
          | {:delete, uid()}
          | {:restore, map()}
          | {:replace_state, t()}
          | {:carry, t(), t()}

  @doc """
  Build a fresh state from root-block uids (no nesting, no db ids).

  Used in tests and for empty fields; `from_entry_blocks/1` is the loaded
  variant.

  ## Examples

      iex> alias BrandoAdmin.Components.Form.BlockField.Ops
      iex> Ops.new(["a", "b"]).order
      ["a", "b"]
      iex> Ops.new(["a"]).statuses
      %{"a" => :persisted}

  """
  @spec new([uid()]) :: t()
  def new(uids) do
    put_spread_keys(%__MODULE__{order: uids, statuses: Map.new(uids, &{&1, :persisted})})
  end

  @doc """
  Build a fresh state from preloaded entry blocks (mount / post-save reload).

  Walks each entry block's children tree recursively, registering structure,
  `:persisted` statuses and db ids. Diffs start empty.
  """
  @spec from_entry_blocks([struct()]) :: t()
  def from_entry_blocks(entry_blocks) do
    Enum.reduce(entry_blocks, %__MODULE__{}, fn entry_block, state ->
      uid = entry_block.block.uid

      state = %{
        state
        | order: state.order ++ [uid],
          statuses: Map.put(state.statuses, uid, :persisted),
          db_ids: Map.put(state.db_ids, uid, {entry_block.id, entry_block.block.id}),
          rel_ids: put_rel_ids(state.rel_ids, entry_block.block),
          row_order: put_row_order(state.row_order, entry_block.block)
      }

      register_persisted_children(state, entry_block.block)
    end)
    |> put_spread_keys()
  end

  # Evenly spread keys for every sibling list, roots included.
  defp put_spread_keys(state) do
    keys =
      [state.order | Map.values(state.child_order)]
      |> Enum.flat_map(fn uids -> Enum.zip(uids, FractionalKey.spread(length(uids))) end)
      |> Map.new()

    %{state | keys: keys}
  end

  defp register_persisted_children(state, %{uid: parent_uid, children: children}) when is_list(children) do
    Enum.reduce(children, state, fn child, state ->
      state = %{
        state
        | parents: Map.put(state.parents, child.uid, parent_uid),
          child_order: Map.update(state.child_order, parent_uid, [child.uid], &(&1 ++ [child.uid])),
          statuses: Map.put(state.statuses, child.uid, :persisted),
          db_ids: Map.put(state.db_ids, child.uid, {nil, child.id}),
          rel_ids: put_rel_ids(state.rel_ids, child),
          row_order: put_row_order(state.row_order, child)
      }

      register_persisted_children(state, child)
    end)
  end

  defp register_persisted_children(state, _block_without_loaded_children), do: state

  # The ids of a block's rows, by what names them without an id: a ref by its
  # uid, a var by its key, a table row by its sync uid. A diff taken while
  # the block was new names its rows that way, and keeps naming them so when
  # it is replayed after a save gave them ids (`fill_rel_ids/2`).
  @rel_identities [{"refs", :uid}, {"vars", :key}, {"table_rows", :sync_uid}]

  # What names a list item, in order (`identity/2`).
  @row_identities ~w(id uid key sync_uid)
  @content_identities %{"options" => ~w(value), "gallery_objects" => ~w(image_id video_id)}

  # The ids of a block's rows, in their order, by relation: the rows as
  # they are saved, for a rejoin whose session has no change to them
  # (`carry/4`).
  defp put_row_order(row_order, %{uid: uid} = block) do
    ids =
      for {key, _field} <- @rel_identities,
          rows = Map.get(block, String.to_existing_atom(key)),
          is_list(rows),
          into: %{},
          do: {key, for(%{id: id} <- rows, not is_nil(id), do: id)}

    Map.put(row_order, uid, ids)
  end

  defp put_rel_ids(rel_ids, %{uid: uid} = block) do
    ids =
      for {key, field} <- @rel_identities,
          rows = Map.get(block, String.to_existing_atom(key)),
          is_list(rows),
          %{id: id} = row when not is_nil(id) <- rows,
          identity = Map.get(row, field),
          identity not in [nil, ""],
          into: %{},
          do: {{key, to_string(identity)}, id}

    if ids == %{}, do: rel_ids, else: Map.put(rel_ids, uid, ids)
  end

  @doc """
  Keep the row ids (`rel_ids`) of `uids` only, and of the blocks with a
  diff.

  A diff names a block's rows by uid only when they were new, so only a
  block that has unsaved work, or had it when a save gave its rows ids,
  needs them. The edit session keeps the rest out of its state: for a long
  entry they are most of its size.
  """
  @spec keep_rel_ids(t(), Enumerable.t()) :: t()
  def keep_rel_ids(%__MODULE__{} = state, uids \\ []) do
    keep = state.diffs |> Enum.reject(fn {_uid, diff} -> diff == %{} end) |> Enum.map(&elem(&1, 0)) |> Enum.concat(uids)
    %{state | rel_ids: Map.take(state.rel_ids, keep), row_order: Map.take(state.row_order, keep)}
  end

  @doc "The blocks of `state` with unsaved work: inserted, or with a diff."
  @spec edited(t()) :: [uid()]
  def edited(%__MODULE__{} = state) do
    inserted = for {uid, :inserted} <- state.statuses, do: uid
    diffed = for {uid, diff} <- state.diffs, diff != %{}, do: uid
    inserted ++ diffed
  end

  defp fill_rel_ids(block_params, nil), do: block_params

  defp fill_rel_ids(block_params, ids) do
    Enum.reduce(@rel_identities, block_params, fn {key, field}, params ->
      case params do
        %{^key => rows} when is_list(rows) -> Map.put(params, key, Enum.map(rows, &fill_rel_id(&1, key, field, ids)))
        _ -> params
      end
    end)
  end

  defp fill_rel_id(%{} = row, key, field, ids) do
    with id when id in [nil, ""] <- Map.get(row, "id"),
         identity when identity not in [nil, ""] <- Map.get(row, to_string(field)),
         %{} <- row,
         rel_id when not is_nil(rel_id) <- Map.get(ids, {key, to_string(identity)}) do
      Map.put(row, "id", rel_id)
    else
      _ -> row
    end
  end

  defp fill_rel_id(row, _key, _field, _ids), do: row

  @doc """
  Apply a named operation, returning `{:ok, state}` or `{:error, reason}`.

  Invalid ops (unknown uid, duplicate insert, bad position) return an error
  instead of raising — the caller decides whether to log or crash.

  ## Examples

      iex> alias BrandoAdmin.Components.Form.BlockField.Ops
      iex> {:ok, state} = Ops.apply_op(Ops.new([]), {:insert, "a", 0, %{}})
      iex> state.order
      ["a"]

  """
  @spec apply_op(t(), op()) :: {:ok, t()} | {:error, term()}
  def apply_op(%__MODULE__{} = state, {:insert, uid, at, params}) when is_map(params) do
    cond do
      known?(state, uid) ->
        {:error, {:duplicate_uid, uid}}

      not valid_position?(at) ->
        {:error, {:bad_position, at}}

      true ->
        {order, keys} = place(state.order, state.keys, uid, at)
        state = %{state | order: order, keys: keys, statuses: Map.put(state.statuses, uid, :inserted)}

        {:ok, register_params(state, uid, params, :entry_block)}
    end
  end

  # A known uid arriving as insert_child is a reparent (the outline's
  # cross-parent extract→insert lands here with the extracted block's uid) —
  # move it and refresh its diff instead of erroring.
  def apply_op(%__MODULE__{} = state, {:insert_child, parent_uid, uid, at, params}) when is_map(params) do
    cond do
      not known?(state, parent_uid) ->
        {:error, {:unknown_uid, parent_uid}}

      not valid_position?(at) ->
        {:error, {:bad_position, at}}

      known?(state, uid) ->
        with {:ok, state} <- apply_op(state, {:move_to_parent, uid, parent_uid, at}) do
          {:ok, register_params(state, uid, params, :block)}
        end

      true ->
        {:ok, attach_child(state, parent_uid, uid, at, params)}
    end
  end

  # Roots and children carry different diff semantics, so `:update` stores them
  # differently — see `register_params/5`.
  def apply_op(%__MODULE__{} = state, {:update, uid, params}) when is_map(params) do
    cond do
      not known?(state, uid) -> {:error, {:unknown_uid, uid}}
      uid in state.order -> {:ok, register_params(state, uid, params, :entry_block)}
      true -> {:ok, register_params(state, uid, params, :block, merge?: true)}
    end
  end

  # One field of one block, last arrival wins. The rest of the block's diff
  # is left alone, so two editors in different fields of one block both keep
  # their changes.
  def apply_op(%__MODULE__{} = state, {:set_field, uid, path, value, _rev}) when is_list(path) and path != [],
    do: set_fields(state, uid, [{path, value}])

  # The fields one event changed together (a widget that sets a value beside
  # its own, rows moved by dragging), each set on its own.
  def apply_op(%__MODULE__{} = state, {:set_fields, uid, changes, _rev}) when is_list(changes),
    do: set_fields(state, uid, changes)

  def apply_op(%__MODULE__{} = state, {:move, uid, to}) do
    cond do
      uid not in state.order ->
        {:error, {:unknown_uid, uid}}

      not valid_position?(to) or to == :end ->
        {:error, {:bad_position, to}}

      true ->
        {order, keys} = place(List.delete(state.order, uid), state.keys, uid, to)
        {:ok, %{state | order: order, keys: keys}}
    end
  end

  def apply_op(%__MODULE__{} = state, {:reorder, uids}) when is_list(uids) do
    order = sanitize_order(uids, state.order)
    {:ok, %{state | order: order, keys: FractionalKey.rekey(order, state.keys)}}
  end

  def apply_op(%__MODULE__{} = state, {:reorder_children, parent_uid, uids}) when is_list(uids) do
    if known?(state, parent_uid) do
      order = sanitize_order(uids, Map.get(state.child_order, parent_uid, []))

      {:ok,
       %{
         state
         | child_order: Map.put(state.child_order, parent_uid, order),
           keys: FractionalKey.rekey(order, state.keys)
       }}
    else
      {:error, {:unknown_uid, parent_uid}}
    end
  end

  def apply_op(%__MODULE__{} = state, {:move_to_parent, uid, new_parent_uid, at}) do
    cond do
      not known?(state, uid) ->
        {:error, {:unknown_uid, uid}}

      not known?(state, new_parent_uid) ->
        {:error, {:unknown_uid, new_parent_uid}}

      uid == new_parent_uid or new_parent_uid in descendants(state, uid) ->
        {:error, {:cyclic_move, uid}}

      not valid_position?(at) ->
        {:error, {:bad_position, at}}

      true ->
        state = detach(state, uid)
        {siblings, keys} = place(Map.get(state.child_order, new_parent_uid, []), state.keys, uid, at)

        {:ok,
         %{
           state
           | parents: Map.put(state.parents, uid, new_parent_uid),
             child_order: Map.put(state.child_order, new_parent_uid, siblings),
             keys: keys
         }}
    end
  end

  # One operation replaces an empty destination and updates the retained slot.
  # Its children never move, keeping their IDs, edits and snapshot ownership.
  def apply_op(%__MODULE__{} = state, {:remap_slot, uid, destination_uid, params}) do
    valid_destination? =
      is_nil(destination_uid) ||
        (destination_uid != uid && known?(state, destination_uid) &&
           state.parents[uid] == state.parents[destination_uid] &&
           Map.get(state.child_order, destination_uid, []) == [])

    if known?(state, uid) && Map.has_key?(state.parents, uid) && valid_destination? do
      {:ok, state} = apply_op(state, {:update, uid, params})
      if destination_uid, do: apply_op(state, {:delete, destination_uid}), else: {:ok, state}
    else
      {:error, :invalid_slot_remap}
    end
  end

  def apply_op(%__MODULE__{} = state, {:delete, uid}) do
    if known?(state, uid) do
      doomed = [uid | descendants(state, uid)]
      newly_deleted = Enum.filter(doomed, &(state.statuses[&1] == :persisted))

      state = detach(state, uid)

      {:ok,
       %{
         state
         | parents: Map.drop(state.parents, doomed),
           child_order: Map.drop(state.child_order, doomed),
           diffs: Map.drop(state.diffs, doomed),
           statuses: Map.drop(state.statuses, doomed),
           db_ids: Map.drop(state.db_ids, doomed),
           keys: Map.drop(state.keys, doomed),
           deleted: state.deleted ++ newly_deleted
       }}
    else
      {:error, {:unknown_uid, uid}}
    end
  end

  # Delete undo: a `bin_snapshot/2` taken before the delete. An op rather than
  # a direct call so it reaches the session and every other editor in order.
  def apply_op(%__MODULE__{} = state, {:restore, %{uids: [_ | _], location: _} = snapshot}),
    do: restore_snapshot(state, snapshot)

  # Applying a recovery copy replaces the field's whole state in one step.
  def apply_op(%__MODULE__{}, {:replace_state, %__MODULE__{} = state}), do: {:ok, state}

  # A recovery copy (or any state built on `base`) applied to a field others
  # share: its changes are carried onto what the field holds now, so their
  # unsaved work stays (`carry/3`).
  def apply_op(%__MODULE__{} = state, {:carry, %__MODULE__{} = carried, %__MODULE__{} = base}) do
    {state, _conflicts} = carry(carried, base, state)
    {:ok, state}
  end

  def apply_op(%__MODULE__{}, op), do: {:error, {:unknown_op, op}}

  @doc """
  All known uids under `uid`, depth first.
  """
  @spec descendants(t(), uid()) :: [uid()]
  def descendants(%__MODULE__{} = state, uid) do
    children = Map.get(state.child_order, uid, [])
    Enum.flat_map(children, &[&1 | descendants(state, &1)])
  end

  @doc """
  The blocks an op changes: whose work a block holds, should another write
  remove it (`Brando.EditSession` keeps this per editor).
  """
  @spec op_uids(op()) :: [uid()]
  def op_uids({kind, uid, _}) when kind in [:update, :move], do: [uid]
  def op_uids({:insert, uid, _at, _params}), do: [uid]
  def op_uids({:set_field, uid, _path, _value, _rev}), do: [uid]
  def op_uids({:set_fields, uid, _changes, _rev}), do: [uid]
  def op_uids({:insert_child, parent, uid, _at, _params}), do: [parent, uid]
  def op_uids({:move_to_parent, uid, parent, _at}), do: [uid, parent]
  def op_uids({:remap_slot, uid, _destination, _params}), do: [uid]
  def op_uids({:reorder_children, parent, _uids}), do: [parent]
  def op_uids(_op), do: []

  @doc """
  Whether `uid` is a block the state knows about (any nesting level).
  """
  @spec known?(t(), uid()) :: boolean()
  def known?(%__MODULE__{} = state, uid), do: Map.has_key?(state.statuses, uid)

  @doc """
  The root uid of the tree `uid` belongs to (`uid` itself for roots).
  """
  @spec root_of(t(), uid()) :: uid()
  def root_of(%__MODULE__{} = state, uid) do
    case Map.get(state.parents, uid) do
      nil -> uid
      parent_uid -> root_of(state, parent_uid)
    end
  end

  # Content + structure of `uid`'s subtree: param diffs (never changesets or
  # forms), parent links and per-parent child order, plus the DFS uid order so
  # a restore can apply parents before children.
  defp subtree_snapshot(%__MODULE__{} = state, uid) do
    uids = [uid | descendants(state, uid)]

    %{
      uids: uids,
      diffs: Map.take(state.diffs, uids),
      parents: Map.take(state.parents, uids),
      child_order: Map.take(state.child_order, uids)
    }
  end

  @doc """
  A restorable-bin snapshot of `uid`'s subtree — capture BEFORE applying
  `{:delete, uid}`, restore with `restore_snapshot/2`.

  Carries the subtree's diffs and structure plus everything a delete
  destroys: per-uid statuses and db ids (so a
  restored persisted block keeps matching its rows at save instead of
  re-inserting them) and the block's location — `{:root, index}` or
  `{:child, parent_uid, index}` — so the restore can reattach it where
  it was.

  Snapshots don't survive a save: the save deletes the underlying rows,
  so the captured db ids go stale (drop the bin when the store re-seeds).
  """
  @spec bin_snapshot(t(), uid()) :: map()
  def bin_snapshot(%__MODULE__{} = state, uid) do
    uids = [uid | descendants(state, uid)]

    location =
      case Map.get(state.parents, uid) do
        nil ->
          {:root, Enum.find_index(state.order, &(&1 == uid)) || length(state.order)}

        parent_uid ->
          siblings = Map.get(state.child_order, parent_uid, [])
          {:child, parent_uid, Enum.find_index(siblings, &(&1 == uid)) || length(siblings)}
      end

    state
    |> subtree_snapshot(uid)
    |> Map.merge(%{
      location: location,
      statuses: Map.take(state.statuses, uids),
      db_ids: Map.take(state.db_ids, uids),
      keys: Map.take(state.keys, uids)
    })
  end

  @doc """
  Undo a delete by re-applying a `bin_snapshot/2`.

  The whole subtree comes back exactly as captured — structure, diffs,
  statuses, db ids — reattached at its original (clamped) position, and its
  persisted uids leave the `deleted` list. Errors if any snapshot uid is
  already known (already restored, or resurrected by another editor) or if
  a child snapshot's parent is gone — restore newest-first and parents
  reappear before their children's snapshots apply.

  ## Examples

      iex> alias BrandoAdmin.Components.Form.BlockField.Ops
      iex> state = Ops.new(["a", "b"])
      iex> snapshot = Ops.bin_snapshot(state, "a")
      iex> {:ok, state} = Ops.apply_op(state, {:delete, "a"})
      iex> state.deleted
      ["a"]
      iex> {:ok, restored} = Ops.apply_op(state, {:restore, snapshot})
      iex> {restored.order, restored.deleted}
      {["a", "b"], []}

  """
  @spec restore_snapshot(t(), map()) :: {:ok, t()} | {:error, term()}
  def restore_snapshot(%__MODULE__{} = state, %{uids: [uid | _] = uids, location: location} = snapshot) do
    cond do
      Enum.any?(uids, &known?(state, &1)) ->
        {:error, {:duplicate_uid, uid}}

      not location_known?(state, location) ->
        {:child, parent_uid, _} = location
        {:error, {:unknown_parent, parent_uid}}

      true ->
        state = %{
          state
          | parents: Map.merge(state.parents, snapshot.parents),
            child_order: Map.merge(state.child_order, snapshot.child_order),
            diffs: Map.merge(state.diffs, snapshot.diffs),
            statuses: Map.merge(state.statuses, snapshot.statuses),
            db_ids: Map.merge(state.db_ids, snapshot.db_ids),
            keys: Map.merge(state.keys, Map.get(snapshot, :keys, %{})),
            deleted: Enum.reject(state.deleted, &(&1 in uids))
        }

        {:ok, reattach(state, uid, restore_position(snapshot, uid, location))}
    end
  end

  defp location_known?(_state, {:root, _at}), do: true
  defp location_known?(state, {:child, parent_uid, _at}), do: known?(state, parent_uid)

  # Back between the neighbours it had (its old key), or at its old index
  # when the snapshot has no key.
  defp restore_position(snapshot, uid, location) do
    case {Map.get(snapshot, :keys, %{}), location} do
      {%{^uid => key}, {:root, _at}} -> {:root, {:key, key}}
      {%{^uid => key}, {:child, parent_uid, _at}} -> {:child, parent_uid, {:key, key}}
      _ -> location
    end
  end

  defp reattach(state, uid, {:root, at}) do
    {order, keys} = place(state.order, Map.delete(state.keys, uid), uid, at)
    %{state | order: order, keys: keys}
  end

  defp reattach(state, uid, {:child, parent_uid, at}) do
    {siblings, keys} = place(Map.get(state.child_order, parent_uid, []), Map.delete(state.keys, uid), uid, at)

    %{
      state
      | parents: Map.put(state.parents, uid, parent_uid),
        child_order: Map.put(state.child_order, parent_uid, siblings),
        keys: keys
    }
  end

  @doc """
  Materialize save-ready entry-block params for one root uid.

  The tree is authoritative: `"sequence"` comes from list position,
  `"block" -> "children"` is rebuilt recursively from `child_order` (any
  `"children"`/`"sequence"` keys inside stored diffs are discarded), db ids
  are re-attached so `cast_assoc` matches existing rows. Untouched persisted
  blocks materialize as id+sequence-only params — empty updates, no SQL.

  Returns `{:error, {:unknown_uid, uid}}` for uids outside `order`.
  """
  @spec materialize_root(t(), uid()) :: {:ok, params()} | {:error, term()}
  def materialize_root(%__MODULE__{} = state, uid) do
    if uid in state.order do
      diff = Map.get(state.diffs, uid, %{})
      {entry_block_id, block_id} = Map.get(state.db_ids, uid, {nil, nil})
      index = Enum.find_index(state.order, &(&1 == uid))

      block_params =
        diff
        |> Map.get("block", %{})
        |> materialize_block(state, uid, block_id)
        # root block rows carry the same sequence stamp as their join row
        |> Map.put("sequence", index)

      params =
        diff
        |> Map.put("sequence", index)
        |> Map.put("block", block_params)
        |> put_new_id(entry_block_id)

      {:ok, params}
    else
      {:error, {:unknown_uid, uid}}
    end
  end

  @doc """
  Materialize block-shaped params for one CHILD uid, subtree included.

  The child equivalent of `materialize_root/2`. Used by the outline's
  cross-parent move, which has to rebuild the moved child under its new
  parent: the store is the only place that holds the child's *current*
  content, since the source parent only ever keeps a mount-time seed form
  (`@children_forms`) and the child's own live_component is destroyed by the
  move (its id embeds the parent's id, so a new parent means a new CID).

  Returns `{:error, {:unknown_uid, uid}}` for uids the store doesn't know,
  and for roots — those go through `materialize_root/2`.
  """
  @spec materialize_child(t(), uid()) :: {:ok, params()} | {:error, term()}
  def materialize_child(%__MODULE__{} = state, uid) do
    if known?(state, uid) and uid not in state.order do
      {_entry_block_id, block_id} = Map.get(state.db_ids, uid, {nil, nil})

      params =
        state.diffs
        |> Map.get(uid, %{})
        |> materialize_block(state, uid, block_id)

      {:ok, params}
    else
      {:error, {:unknown_uid, uid}}
    end
  end

  defp materialize_block(block_diff, state, uid, block_id) do
    children =
      state.child_order
      |> Map.get(uid, [])
      |> Enum.with_index()
      |> Enum.map(fn {child_uid, idx} ->
        {_, child_block_id} = Map.get(state.db_ids, child_uid, {nil, nil})

        state.diffs
        |> Map.get(child_uid, %{})
        |> materialize_block(state, child_uid, child_block_id)
        |> Map.put("sequence", idx)
        |> Map.put("uid", child_uid)
      end)

    block_diff
    |> Map.put("uid", uid)
    # editor-stamped render artifacts must not dirty block rows at save
    |> Map.drop(["sequence", "rendered_html", "rendered_at"])
    |> put_children(children)
    |> put_new_id(block_id)
    |> fill_rel_ids(Map.get(state.rel_ids, uid))
  end

  # ALWAYS emit "children" — the tree is authoritative, including emptiness
  # (`from_entry_blocks`/insert registration know every child). Dropping the
  # key when empty silently kept rows alive: deleting a parent's last child
  # never persisted, and a child moved to another parent stayed (duplicated)
  # under the old one. An empty list over loaded-empty data is a no-op cast.
  defp put_children(params, children), do: Map.put(params, "children", children)

  # A diff can carry `"id" => nil` (the snapshot of a block that was new when
  # it was taken, replayed after a save gave it a row): the row's id wins.
  defp put_new_id(params, nil), do: params

  defp put_new_id(params, id) do
    case params do
      %{"id" => existing} when existing not in [nil, ""] -> params
      _ -> Map.put(params, "id", id)
    end
  end

  @doc """
  Convert a changeset's changes into a string-keyed params map, recursively.

  This is the diff format stored per uid: only changed fields appear
  (`cast/4` skips absent keys, so re-casting the diff over persisted data
  reproduces the changeset cheaply). Nested assoc/embed changesets become
  nested maps/lists; children marked `:replace`/`:delete` are dropped —
  re-casting the remaining list expresses the removal. Each nested child
  carries its primary key (taken from `data` when set), so `cast_assoc`
  matches existing rows instead of replace+insert.

  Non-changeset values (scalars, but also structs placed with `put_change`)
  pass through untouched — materialization decides how to apply them.

  ## Examples

      iex> alias BrandoAdmin.Components.Form.BlockField.Ops
      iex> cs = Ecto.Changeset.change(%Brando.Content.Block{}, %{uid: "abc"})
      iex> Ops.changes_to_params(cs)
      %{"uid" => "abc"}

  """
  @spec changes_to_params(Changeset.t()) :: params()
  def changes_to_params(%Changeset{} = changeset) do
    Enum.reduce(changeset.changes, %{}, fn {field, value}, acc ->
      case change_value(value) do
        :drop -> acc
        converted -> Map.put(acc, to_string(field), converted)
      end
    end)
    |> Brando.Drafts.Params.preserve_invalid(changeset)
  end

  @doc """
  The right diff for a block form's changeset: persisted records diff by
  changes (`changes_to_params/1`), NEW records snapshot their full applied
  state (`snapshot_params/1`).

  New-record changesets get their content from pre-populated `data`
  (`build_block/5` and friends), so a changes-only diff would silently drop
  `module_id`, vars, refs — everything the builder set as data.
  """
  @spec block_diff_params(Changeset.t()) :: params()
  def block_diff_params(%Changeset{data: %{id: nil}} = changeset), do: snapshot_params(changeset)
  def block_diff_params(%Changeset{} = changeset), do: changes_to_params(changeset)

  @doc """
  Params for a saved child block moved to another parent, from its full
  snapshot (`snapshot_params/1`).

  Under its new parent the block is a new row (`cast_assoc` does not take a
  child's id), so it has to carry everything it holds, not only what
  changed, and none of the old rows' ids: its refs, vars, table rows,
  identifiers and children come along as new rows. A ref's gallery stays
  the same gallery (`gallery_id`): the old ref goes with the old row. A
  gallery with unsaved changes (its ref's uid in `changed_galleries`) can
  only bring them as a new gallery; the saved one is left unused.
  """
  @spec moved_params(params(), MapSet.t()) :: params()
  def moved_params(%{} = block, changed_galleries \\ MapSet.new()) do
    block
    |> Map.drop(["id", "parent_id"])
    |> update_rows("refs", &(&1 |> keep_gallery(changed_galleries) |> Map.drop(["id", "block_id"])))
    |> update_rows("vars", &moved_var/1)
    |> update_rows("table_rows", fn row ->
      row
      |> Map.drop(["id", "block_id"])
      |> update_rows("vars", &moved_var/1)
    end)
    |> update_rows("block_identifiers", &Map.drop(&1, ["id", "block_id"]))
    |> update_rows("children", &moved_params(&1, changed_galleries))
  end

  # A var's gallery is one picked from the library: it goes by its id.
  defp moved_var(var) do
    var =
      case var do
        %{"gallery" => %{"id" => id}} when id not in [nil, ""] ->
          var |> Map.delete("gallery") |> Map.put("gallery_id", id)

        _ ->
          var
      end

    Map.drop(var, ["id", "block_id", "table_row_id"])
  end

  defp update_rows(params, key, fun) do
    case params do
      %{^key => rows} when is_list(rows) -> Map.put(params, key, Enum.map(rows, &if(is_map(&1), do: fun.(&1), else: &1)))
      _ -> params
    end
  end

  defp keep_gallery(%{"gallery" => %{"id" => id} = gallery} = ref, changed) when id not in [nil, ""] do
    if MapSet.member?(changed, ref["uid"]) do
      gallery = gallery |> Map.delete("id") |> update_rows("gallery_objects", &Map.drop(&1, ["id", "gallery_id"]))
      Map.put(ref, "gallery", gallery)
    else
      ref |> Map.delete("gallery") |> Map.put("gallery_id", id)
    end
  end

  defp keep_gallery(ref, _changed), do: ref

  @doc """
  Full castable params snapshot of a changeset's applied state.
  """
  @spec snapshot_params(Changeset.t()) :: params()
  def snapshot_params(%Changeset{} = changeset) do
    params = changeset |> Changeset.apply_changes() |> struct_to_params()
    Brando.Drafts.Params.preserve_invalid_tree(params, changeset)
  end

  # Schema fields (embeds included) + the owned assoc trees. Media belongs_to
  # associations stay out — `image_id`/`video_id`/`file_id` cover them, because
  # those rows exist in the library before a ref ever points at one.
  #
  # `:gallery` is the exception, and it has to be here. A gallery has no
  # independent existence: `Ref.ref_changeset/3` `cast_assoc`s it, so a gallery
  # picked or uploaded into a ref is *created by the save*. Leaving it out of
  # the snapshot meant a new (never-saved) block lost its gallery entirely —
  # its `gallery_id` is still nil at that point, so the FK covered nothing.
  # A persisted block was unaffected: `changes_to_params/1` ships changes, and
  # `:gallery` is one. `:gallery_objects` rides along for the same reason —
  # without it the gallery would save as an empty one.
  @snapshot_assocs [
    :block,
    :children,
    :vars,
    :refs,
    :table_rows,
    :block_identifiers,
    :gallery,
    :gallery_objects
  ]

  defp struct_to_params(%mod{} = struct) do
    field_params =
      Map.new(mod.__schema__(:fields), fn field ->
        {to_string(field), struct |> Map.get(field) |> change_value()}
      end)

    field_params =
      if mod == Brando.Content.Block && struct.slot_remap,
        do: Map.put(field_params, "slot_remap", struct.slot_remap),
        else: field_params

    mod.__schema__(:associations)
    |> Enum.filter(&(&1 in @snapshot_assocs))
    |> Enum.reduce(field_params, fn assoc, acc ->
      case Map.get(struct, assoc) do
        %Ecto.Association.NotLoaded{} ->
          acc

        # A cleared association is expressed by its FK going nil, which the
        # field params already carry — emitting the assoc as nil as well would
        # take the FK's place below and say nothing.
        nil ->
          acc

        value ->
          put_assoc_param(acc, struct, mod, assoc, value)
      end
    end)
  end

  defp put_assoc_param(params, struct, mod, assoc, value) do
    if stale_owner?(struct, mod, assoc, value),
      do: params,
      else: params |> drop_owner_key(mod, assoc) |> Map.put(to_string(assoc), change_value(value))
  end

  # A belongs_to still loaded from the row while its FK was changed (a
  # gallery picked or cleared on a saved var): the FK says what it is now.
  defp stale_owner?(struct, mod, assoc, %{id: id}) when not is_nil(id) do
    case mod.__schema__(:association, assoc) do
      %Ecto.Association.BelongsTo{owner_key: owner_key} -> Map.get(struct, owner_key) != id
      _ -> false
    end
  end

  defp stale_owner?(_struct, _mod, _assoc, _value), do: false

  # `cast_assoc` writes the foreign key itself, and Ecto refuses to accept both
  # at once — "cannot change belongs_to association `gallery` because there is
  # already a change setting its foreign key `gallery_id`". So an emitted
  # belongs_to takes its FK's place in the params rather than sitting beside it.
  defp drop_owner_key(params, mod, assoc) do
    case mod.__schema__(:association, assoc) do
      %Ecto.Association.BelongsTo{owner_key: owner_key} -> Map.delete(params, to_string(owner_key))
      _ -> params
    end
  end

  ## Sessions and replicas

  @doc """
  What a base state says about the database rows it was loaded from: the
  structure and the db ids, nothing else.

  Two editors that loaded the same rows get equal signatures, so the edit
  session uses this to tell whether a joining editor's rows are the ones its
  own state was built on.
  """
  @spec signature(t()) :: term()
  def signature(%__MODULE__{} = state), do: {state.order, state.parents, state.child_order, state.db_ids}

  @doc """
  Whether `state` holds nothing that differs from `base`: no diffs, no
  inserted or deleted blocks and the same structure.
  """
  @spec pristine?(t(), t()) :: boolean()
  def pristine?(%__MODULE__{} = state, %__MODULE__{} = base) do
    state.deleted == [] and Enum.all?(state.diffs, fn {_uid, diff} -> diff == %{} end) and
      signature(state) == signature(base) and state.statuses == base.statuses
  end

  @doc """
  The roots whose mounted forms no longer show `after` correctly, given that
  they showed `before`: roots present in both whose subtree's diffs,
  structure, statuses or db ids changed. Roots that appeared or disappeared
  are not included; the caller handles them from `order`.

  `uids` narrows the comparison to the blocks an op names, when known.
  """
  @spec changed_roots(t(), t(), [uid()] | :all) :: [uid()]
  def changed_roots(%__MODULE__{} = before, %__MODULE__{} = after_state, uids \\ :all) do
    candidates =
      case uids do
        :all -> after_state.order
        uids -> uids |> Enum.filter(&known?(after_state, &1)) |> Enum.map(&root_of(after_state, &1)) |> Enum.uniq()
      end

    Enum.filter(candidates, fn root ->
      root in before.order and subtree_view(before, root) != subtree_view(after_state, root)
    end)
  end

  defp subtree_view(state, root) do
    uids = [root | descendants(state, root)]

    {uids, Map.take(state.diffs, uids), Map.take(state.child_order, uids), Map.take(state.statuses, uids),
     Map.take(state.db_ids, uids)}
  end

  @doc """
  Carry the unsaved work in `state` onto `new_base`, the rows as someone
  else just saved them (an Assistant proposal, an activated revision, a save
  made outside the session).

  `state` was built on `old_base`. What the editors did since is expressed
  again as ordinary ops against the new rows: their deletes, their new
  blocks (with whole subtrees), their field changes and, if they moved
  blocks, their order. Blocks the other writer added keep their place
  among their neighbours. Field changes merge as diffs do: an editor's
  changed fields win, fields they did not touch take the new values.

  When `new_base` is live state rather than rows, a block's diff merges
  with the one held there: the target's other fields stay. A list in it
  keeps the carried side's rows (a recovery copy: its lists are whole),
  unless `lists: :merge` is given (a rejoin, `Brando.EditSession.Data`):
  then the block's row lists merge by row, keeping each side's additions,
  removals and changes (`carry_list/4`).

  Returns `{state, conflicts}`. A conflict is unsaved work on a block the
  other writer deleted; it cannot be replayed onto rows that no longer
  exist, so it is reported (the editor's recovery copy keeps it).
  """
  @spec carry(t(), t(), t(), keyword()) :: {t(), [uid()]}
  def carry(%__MODULE__{} = state, %__MODULE__{} = old_base, %__MODULE__{} = new_base, opts \\ []) do
    lists = Keyword.get(opts, :lists, :carried)
    rows = Keyword.get(opts, :rows, new_base)
    acc = {adopt_keys(new_base, state), []}
    acc = Enum.reduce(state.deleted, acc, &carry_delete/2)
    acc = state |> inserted_tops() |> Enum.reduce(acc, &carry_insert(&1, &2, state))

    acc =
      state.diffs
      |> Enum.filter(fn {uid, diff} -> diff != %{} and state.statuses[uid] == :persisted end)
      |> Enum.sort_by(fn {uid, _} -> depth(state, uid) end)
      |> Enum.reduce(acc, &carry_update(&1, &2, state, {lists, old_base, rows}))

    acc = state |> moved_children(old_base) |> Enum.reduce(acc, &carry_move(&1, &2, state))

    {carried, conflicts} = acc
    carried = carry_order(carried, state, old_base, new_base)
    {carried, Enum.reverse(conflicts)}
  end

  # Persisted blocks the editors moved to another parent.
  defp moved_children(state, old_base) do
    state.parents
    |> Enum.filter(fn {uid, parent} ->
      state.statuses[uid] == :persisted and Map.has_key?(old_base.statuses, uid) and old_base.parents[uid] != parent
    end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort_by(&depth(state, &1))
  end

  defp carry_move(uid, {acc, conflicts}, state) do
    parent = state.parents[uid]

    case known?(acc, uid) and known?(acc, parent) and apply_op(acc, {:move_to_parent, uid, parent, :end}) do
      {:ok, acc} -> {acc, conflicts}
      _ -> {acc, [uid | conflicts]}
    end
  end

  defp carry_delete(uid, {acc, conflicts}) do
    if known?(acc, uid), do: {carry_apply(acc, {:delete, uid}), conflicts}, else: {acc, conflicts}
  end

  defp carry_apply(acc, op) do
    case apply_op(acc, op) do
      {:ok, acc} -> acc
      {:error, _reason} -> acc
    end
  end

  # The top of every subtree an editor added: an inserted block whose parent
  # (if any) is not itself inserted. Its descendants travel inside it.
  defp inserted_tops(state) do
    roots = Enum.filter(state.order, &(state.statuses[&1] == :inserted))

    children =
      state.parents
      |> Enum.filter(fn {uid, parent} -> state.statuses[uid] == :inserted and state.statuses[parent] != :inserted end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort_by(&depth(state, &1))

    roots ++ children
  end

  defp carry_insert(uid, {acc, conflicts}, state) do
    cond do
      known?(acc, uid) ->
        {acc, conflicts}

      uid in state.order ->
        {:ok, params} = materialize_root(state, uid)
        {carry_apply(acc, {:insert, uid, :end, Map.delete(params, "sequence")}), conflicts}

      known?(acc, state.parents[uid]) ->
        {:ok, params} = materialize_child(state, uid)
        at = state.child_order |> Map.get(state.parents[uid], []) |> Enum.find_index(&(&1 == uid))
        {carry_apply(acc, {:insert_child, state.parents[uid], uid, at || :end, params}), conflicts}

      true ->
        {acc, [uid | conflicts]}
    end
  end

  defp carry_update({uid, diff}, {acc, conflicts}, state, {lists, old_base, rows}) do
    if known?(acc, uid) do
      # Rows just loaded hold no diff, but live session state can (a
      # rejoin, a recovery copy), so the diff is merged with the one held
      # there. An `:update` replaces a root's diff and merges a child's onto
      # its own, which the merged diff already holds. A row one side named
      # by uid while it was new, and the other by the id a save gave it, is
      # one row: both are named by id first.
      root? = uid in acc.order

      ids =
        [state, rows, acc] |> Enum.map(&Map.get(&1.rel_ids, uid, %{})) |> Enum.reduce(&Map.merge(&2, &1))

      now = acc.diffs |> Map.get(uid, %{}) |> fill_diff_ids(root?, ids)
      diff = fill_diff_ids(diff, root?, ids)

      diff =
        case lists do
          :merge ->
            now |> with_saved_rows(diff, root?, rows, uid) |> carry_merge(diff, {:block, base_row_ids(old_base, uid)})

          :carried ->
            deep_merge_params(now, diff)
        end

      {carry_apply(acc, {:update, uid, diff}), conflicts}
    else
      {acc, [uid | conflicts]}
    end
  end

  # A rejoiner's diff onto the diff the session holds for the block. The
  # fields the rejoiner's diff has win; the session's other fields stay.
  # The block's lists of rows (refs, vars, table rows) merge by row
  # (`carry_list/4`), because a diff holds a whole list as its editor had
  # it: a cell edit names its row in the list as it was then.
  #
  # Both sides were built on the same rows, which hold no diff, so a field
  # the rejoiner's diff lacks is one its editor did not change: the
  # session's value stays. (An editor who set a field back to its saved
  # value with a whole-form `:update` sends no key for it, which reads the
  # same.)
  #
  # `at` is `{:block, base_ids}` in the block's own params (a root's
  # `"block"` included), whose lists are its rows, and `:nested` below.
  defp carry_merge(now, value, at)
       when is_map(now) and is_map(value) and not is_struct(now) and not is_struct(value),
       do: Map.merge(now, value, &carry_merge(&1, &2, &3, at))

  defp carry_merge(_now, value, _at), do: value

  defp carry_merge(key, now, value, at) when is_list(now) and is_list(value), do: carry_list(key, now, value, at)
  defp carry_merge("block", now, value, {:block, _} = at), do: carry_merge(now, value, at)
  defp carry_merge(_key, now, value, _at), do: carry_merge(now, value, :nested)

  # A list the rejoiner's diff has and the session's lacks is the rows as
  # they are saved, in their order (`rows`): rows saved while the rejoiner
  # was away are among them, and its list would drop them.
  defp with_saved_rows(now, diff, root?, rows, uid) do
    saved = saved_row_lists(rows, uid)
    {now_block, diff_block} = if root?, do: {Map.get(now, "block", %{}), Map.get(diff, "block", %{})}, else: {now, diff}

    filled =
      Enum.reduce(saved, now_block, fn {key, ids}, block ->
        if is_list(diff_block[key]) and not Map.has_key?(block, key),
          do: Map.put(block, key, Enum.map(ids, &%{"id" => &1})),
          else: block
      end)

    if root?, do: Map.put(now, "block", filled), else: filled
  end

  defp saved_row_lists(%__MODULE__{} = rows, uid), do: Map.get(rows.row_order, uid, %{})

  # The ids of the rows the rejoiner's rows had, by relation
  # (`row_order`): a saved row it lacks that is not among them was saved
  # while it was away, not removed by it.
  defp base_row_ids(%__MODULE__{} = base, uid) do
    base.row_order |> Map.get(uid, %{}) |> Map.new(fn {key, ids} -> {key, MapSet.new(ids, &to_string/1)} end)
  end

  # `current` is the session's list, `carried` the rejoiner's. Both were
  # built on the same rows, and every saved row has an id. Neither holds
  # the saved rows, so a row one side changed cannot be told from one it
  # left as it was (a list op leaves every row whole, a reorder gives each
  # a new sequence): a saved row stays when both lists have it, and a
  # saved row either side removed is removed, as a list op's removal is
  # (`merge_list/4`). A row with no id is new: each side's stay. A row both
  # have merges field by field, the rejoiner's fields winning. Items that
  # cannot be named are set whole, as the rejoiner has them.
  #
  # A saved row the rejoiner's own rows did not have (`base_row_ids/2`) was
  # saved while it was away: it stays.
  #
  # Below a row (`:nested`), an item without an id may be named by id on
  # the other side (a gallery object by its image, before a save gave it a
  # row), and only the block's own rows have ids to resolve that by
  # (`fill_diff_ids/3`): such a list is the rejoiner's.
  defp carry_list(key, current, carried, at) do
    named = Enum.map(current, &row_key(&1, key))
    carried_named = Enum.map(carried, &row_key(&1, key))

    cond do
      :none in named or :none in carried_named or repeated?(named) or repeated?(carried_named) ->
        carried

      at == :nested and not Enum.all?(current ++ carried, &saved_row?/1) ->
        deep_merge_params(current, carried)

      true ->
        known = with {:block, ids} <- at, do: Map.get(ids, key)
        merge_rows(key, current, named, carried, carried_named, known)
    end
  end

  defp merge_rows(key, current, named, carried, carried_named, known) do
    in_current = MapSet.new(named)
    current_by = Map.new(Enum.zip(named, current))

    before =
      (carried ++ current)
      |> Enum.filter(&(saved_row?(&1) and (not is_struct(known, MapSet) or MapSet.member?(known, to_string(&1["id"])))))
      |> Enum.map(&identity_only(&1, key))
      |> Enum.uniq()

    # The rejoiner's saved rows the session no longer has are left out; the
    # session's saved rows the rejoiner lacks are in `before`, so they stay
    # out too; the new rows of both come through.
    after_list =
      carried
      |> Enum.zip(carried_named)
      |> Enum.reject(fn {row, k} -> saved_row?(row) and k not in in_current end)
      |> Enum.map(&elem(&1, 0))

    before
    |> merge_list(after_list, current, key)
    |> Enum.map(fn item ->
      case Map.fetch(current_by, row_key(item, key)) do
        {:ok, now} -> carry_merge(now, item, :nested)
        :error -> item
      end
    end)
  end

  @doc """
  What `Brando.EditSession.Data` logs of a rejoin (`carried`) to replay
  onto rows a save in flight writes, given `merged`, what the rejoin made
  of the session's state.

  Replayed as it was, a list in `carried` would leave out rows the merge
  kept; the save writes them, and the next save would delete them. So each
  list holds the merged rows in the merged order: the rejoiner's rows as
  it had them, the others by their identity alone, which carries no change.
  """
  @spec rejoin_log(t(), t()) :: t()
  def rejoin_log(%__MODULE__{} = carried, %__MODULE__{} = merged) do
    diffs =
      Map.new(carried.diffs, fn {uid, diff} ->
        merged_diff = Map.get(merged.diffs, uid, %{})
        root? = uid in carried.order
        # named as the merge named them: a row the rejoiner had new may be
        # a row with an id by now
        ids = Map.merge(Map.get(carried.rel_ids, uid, %{}), Map.get(merged.rel_ids, uid, %{}))
        diff = fill_diff_ids(diff, root?, ids)

        if root?,
          do: {uid, Map.update(diff, "block", %{}, &log_lists(&1, Map.get(merged_diff, "block", %{})))},
          else: {uid, log_lists(diff, merged_diff)}
      end)

    %{carried | diffs: diffs}
  end

  defp log_lists(%{} = diff, %{} = merged) when not is_struct(diff) and not is_struct(merged) do
    Map.new(diff, fn
      {key, list} when is_list(list) -> {key, log_list(key, list, merged[key])}
      {key, %{} = map} -> {key, log_lists(map, Map.get(merged, key))}
      pair -> pair
    end)
  end

  defp log_lists(diff, _merged), do: diff

  # The merged rows in the merged order: the rejoiner's own as it had them
  # (with the lists inside them built the same way), the others by their
  # identity alone.
  defp log_list(key, carried, merged) when is_list(merged) do
    own = carried |> Enum.reject(&(row_key(&1, key) == :none)) |> Map.new(&{row_key(&1, key), &1})

    if Enum.any?(merged, &(row_key(&1, key) == :none)) or repeated_keys?(carried, key) or repeated_keys?(merged, key),
      do: carried,
      else: Enum.map(merged, &log_row(Map.fetch(own, row_key(&1, key)), &1, key))
  end

  defp log_list(_key, carried, _merged), do: carried

  defp log_row({:ok, mine}, row, _key), do: log_lists(mine, row)
  defp log_row(:error, row, key), do: identity_only(row, key)

  defp identity_only(row, key) do
    {name, _value} = identity(row, key)
    Map.take(row, Enum.uniq([name | @row_identities]))
  end

  defp saved_row?(%{"id" => id}) when id not in [nil, ""], do: true
  defp saved_row?(_item), do: false

  defp depth(state, uid) do
    case state.parents[uid] do
      nil -> 0
      parent -> 1 + depth(state, parent)
    end
  end

  defp carry_order(carried, state, old_base, new_base) do
    order = merged_order(carried.order, state.order, old_base.order, new_base.order)
    {:ok, carried} = apply_op(carried, {:reorder, order})

    carried.child_order
    |> Map.keys()
    |> Enum.reduce(carried, fn parent, acc ->
      current = Map.get(acc.child_order, parent, [])

      merged =
        merged_order(
          current,
          Map.get(state.child_order, parent, []),
          Map.get(old_base.child_order, parent, []),
          Map.get(new_base.child_order, parent, [])
        )

      {:ok, acc} = apply_op(acc, {:reorder_children, parent, merged})
      acc
    end)
  end

  # One list of siblings, three opinions. If the editors kept the old relative
  # order of the blocks both sides know, the other writer's order wins and the
  # editors' new blocks follow the neighbour they were put after. If the
  # editors moved blocks themselves, their order wins and the other writer's
  # new blocks follow their neighbour in the new rows.
  defp merged_order(present, editor, old, new) do
    present_set = MapSet.new(present)
    shared = Enum.filter(old, &(&1 in editor and &1 in new))
    editors_moved? = Enum.filter(editor, &(&1 in shared)) != shared

    {primary, secondary} = if editors_moved?, do: {editor, new}, else: {new, editor}

    base = Enum.filter(primary, &MapSet.member?(present_set, &1))

    secondary
    |> Enum.with_index()
    |> Enum.reject(fn {uid, _} -> uid in base or not MapSet.member?(present_set, uid) end)
    |> Enum.reduce(base, fn {uid, index}, acc ->
      anchor = secondary |> Enum.take(index) |> Enum.reverse() |> Enum.find(&(&1 in acc))

      case anchor do
        nil -> [uid | acc]
        anchor -> List.insert_at(acc, Enum.find_index(acc, &(&1 == anchor)) + 1, uid)
      end
    end)
    |> then(&(&1 ++ Enum.reject(present, fn uid -> uid in &1 end)))
  end

  ## Fields

  @render_artifacts ~w(rendered_html rendered_at)

  @doc """
  The op for what one event changed in a block's form: `{:set_field, ...}`
  for one field, `{:set_fields, ...}` for several, `nil` for nothing, or
  `:error` when the forms cannot be compared (the caller sends the whole
  block).

  `previous` is the block's changeset before the event and `changeset` the
  one after; every leaf that differs is a field. List items are named by
  identity (`id`, `uid`, `key` or `sync_uid`) rather than index, and a list
  whose items have none, or whose items were added, removed or reordered,
  is one field, set whole. `"children"` is left out: the tree is the
  store's.

  `target` is the input the event names (LiveView's `_target`): its field
  is always a change.

  `replaced` is `{stale, replacing}` when another editor's change replaced
  the form a moment ago: the form the browser showed before, and the one
  that replaced it. The event can carry the browser's old values for the
  fields that change touched (where the two differ). A touched field set
  back to its `stale` value is that, not a change, and is left out; every
  other field counts, a backspace or a toggle set back included.

  A list that gained, lost or reordered items is sent as `{:list, before,
  after}` when its items have identities, so other editors' additions and
  removals made meanwhile are kept (`merge_list/3`).

  ## Examples

      iex> alias BrandoAdmin.Components.Form.BlockField.Ops
      iex> before = Ecto.Changeset.change(%Brando.Content.Block{id: 1, uid: "b"})
      iex> cs = Ecto.Changeset.change(before, %{description: "New"})
      iex> Ops.field_op(before, cs, "b")
      {:ok, {:set_field, "b", ["description"], "New", nil}}

  """
  @spec field_op(Changeset.t(), Changeset.t(), uid(), {Changeset.t(), Changeset.t()} | nil, [String.t()] | nil) ::
          {:ok, op() | nil} | :error
  def field_op(%Changeset{} = previous, %Changeset{} = changeset, uid, replaced \\ nil, target \\ nil) do
    before = fields_snapshot(previous)
    now = fields_snapshot(changeset)

    changes =
      before
      |> leaf_changes(now, [], [], :top)
      |> reject_stale(replaced, target_path(target))

    case changes do
      [] -> {:ok, nil}
      [{_raw, path, value}] -> {:ok, {:set_field, uid, path, value, nil}}
      changes -> {:ok, {:set_fields, uid, Enum.map(changes, fn {_raw, path, value} -> {path, value} end), nil}}
    end
  rescue
    _ -> :error
  end

  defp reject_stale(changes, nil, _target), do: changes

  defp reject_stale(changes, {stale, replacing}, target) do
    stale = fields_snapshot(stale)
    replacing = fields_snapshot(replacing)

    Enum.reject(changes, fn {raw, _path, value} ->
      old = dom_get(stale, raw)
      not targets?(target, raw) and old != dom_get(replacing, raw) and old == {:ok, list_after(value)}
    end)
  end

  # The input the event names (`_target`, without the form's name) is what
  # the editor changed: never an echo, even when it is set back to what it
  # was before another editor's change to it (a toggle turned off again).
  defp target_path([_form_name | path]) when path != [], do: path
  defp target_path(_target), do: nil

  defp targets?(nil, _raw), do: false
  defp targets?(target, raw), do: List.starts_with?(target, raw)

  defp list_after({:list, _before, after_list}), do: after_list
  defp list_after(value), do: value

  # The block's own fields. Its children are left out before the snapshot
  # (they are other blocks, with their own forms): on a block with many
  # children the snapshot is otherwise most of a keystroke's cost.
  defp fields_snapshot(changeset), do: changeset |> without_children() |> snapshot_params() |> drop_artifacts()

  defp without_children(%Changeset{changes: changes, data: data} = changeset) do
    changes =
      case Map.delete(changes, :children) do
        %{block: %Changeset{} = block} = changes -> %{changes | block: without_children(block)}
        changes -> changes
      end

    %{changeset | changes: changes, data: data_without_children(data)}
  end

  defp data_without_children(%{children: _} = data),
    do: %{
      data
      | children: %Ecto.Association.NotLoaded{__field__: :children, __owner__: data.__struct__, __cardinality__: :many}
    }

  defp data_without_children(%{block: %{} = block} = data) when not is_struct(block, Ecto.Association.NotLoaded),
    do: %{data | block: data_without_children(block)}

  defp data_without_children(data), do: data

  # {path as the form names it (keys and indexes), field path, value} for
  # every leaf that differs.
  defp leaf_changes(%{} = before, %{} = now, raw, acc, level) do
    (Map.keys(now) ++ Map.keys(before))
    |> Enum.uniq()
    |> Enum.reject(&(&1 in @render_artifacts or &1 == "children"))
    |> Enum.flat_map(&key_changes(&1, Map.get(before, &1), Map.get(now, &1), raw, acc, level))
  end

  defp key_changes(_key, same, same, _raw, _acc, _level), do: []

  # The block of a root's entry-block diff is partial by nature (its rows
  # are matched by id); a map below a list item is an embed and needs its
  # whole value if the stored diff has none.
  defp key_changes(key, %{} = old, %{} = new, raw, acc, level) when not is_struct(old) and not is_struct(new) do
    segment = if level == :item, do: {:map, key, new}, else: key
    leaf_changes(old, new, raw ++ [key], [segment | acc], :inner)
  end

  defp key_changes(key, old, new, raw, acc, _level) when is_list(old) and is_list(new) do
    identities = Enum.map(new, &identity(&1, key))
    old_identities = Enum.map(old, &identity(&1, key))

    cond do
      # items without identities, or two named alike (an image twice in a
      # gallery): the list, as this editor has it
      :none in identities or :none in old_identities or repeated?(identities) or repeated?(old_identities) ->
        [{raw ++ [key], Enum.reverse([key | acc]), new}]

      # items added, removed or moved: what changed, to merge with others'
      identities != old_identities ->
        [{raw ++ [key], Enum.reverse([key | acc]), {:list, old, new}}]

      true ->
        list_item_changes(key, old, new, identities, raw, acc)
    end
  end

  defp key_changes(key, _old, new, raw, acc, _level), do: [{raw ++ [key], Enum.reverse([key | acc]), new}]

  defp list_item_changes(key, old, new, identities, raw, acc) do
    skeleton = Enum.map(identities, &identity_map/1)

    [old, new, identities]
    |> Enum.zip()
    |> Enum.with_index()
    |> Enum.flat_map(fn {{old_item, new_item, identity}, index} ->
      item_raw = raw ++ [key, to_string(index)]
      leaf_changes(old_item, new_item, item_raw, [{:at, key, identity, skeleton} | acc], :item)
    end)
  end

  defp dom_get(value, []), do: {:ok, value}
  defp dom_get(%{} = map, [key | rest]) when is_map_key(map, key), do: dom_get(Map.fetch!(map, key), rest)

  defp dom_get(list, [index | rest]) when is_list(list) do
    with {i, ""} <- Integer.parse(index),
         true <- i < length(list),
         do: dom_get(Enum.at(list, i), rest),
         else: (_ -> :error)
  end

  defp dom_get(_value, _path), do: :error

  defp drop_artifacts(%{} = map) when not is_struct(map),
    do: map |> Map.drop(@render_artifacts) |> Map.new(fn {k, v} -> {k, drop_artifacts(v)} end)

  defp drop_artifacts(list) when is_list(list), do: Enum.map(list, &drop_artifacts/1)
  defp drop_artifacts(other), do: other

  # What names a list item whatever its index: its row id, its uid, its key
  # (a var), its sync uid (a table row). An item with none of them cannot be
  # named, and its list is set whole.
  #
  # Two lists name an item without a row (or without one yet) by what it
  # holds, so it is named from the moment it is picked or typed, before any
  # save: a select var's option by its value (an embed, it never has an
  # id), a new gallery object by its image or video. A row's id comes
  # first, so two objects showing one image stay two; a list in which two
  # items are named alike is set whole (`repeated?/1`). Nothing is stored.

  defp identity(%{} = item, key) when not is_struct(item) do
    Enum.find_value(@row_identities ++ Map.get(@content_identities, key, []), :none, fn name ->
      case Map.get(item, name) do
        value when value not in [nil, ""] -> {name, value}
        _ -> nil
      end
    end)
  end

  defp identity(_item, _key), do: :none

  defp identity_map({key, value}), do: %{key => value}

  defp repeated?(identities), do: length(Enum.uniq(identities)) != length(identities)

  defp set_fields(state, uid, changes) do
    if known?(state, uid) do
      ids = Map.get(state.rel_ids, uid, %{})
      root? = uid in state.order
      diff = state.diffs |> Map.get(uid, %{}) |> fill_diff_ids(root?, ids)

      diff =
        Enum.reduce(changes, diff, fn {path, value}, diff ->
          put_path(diff, resolve_ids(path, root?, ids), resolve_list_ids(value, path, ids))
        end)

      {:ok, %{state | diffs: Map.put(state.diffs, uid, diff)}}
    else
      {:error, {:unknown_uid, uid}}
    end
  end

  # A field op made while its rows were new names them by uid, key or sync
  # uid; once a save gave them ids (`rel_ids`), the op and the diff it lands
  # in name them by id as well, so both meet on one row however each was
  # made — a second item for the same row would be saved as a new row.
  defp fill_diff_ids(diff, _root?, ids) when ids == %{}, do: diff
  defp fill_diff_ids(%{"block" => %{} = block} = diff, true, ids), do: Map.put(diff, "block", fill_rel_ids(block, ids))
  defp fill_diff_ids(diff, true, _ids), do: diff
  defp fill_diff_ids(diff, false, ids), do: fill_rel_ids(diff, ids)

  defp resolve_ids(path, _root?, ids) when ids == %{}, do: path
  defp resolve_ids(["block" | rest], true, ids), do: ["block" | resolve_ids(rest, false, ids)]

  defp resolve_ids([{:at, key, identity, skeleton} | rest], false, ids) do
    case List.keyfind(@rel_identities, key, 0) do
      {^key, field} ->
        skeleton = Enum.map(skeleton, &fill_rel_id(&1, key, field, ids))
        [{:at, key, resolve_identity(identity, key, field, ids), skeleton} | rest]

      nil ->
        [{:at, key, identity, skeleton} | rest]
    end
  end

  defp resolve_ids(path, _root?, _ids), do: path

  defp resolve_identity({name, value} = identity, key, field, ids) do
    case name == to_string(field) && Map.get(ids, {key, to_string(value)}) do
      id when id not in [nil, false] -> {"id", id}
      _ -> identity
    end
  end

  # A list set as what changed in it: merged with what the diff holds now.
  # A diff without the list has it as the editor had it before.
  defp put_path(map, [key], {:list, before, after_list}) when is_binary(key) do
    map = as_map(map)

    current =
      case Map.get(map, key) do
        list when is_list(list) -> list
        _ -> before
      end

    Map.put(map, key, merge_list(before, after_list, current, key))
  end

  defp put_path(map, [key], value) when is_binary(key), do: Map.put(as_map(map), key, value)

  defp put_path(map, [key | rest], value) when is_binary(key) do
    map = as_map(map)
    Map.put(map, key, put_path(Map.get(map, key), rest, value))
  end

  defp put_path(map, [{:map, key, default} | rest], value) do
    map = as_map(map)

    current =
      case Map.get(map, key) do
        %{} = current -> current
        _ -> default
      end

    Map.put(map, key, put_path(current, rest, value))
  end

  defp put_path(map, [{:at, key, identity, skeleton} | rest], value) do
    map = as_map(map)

    list =
      case Map.get(map, key) do
        list when is_list(list) -> list
        _ -> skeleton
      end

    list =
      case Enum.find_index(list, &same_item?(&1, identity)) do
        nil -> list ++ [put_path(identity_map(identity), rest, value)]
        index -> List.update_at(list, index, &put_path(&1, rest, value))
      end

    Map.put(map, key, list)
  end

  # The rows of a list op name them as the editor had them; after a save
  # they have ids (`rel_ids`), so they meet the diff's by id.
  defp resolve_list_ids({:list, before, after_list}, path, ids) when ids != %{} do
    case path |> List.last() |> then(&List.keyfind(@rel_identities, &1, 0)) do
      {key, field} ->
        fill = &Enum.map(&1, fn row -> fill_rel_id(row, key, field, ids) end)
        {:list, fill.(before), fill.(after_list)}

      nil ->
        {:list, before, after_list}
    end
  end

  defp resolve_list_ids(value, _path, _ids), do: value

  @doc """
  Three-way merge of a list by item identity (`id`, `uid`, `key`,
  `sync_uid`): `after_list` is what an editor made of `before`, `current`
  what the list is now, with other editors' changes since.

  The editor's order and its additions, removals and item changes win;
  items it left as they were take their current version, items others
  removed stay removed, and items others added are kept, after the item
  they follow in `current`. So when an editor adds or removes items, its
  order wins over a reorder someone else made meanwhile.

  Items are the same row when their first identity (of `id`, `uid`, `key`
  and `sync_uid`, in that order) is the same. In a list under `key`
  `"options"` (a select var's) an item without those is named by its
  `value`, and under `"gallery_objects"` by its `image_id` or `video_id`.

  ## Examples

      iex> alias BrandoAdmin.Components.Form.BlockField.Ops
      iex> before = [%{"uid" => "a"}, %{"uid" => "b"}]
      iex> mine = before ++ [%{"uid" => "c"}]
      iex> theirs = before ++ [%{"uid" => "d"}]
      iex> Ops.merge_list(before, mine, theirs) |> Enum.map(& &1["uid"])
      ["a", "b", "d", "c"]

  """
  @spec merge_list([map()], [map()], [map()], String.t() | nil) :: [map()]
  def merge_list(before, after_list, current, key \\ nil) do
    if Enum.any?([before, after_list, current], &repeated_keys?(&1, key)),
      do: merge_list_alike(before, after_list, current, key),
      else: merge_list_keyed(before, after_list, current, key)
  end

  # Identities once per item: a list of 200 rows is 40,000 comparisons
  # otherwise, in the session and again in every editor.
  defp merge_list_keyed(before, after_list, current, key) do
    before_by = first_by_key(before, key)
    current_keyed = Enum.map(current, &{row_key(&1, key), &1})
    current_by = first_by_key(current, key)

    kept =
      Enum.flat_map(after_list, fn item ->
        k = row_key(item, key)
        kept_version(item, lookup(before_by, k), lookup(current_by, k))
      end)

    kept_keys = kept |> Enum.map(&row_key(&1, key)) |> MapSet.new()

    # Items others added, each after the nearest item before it in
    # `current` that the result holds (one added before it included), or
    # first; several after one item, the later first.
    {after_anchor, _} = Enum.reduce(current_keyed, {%{}, :start}, &place_added(&1, &2, kept_keys, before_by))

    with_inserted = &[&1 | inserted_after(after_anchor, row_key(&1, key), key)]
    Enum.flat_map(Map.get(after_anchor, :start, []), with_inserted) ++ Enum.flat_map(kept, with_inserted)
  end

  # added by this editor, or changed by it: its version; left as it was
  # and removed by someone else: gone; left as it was: as it is now
  defp kept_version(item, was, _now) when is_nil(was) or was != item, do: [item]
  defp kept_version(_item, _was, nil), do: []
  defp kept_version(_item, _was, now), do: [now]

  defp place_added({:none, item}, {inserts, anchor}, _kept_keys, _before_by),
    do: {Map.update(inserts, anchor, [item], &[item | &1]), anchor}

  defp place_added({k, item}, {inserts, anchor}, kept_keys, before_by) do
    cond do
      MapSet.member?(kept_keys, k) -> {inserts, k}
      Map.has_key?(before_by, k) -> {inserts, anchor}
      true -> {Map.update(inserts, anchor, [item], &[item | &1]), k}
    end
  end

  # The same merge, one comparison at a time, for lists with items named
  # alike: an item goes after the first one named like the one before it.
  defp merge_list_alike(before, after_list, current, key) do
    same_row? = &(row_key(&1, key) != :none and row_key(&1, key) == row_key(&2, key))

    kept =
      Enum.flat_map(after_list, fn item ->
        kept_version(item, Enum.find(before, &same_row?.(&1, item)), Enum.find(current, &same_row?.(&1, item)))
      end)

    current
    |> Enum.with_index()
    |> Enum.reject(fn {item, _} -> Enum.any?(before, &same_row?.(&1, item)) or Enum.any?(kept, &same_row?.(&1, item)) end)
    |> Enum.reduce(kept, fn {item, index}, merged ->
      preceding = current |> Enum.take(index) |> Enum.reverse()
      at = Enum.find_value(preceding, 0, fn prev -> (i = Enum.find_index(merged, &same_row?.(&1, prev))) && i + 1 end)
      List.insert_at(merged, at, item)
    end)
  end

  defp repeated_keys?(items, key) do
    keys = items |> Enum.map(&row_key(&1, key)) |> Enum.reject(&(&1 == :none))
    length(Enum.uniq(keys)) != length(keys)
  end

  defp inserted_after(_after_anchor, :none, _key), do: []

  defp inserted_after(after_anchor, k, key) do
    after_anchor |> Map.get(k, []) |> Enum.flat_map(&[&1 | inserted_after(after_anchor, row_key(&1, key), key)])
  end

  # An item's identity as a map key: `{name, value}`, or `:none`.
  defp row_key(%{} = item, key) when not is_struct(item) do
    case identity(item, key) do
      {name, value} -> {name, to_string(value)}
      :none -> :none
    end
  end

  defp row_key(_item, _key), do: :none

  defp first_by_key(items, key) do
    Enum.reduce(items, %{}, fn item, acc ->
      case row_key(item, key) do
        :none -> acc
        k -> Map.put_new(acc, k, item)
      end
    end)
  end

  defp lookup(_map, :none), do: nil
  defp lookup(map, k), do: Map.get(map, k)

  defp as_map(%{} = map), do: map
  defp as_map(_), do: %{}

  defp same_item?(%{} = item, {key, value}), do: to_string(Map.get(item, key)) == to_string(value)
  defp same_item?(_item, _identity), do: false

  ## State plumbing

  defp valid_position?(:end), do: true
  defp valid_position?({:key, key}), do: is_binary(key) and key != ""
  defp valid_position?(at), do: is_integer(at) and at >= 0

  # Put `uid` into a sibling list kept in key order. A key places it among
  # the keys; an index gets a key between the neighbours at that index. Two
  # editors' blocks with the same key sort by uid. Neighbours without keys,
  # or with equal keys, are keyed again around it.
  defp place(list, keys, uid, {:key, key}) do
    index = Enum.find_index(list, &({Map.get(keys, &1), &1} > {key, uid})) || length(list)
    {List.insert_at(list, index, uid), Map.put(keys, uid, key)}
  end

  defp place(list, keys, uid, at) do
    index = clamp(at, list)
    list = List.insert_at(list, index, uid)

    case key_between(list, keys, index) do
      {:ok, key} -> {list, Map.put(keys, uid, key)}
      :rekey -> {list, FractionalKey.rekey(list, Map.delete(keys, uid))}
    end
  end

  # The key between the neighbours of `index` in `list`, if they allow one.
  defp key_between(list, keys, index) do
    before = if index > 0, do: Map.get(keys, Enum.at(list, index - 1)), else: :start
    next = if index + 1 < length(list), do: Map.get(keys, Enum.at(list, index + 1)), else: :end

    case {bound(before, :start), bound(next, :end)} do
      {:missing, _} -> :rekey
      {_, :missing} -> :rekey
      {before, next} when is_nil(before) or is_nil(next) or before < next -> {:ok, FractionalKey.between(before, next)}
      _equal -> :rekey
    end
  end

  # A neighbour's key, nil for the start or end of the list, `:missing` for a
  # neighbour without a key.
  defp bound(edge, edge), do: nil
  defp bound(nil, _edge), do: :missing
  defp bound(key, _edge), do: key

  @doc """
  The same op with its position as a fractional key, worked out on `state`,
  the editor's view when they made it. What the editor meant by "between
  these two" then survives other editors' ops that arrive first. Ops without
  a position, or whose neighbours allow no key, come back unchanged.
  """
  @spec keyed(t(), op()) :: op()
  def keyed(%__MODULE__{} = state, {:insert, uid, at, params}) when at == :end or is_integer(at),
    do: {:insert, uid, key_at(state.order, state.keys, at), params}

  def keyed(%__MODULE__{} = state, {:insert_child, parent_uid, uid, at, params}) when at == :end or is_integer(at),
    do: {:insert_child, parent_uid, uid, key_at(Map.get(state.child_order, parent_uid, []), state.keys, at), params}

  def keyed(%__MODULE__{} = state, {:move, uid, to}) when is_integer(to),
    do: {:move, uid, key_at(List.delete(state.order, uid), state.keys, to)}

  def keyed(_state, op), do: op

  defp key_at(list, keys, at) do
    index = clamp(at, list)

    case key_between(List.insert_at(list, index, :__new__), keys, index) do
      {:ok, key} -> {:key, key}
      :rekey -> at
    end
  end

  @doc """
  Give `base`, rows that were just loaded, the keys `state` already uses
  for the same blocks, so ops that name those keys still land where their
  editors meant. Blocks only `base` knows get keys between their neighbours.
  """
  @spec adopt_keys(t(), t()) :: t()
  def adopt_keys(%__MODULE__{} = base, %__MODULE__{} = state) do
    keys =
      [base.order | Map.values(base.child_order)]
      |> Enum.reduce(Map.merge(base.keys, state.keys), &FractionalKey.rekey/2)
      |> Map.take(Map.keys(base.statuses))

    %{base | keys: keys}
  end

  defp clamp(:end, list), do: length(list)
  defp clamp(at, list), do: min(at, length(list))

  defp sanitize_order(uids, current) do
    known = MapSet.new(current)
    sanitized = uids |> Enum.uniq() |> Enum.filter(&MapSet.member?(known, &1))
    # a reorder must never lose blocks — anything the new list forgot keeps
    # its relative order at the end
    sanitized ++ Enum.reject(current, &(&1 in sanitized))
  end

  # remove uid from its current position (root order or its parent's children)
  defp detach(state, uid) do
    case Map.get(state.parents, uid) do
      nil ->
        %{state | order: List.delete(state.order, uid)}

      parent_uid ->
        %{
          state
          | parents: Map.delete(state.parents, uid),
            child_order: Map.update(state.child_order, parent_uid, [], &List.delete(&1, uid))
        }
    end
  end

  defp attach_child(state, parent_uid, uid, at, params) do
    {siblings, keys} = place(Map.get(state.child_order, parent_uid, []), state.keys, uid, at)

    state = %{
      state
      | parents: Map.put(state.parents, uid, parent_uid),
        child_order: Map.put(state.child_order, parent_uid, siblings),
        keys: keys,
        statuses: Map.put(state.statuses, uid, :inserted)
    }

    register_params(state, uid, params, :block)
  end

  # Store a diff under uid, splitting any nested children params
  # (duplicate/paste/recovery inserts carry whole subtrees) into per-uid
  # diffs + registered structure. The stored diff keeps its "children" key
  # only as dead weight for :update ops — materialization ignores it.
  defp register_params(state, uid, params, shape, opts \\ []) do
    {block_params, put_back} =
      case shape do
        :entry_block -> {Map.get(params, "block", %{}), &Map.put(params, "block", &1)}
        :block -> {params, & &1}
      end

    {children_params, block_params} = pop_children(block_params)

    block_params =
      if Keyword.get(opts, :merge?, false) do
        deep_merge_params(stored_block_params(state, uid), block_params)
      else
        block_params
      end

    state = %{state | diffs: Map.put(state.diffs, uid, put_back.(block_params))}

    register_children_params(state, uid, children_params)
  end

  # Only ever called for `:block` (merging is child-only — see below), so the
  # stored diff is already block-shaped and needs no unwrapping.
  defp stored_block_params(state, uid), do: Map.get(state.diffs, uid, %{})

  # A child block's `validate_block` clause rebases on `apply_changes/1`, so the
  # diff it emits is a DELTA since the previous validate — not a cumulative diff
  # vs. the persisted row. Replacing the stored diff wholesale therefore dropped
  # every earlier edit: type in `description`, then in `anchor`, and the
  # description silently reverted at save.
  #
  # Roots keep replace semantics deliberately. They rebase on `changeset.data`,
  # so their diffs are already cumulative vs. the DB, and merging them would be a
  # bug in the other direction — a field the user edited and then reverted back
  # to its stored value emits no change at all, so the stale value would be
  # resurrected from the previous diff. A carry (`carry/3`) is different: the
  # stored diff is other editors' work, so `carry_update/3` merges a carried
  # root diff into it by field, the carried fields winning.
  #
  # Maps merge recursively. Relation lists (refs/vars/table_rows) merge ELEMENTWISE
  # BY IDENTITY, which is the case that matters most and the one that is easy to
  # get wrong: `changes_to_params/1` emits nested relations as LISTS, not
  # index-keyed maps (`change_value/1` on a list), so a naive "maps recurse,
  # everything else replaces" merge silently drops the earlier round's edits for
  # exactly the fields most likely to hold programmatic state. Pick an image on
  # ref A, then on ref B, and A's image would be gone before it reached SQL.
  #
  # Identity is `"id"` for persisted rows and `"uid"` for unsaved ones.
  #
  # The NEW list alone defines membership; the old one only contributes field
  # history for rows that appear in both. That asymmetry is deliberate and the
  # subtle part: when a relation key is present at all, its list is COMPLETE —
  # `change_value/1` maps every element — and a row the user deleted is dropped
  # from it (`:replace`/`:delete` changesets become `:drop`). Carrying old-only
  # rows over would therefore resurrect deleted refs, which is the same class of
  # bug in the opposite direction. A row with no identity on either side can't be
  # correlated, so it is taken from the new list as-is.
  defp deep_merge_params(old, new) when is_map(old) and is_map(new) do
    Map.merge(old, new, fn _key, old_value, new_value -> deep_merge_params(old_value, new_value) end)
  end

  defp deep_merge_params(old, new) when is_list(old) and is_list(new) do
    old_by_identity =
      old
      |> Enum.filter(&is_map/1)
      |> Enum.reduce(%{}, fn element, acc ->
        case relation_identity(element) do
          nil -> acc
          identity -> Map.put(acc, identity, element)
        end
      end)

    Enum.map(new, fn element ->
      with true <- is_map(element),
           identity when not is_nil(identity) <- relation_identity(element),
           stored when not is_nil(stored) <- Map.get(old_by_identity, identity) do
        deep_merge_params(stored, element)
      else
        _ -> element
      end
    end)
  end

  defp deep_merge_params(_old, new), do: new

  defp relation_identity(element) when is_map(element) do
    case {Map.get(element, "id"), Map.get(element, "uid")} do
      {id, _} when id not in [nil, ""] -> {:id, to_string(id)}
      {_, uid} when uid not in [nil, ""] -> {:uid, to_string(uid)}
      _ -> nil
    end
  end

  defp pop_children(params) when is_map(params) do
    case Map.pop(params, "children") do
      {children, rest} when is_list(children) -> {children, rest}
      {_, rest} -> {[], rest}
    end
  end

  defp register_children_params(state, _parent_uid, []), do: state

  defp register_children_params(state, parent_uid, children_params) do
    Enum.reduce(children_params, state, &register_child_params(&2, parent_uid, &1))
  end

  defp register_child_params(state, parent_uid, child_params) do
    case Map.get(child_params, "uid") do
      uid when is_binary(uid) ->
        if known?(state, uid) do
          # subtree re-registration (e.g. a re-propagated insert) — keep
          # existing structure, refresh the diff
          register_params(state, uid, child_params, :block)
        else
          attach_child(state, parent_uid, uid, :end, child_params)
        end

      _ ->
        state
    end
  end

  defp change_value(%Changeset{action: action}) when action in [:replace, :delete], do: :drop

  # A real schema changeset (has __meta__) can be partially cast by id-matching,
  # so ship only its changes plus the pk to match on.
  defp change_value(%Changeset{data: %{__meta__: _}} = cs), do: cs |> changes_to_params() |> put_data_pk(cs)

  # Embedded-schema changesets (no __meta__, e.g. polymorphic ref data) have no
  # pk to match on — snapshot their full applied state instead.
  defp change_value(%Changeset{} = cs), do: snapshot_params(cs)

  defp change_value(list) when is_list(list) do
    list
    |> Enum.map(&change_value/1)
    |> Enum.reject(&(&1 == :drop))
  end

  # schema/embed structs placed with put_change (e.g. ref data blocks) must
  # become castable maps — cast/4 raises on struct params
  defp change_value(%mod{} = struct) do
    if function_exported?(mod, :__schema__, 1) do
      struct_to_params(struct)
    else
      struct
    end
  end

  defp change_value(other), do: other

  defp put_data_pk(params, %Changeset{data: %schema{} = data}) do
    if function_exported?(schema, :__schema__, 1) do
      schema.__schema__(:primary_key)
      |> Enum.reduce(params, &put_pk_value(&2, &1, Map.get(data, &1)))
    else
      params
    end
  end

  defp put_data_pk(params, _), do: params

  defp put_pk_value(params, _pk_field, nil), do: params
  defp put_pk_value(params, pk_field, value), do: Map.put_new(params, to_string(pk_field), value)
end
