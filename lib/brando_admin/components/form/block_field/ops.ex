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
  preview, share, remote sync, restore and the outline alike.

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
  * Inserted params may carry a nested children tree (duplicate/paste/
    recovery); `apply_op/2` splits it into per-uid diffs and registers the
    structure, keeping the one-diff-per-uid invariant.
  * Deleting a `:persisted` block records it (and its persisted descendants)
    in `deleted`; `:inserted` blocks just drop. `bin_snapshot/2` captured
    before the delete + `restore_snapshot/2` undo one, subtree and all.
  """

  alias Ecto.Changeset

  defstruct order: [],
            parents: %{},
            child_order: %{},
            diffs: %{},
            statuses: %{},
            db_ids: %{},
            deleted: [],
            deleted_roots: []

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
          deleted: [uid()],
          deleted_roots: [uid()]
        }

  @type op ::
          {:insert, uid(), non_neg_integer() | :end, params()}
          | {:insert_child, parent :: uid(), uid(), non_neg_integer() | :end, params()}
          | {:update, uid(), params()}
          | {:move, uid(), non_neg_integer()}
          | {:reorder, [uid()]}
          | {:reorder_children, parent :: uid(), [uid()]}
          | {:move_to_parent, uid(), new_parent :: uid(), non_neg_integer() | :end}
          | {:delete, uid()}

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
    %__MODULE__{order: uids, statuses: Map.new(uids, &{&1, :persisted})}
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
          db_ids: Map.put(state.db_ids, uid, {entry_block.id, entry_block.block.id})
      }

      register_persisted_children(state, entry_block.block)
    end)
  end

  defp register_persisted_children(state, %{uid: parent_uid, children: children}) when is_list(children) do
    Enum.reduce(children, state, fn child, state ->
      state = %{
        state
        | parents: Map.put(state.parents, child.uid, parent_uid),
          child_order: Map.update(state.child_order, parent_uid, [child.uid], &(&1 ++ [child.uid])),
          statuses: Map.put(state.statuses, child.uid, :persisted),
          db_ids: Map.put(state.db_ids, child.uid, {nil, child.id})
      }

      register_persisted_children(state, child)
    end)
  end

  defp register_persisted_children(state, _block_without_loaded_children), do: state

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
        state = %{
          state
          | order: List.insert_at(state.order, clamp(at, state.order), uid),
            statuses: Map.put(state.statuses, uid, :inserted)
        }

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

  def apply_op(%__MODULE__{} = state, {:move, uid, to}) do
    cond do
      uid not in state.order -> {:error, {:unknown_uid, uid}}
      not is_integer(to) or to < 0 -> {:error, {:bad_position, to}}
      true -> {:ok, %{state | order: state.order |> List.delete(uid) |> List.insert_at(to, uid)}}
    end
  end

  def apply_op(%__MODULE__{} = state, {:reorder, uids}) when is_list(uids) do
    {:ok, %{state | order: sanitize_order(uids, state.order)}}
  end

  def apply_op(%__MODULE__{} = state, {:reorder_children, parent_uid, uids}) when is_list(uids) do
    if known?(state, parent_uid) do
      current = Map.get(state.child_order, parent_uid, [])
      {:ok, %{state | child_order: Map.put(state.child_order, parent_uid, sanitize_order(uids, current))}}
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
        siblings = Map.get(state.child_order, new_parent_uid, [])

        {:ok,
         %{
           state
           | parents: Map.put(state.parents, uid, new_parent_uid),
             child_order: Map.put(state.child_order, new_parent_uid, List.insert_at(siblings, clamp(at, siblings), uid))
         }}
    end
  end

  def apply_op(%__MODULE__{} = state, {:delete, uid}) do
    if known?(state, uid) do
      doomed = [uid | descendants(state, uid)]
      newly_deleted = Enum.filter(doomed, &(state.statuses[&1] == :persisted))
      # roots are tracked separately: late-join sync replays root deletes as
      # structural broadcasts, while child deletes travel as snapshot tombstones
      newly_deleted_roots = Enum.filter(newly_deleted, &(&1 in state.order))

      state = detach(state, uid)

      {:ok,
       %{
         state
         | parents: Map.drop(state.parents, doomed),
           child_order: Map.drop(state.child_order, doomed),
           diffs: Map.drop(state.diffs, doomed),
           statuses: Map.drop(state.statuses, doomed),
           db_ids: Map.drop(state.db_ids, doomed),
           deleted: state.deleted ++ newly_deleted,
           deleted_roots: state.deleted_roots ++ newly_deleted_roots
       }}
    else
      {:error, {:unknown_uid, uid}}
    end
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

  @doc """
  A self-contained content+structure snapshot of `uid`'s subtree, for
  shipping to other editors over PubSub.

  Carries param diffs (never changesets/forms — payloads stay tiny and
  node-portable), the parent links and per-parent child order for the
  subtree, plus the DFS uid order so receivers can apply parents before
  children. Also ships the sender's `deleted` tombstones — snapshots can
  attach remotely inserted children but could never express a remote CHILD
  delete without them (root deletes travel as structural broadcasts).
  Apply with `apply_remote_snapshot/3`.
  """
  @spec subtree_snapshot(t(), uid()) :: map()
  def subtree_snapshot(%__MODULE__{} = state, uid) do
    uids = [uid | descendants(state, uid)]

    %{
      uids: uids,
      diffs: Map.take(state.diffs, uids),
      parents: Map.take(state.parents, uids),
      child_order: Map.take(state.child_order, uids),
      deleted: state.deleted
    }
  end

  @doc """
  Apply a remote editor's `subtree_snapshot/2` to this state.

  Known uids get their diffs replaced; unknown uids are attached under
  their shipped parent (this is how remotely inserted children reach
  editors that never received a structural broadcast for them); shipped
  child orders are applied next; finally the sender's `deleted` tombstones
  remove any of OUR known children the sender deleted. Tombstones only
  apply to child uids — root deletes travel as structural broadcasts, and
  a stale tombstone must never kill a root the remote editor undeleted.
  The snapshot's top uid must be known unless it arrives with a known
  parent — remote ROOT inserts travel as structural broadcasts before any
  content ships for them.
  """
  @spec apply_remote_snapshot(t(), uid(), map()) :: {:ok, t()} | {:error, term()}
  def apply_remote_snapshot(%__MODULE__{} = state, _uid, %{uids: uids} = snapshot) do
    diffs = Map.get(snapshot, :diffs, %{})
    parents = Map.get(snapshot, :parents, %{})
    child_order = Map.get(snapshot, :child_order, %{})
    tombstones = Map.get(snapshot, :deleted, [])

    uids
    |> Enum.reduce_while({:ok, state}, fn u, {:ok, state} ->
      diff = Map.get(diffs, u, %{})

      result =
        cond do
          known?(state, u) -> apply_op(state, {:update, u, diff})
          parents[u] && known?(state, parents[u]) -> apply_op(state, {:insert_child, parents[u], u, :end, diff})
          true -> {:error, {:unknown_uid, u}}
        end

      case result do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, state} ->
        child_order
        |> Enum.filter(fn {parent_uid, _} -> known?(state, parent_uid) end)
        |> Enum.reduce({:ok, state}, fn {parent_uid, order}, {:ok, state} ->
          apply_op(state, {:reorder_children, parent_uid, order})
        end)

      error ->
        error
    end
    |> case do
      {:ok, state} -> {:ok, apply_child_tombstones(state, tombstones)}
      error -> error
    end
  end

  defp apply_child_tombstones(state, tombstones) do
    Enum.reduce(tombstones, state, fn u, state ->
      if known?(state, u) and Map.has_key?(state.parents, u) do
        {:ok, state} = apply_op(state, {:delete, u})
        state
      else
        state
      end
    end)
  end

  @doc """
  A restorable-bin snapshot of `uid`'s subtree — capture BEFORE applying
  `{:delete, uid}`, restore with `restore_snapshot/2`.

  Extends `subtree_snapshot/2` with everything a delete destroys that a
  remote-sync snapshot doesn't need: per-uid statuses and db ids (so a
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
      db_ids: Map.take(state.db_ids, uids)
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
      iex> {:ok, restored} = Ops.restore_snapshot(state, snapshot)
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
            deleted: Enum.reject(state.deleted, &(&1 in uids)),
            deleted_roots: Enum.reject(state.deleted_roots, &(&1 in uids))
        }

        {:ok, reattach(state, uid, location)}
    end
  end

  defp location_known?(_state, {:root, _at}), do: true
  defp location_known?(state, {:child, parent_uid, _at}), do: known?(state, parent_uid)

  defp reattach(state, uid, {:root, at}) do
    %{state | order: List.insert_at(state.order, clamp(at, state.order), uid)}
  end

  defp reattach(state, uid, {:child, parent_uid, at}) do
    siblings = Map.get(state.child_order, parent_uid, [])

    %{
      state
      | parents: Map.put(state.parents, uid, parent_uid),
        child_order: Map.put(state.child_order, parent_uid, List.insert_at(siblings, clamp(at, siblings), uid))
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
  end

  # ALWAYS emit "children" — the tree is authoritative, including emptiness
  # (`from_entry_blocks`/insert registration know every child). Dropping the
  # key when empty silently kept rows alive: deleting a parent's last child
  # never persisted, and a child moved to another parent stayed (duplicated)
  # under the old one. An empty list over loaded-empty data is a no-op cast.
  defp put_children(params, children), do: Map.put(params, "children", children)

  defp put_new_id(params, nil), do: params
  defp put_new_id(params, id), do: Map.put_new(params, "id", id)

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

    mod.__schema__(:associations)
    |> Enum.filter(&(&1 in @snapshot_assocs))
    |> Enum.reduce(field_params, fn assoc, acc ->
      case Map.get(struct, assoc) do
        %Ecto.Association.NotLoaded{} -> acc
        # A cleared association is expressed by its FK going nil, which the
        # field params already carry — emitting the assoc as nil as well would
        # take the FK's place below and say nothing.
        nil -> acc
        value -> acc |> drop_owner_key(mod, assoc) |> Map.put(to_string(assoc), change_value(value))
      end
    end)
  end

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

  ## State plumbing

  defp valid_position?(:end), do: true
  defp valid_position?(at), do: is_integer(at) and at >= 0

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
    siblings = Map.get(state.child_order, parent_uid, [])

    state = %{
      state
      | parents: Map.put(state.parents, uid, parent_uid),
        child_order: Map.put(state.child_order, parent_uid, List.insert_at(siblings, clamp(at, siblings), uid)),
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
  # resurrected from the previous diff.
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
    Enum.reduce(children_params, state, fn child_params, state ->
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
    end)
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
      |> Enum.reduce(params, fn pk_field, acc ->
        case Map.get(data, pk_field) do
          nil -> acc
          value -> Map.put_new(acc, to_string(pk_field), value)
        end
      end)
    else
      params
    end
  end

  defp put_data_pk(params, _), do: params
end
