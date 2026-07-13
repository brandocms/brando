defmodule BrandoAdmin.Components.Form.BlockField.Ops do
  @moduledoc """
  Pure operation reducer for the block field's root-block state.

  Phase 3 of the block editor refactor replaces changesets-travelling-between-
  components with small named operations applied by one owner (BlockField).
  This module is that owner's state + reducer: a uid order list, a uid-keyed
  param-diff store, and per-uid statuses, mutated exclusively through
  `apply_op/2`. Being pure, every structural/content mutation the LiveView
  layer performs becomes unit-testable here.

  ## Strangler phase

  While the legacy `entry_blocks_forms` cache still exists, BlockField applies
  ops *alongside* the cache updates — the diff store is written but not yet
  read. Save-time materialization (building ONE entry changeset from
  `diffs`, order-derived sequences, and `deleted`) replaces the
  gather/broadcast protocols in the next step.

  ## Semantics

  * `order` is the single source of truth for root-block sequence. Diffs may
    carry a stale `"sequence"` key (children restamp their forms after
    reorders); materialization must override sequence from `order` position.
  * `diffs` hold the latest params snapshot of a block's *changes vs. its
    persisted data* (see `changes_to_params/1`) — `Ecto.Changeset.cast/4`
    skips absent keys, so untouched fields never travel. An `{:update, ...}`
    replaces the previous diff wholesale (each snapshot is complete in
    itself), it does not deep-merge.
  * Ops are root-level only for now: edits inside container/multi children
    reach the store when their root block propagates, mirroring what the
    legacy cache sees today.
  * Deleting a `:persisted` block records the uid in `deleted` (the row must
    be deleted at save); deleting an `:inserted` block just drops it.
  """

  alias Ecto.Changeset

  defstruct order: [], diffs: %{}, statuses: %{}, deleted: []

  @type uid :: String.t()
  @type params :: %{optional(String.t()) => term()}
  @type status :: :persisted | :inserted

  @type t :: %__MODULE__{
          order: [uid()],
          diffs: %{optional(uid()) => params()},
          statuses: %{optional(uid()) => status()},
          deleted: [uid()]
        }

  @type op ::
          {:insert, uid(), non_neg_integer() | :end, params()}
          | {:update, uid(), params()}
          | {:move, uid(), non_neg_integer()}
          | {:reorder, [uid()]}
          | {:delete, uid()}

  @doc """
  Build a fresh state from the persisted root-block uid order.

  Used on mount and after a full reload (post-save), when every known block
  is `:persisted` and no diffs are pending.

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
      uid in state.order ->
        {:error, {:duplicate_uid, uid}}

      at != :end and (not is_integer(at) or at < 0) ->
        {:error, {:bad_position, at}}

      true ->
        at = if at == :end, do: length(state.order), else: min(at, length(state.order))

        {:ok,
         %{
           state
           | order: List.insert_at(state.order, at, uid),
             diffs: Map.put(state.diffs, uid, params),
             statuses: Map.put(state.statuses, uid, :inserted)
         }}
    end
  end

  def apply_op(%__MODULE__{} = state, {:update, uid, params}) when is_map(params) do
    if uid in state.order do
      {:ok, %{state | diffs: Map.put(state.diffs, uid, params)}}
    else
      {:error, {:unknown_uid, uid}}
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
    known = MapSet.new(state.order)
    sanitized = uids |> Enum.uniq() |> Enum.filter(&MapSet.member?(known, &1))
    # a reorder must never lose blocks — anything the new list forgot keeps
    # its relative order at the end
    missing = Enum.reject(state.order, &(&1 in sanitized))
    {:ok, %{state | order: sanitized ++ missing}}
  end

  def apply_op(%__MODULE__{} = state, {:delete, uid}) do
    if uid in state.order do
      deleted =
        case state.statuses do
          %{^uid => :persisted} -> state.deleted ++ [uid]
          _ -> state.deleted
        end

      {:ok,
       %{
         state
         | order: List.delete(state.order, uid),
           diffs: Map.delete(state.diffs, uid),
           statuses: Map.delete(state.statuses, uid),
           deleted: deleted
       }}
    else
      {:error, {:unknown_uid, uid}}
    end
  end

  def apply_op(%__MODULE__{}, op), do: {:error, {:unknown_op, op}}

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
  end

  defp change_value(%Changeset{action: action}) when action in [:replace, :delete], do: :drop

  defp change_value(%Changeset{} = cs), do: cs |> changes_to_params() |> put_data_pk(cs)

  defp change_value(list) when is_list(list) do
    list
    |> Enum.map(&change_value/1)
    |> Enum.reject(&(&1 == :drop))
  end

  defp change_value(other), do: other

  defp put_data_pk(params, %Changeset{data: %schema{} = data}) do
    if function_exported?(schema, :__schema__, 1) do
      schema
      |> apply(:__schema__, [:primary_key])
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
