defmodule Brando.EditSession.Data do
  @moduledoc """
  The state of an edit session, as pure functions.

  `Brando.EditSession` is a thin process around this: it orders the messages
  it receives, calls these functions and broadcasts what they return. Keeping
  the rules here means they can be tested without processes, and that the
  replicas in each editor run exactly the same reducer
  (`BrandoAdmin.Components.Form.BlockField.Ops`).

  ## Per block field

  * `base` — the rows the state was built on, as `Ops.from_entry_blocks/1`
    gives them. Joiners compare their own rows with it (`Ops.signature/1`).
  * `state` — `base` plus every unsaved op, in session order.
  * `log` — ops applied while a save is in flight, newest first, so that the
    save's rebase can replay what arrived after the saver read the state.
    Empty while nobody is saving.
  * `marks` — `%{client => {rev, monotonic_ms}}`, one per save in flight.
  * `rev` — counts the ops applied to the field (and its rebases), so a
    replica can tell a gap from a duplicate.

  `epoch` changes when the session process is replaced, which resets
  revision numbering.
  """

  alias BrandoAdmin.Components.Form.BlockField.Ops

  require Logger

  # A save that has not rebased within this time has failed or been
  # abandoned. Its mark stops pinning the log.
  @mark_ttl_ms 120_000

  defstruct epoch: nil, fields: %{}

  @type field :: atom() | String.t()
  @type t :: %__MODULE__{epoch: integer(), fields: %{optional(field()) => map()}}

  @doc "A session with no fields yet."
  @spec new(integer()) :: t()
  def new(epoch), do: %__MODULE__{epoch: epoch}

  @doc """
  Add an editor's view of `field`.

  * An unknown field is seeded with what the editor holds: `base` is the rows
    it loaded and `state` its current state (the same as `base` on a fresh
    open, more than that when a replica re-seeds a replaced session).
  * A known field is joined when the editor loaded the same rows the session
    is built on. Otherwise `{:mismatch, data}`: the editor's rows are older
    or newer than the session's, and the caller decides (see
    `Brando.EditSession.join/4`).
  """
  @spec join(t(), field(), Ops.t(), Ops.t()) :: {:seeded | :joined | :mismatch, t()}
  def join(%__MODULE__{} = data, field, %Ops{} = base, %Ops{} = state) do
    case data.fields do
      %{^field => %{base: known}} ->
        if Ops.signature(known) == Ops.signature(base), do: {:joined, data}, else: {:mismatch, data}

      _ ->
        {:seeded, put_field(data, field, new_field(base, state))}
    end
  end

  defp new_field(base, state), do: %{base: base, state: state, rev: 0, log: [], marks: %{}}

  @doc "The current state of `field`, or `nil`."
  @spec state(t(), field()) :: Ops.t() | nil
  def state(%__MODULE__{} = data, field) do
    case data.fields do
      %{^field => %{state: state}} -> state
      _ -> nil
    end
  end

  @doc "The revision of `field` (0 for an unknown field)."
  @spec rev(t(), field()) :: non_neg_integer()
  def rev(%__MODULE__{} = data, field) do
    case data.fields do
      %{^field => %{rev: rev}} -> rev
      _ -> 0
    end
  end

  @doc """
  Apply one op to `field`. On success the revision moves on by one and the
  op is what replicas apply. A rejected op changes nothing.

  An op that raises is rejected as well: one malformed op must not take the
  session, and with it every editor's unsaved work, down.
  """
  @spec apply_op(t(), field(), Ops.op()) :: {:ok, t()} | {:error, term()}
  def apply_op(%__MODULE__{} = data, field, op) do
    with %{} = entry <- Map.get(data.fields, field, {:error, {:unknown_field, field}}),
         {:ok, state} <- safe_apply(entry.state, op) do
      rev = entry.rev + 1
      log = if entry.marks == %{}, do: [], else: [{rev, op} | entry.log]
      {:ok, put_field(data, field, %{entry | state: state, rev: rev, log: log})}
    end
  end

  defp safe_apply(state, op) do
    Ops.apply_op(state, op)
  rescue
    error ->
      Logger.error("[EditSession] op #{inspect(elem(op, 0))} raised: " <> Exception.message(error))
      {:error, :invalid_op}
  end

  @doc """
  Note that `client` is about to save `field` from the current state, so the
  ops after this revision are kept for its rebase.
  """
  @spec mark_save(t(), field(), term(), integer()) :: t()
  def mark_save(%__MODULE__{} = data, field, client, now) do
    update_field(data, field, fn entry ->
      %{entry | marks: Map.put(expire_marks(entry.marks, now), client, {entry.rev, now})}
    end)
  end

  @doc "Forget the saves `client` had in flight (it left, or its save failed)."
  @spec drop_client(t(), term()) :: t()
  def drop_client(%__MODULE__{} = data, client) do
    Enum.reduce(Map.keys(data.fields), data, fn field, data ->
      update_field(data, field, fn entry -> prune(%{entry | marks: Map.delete(entry.marks, client)}) end)
    end)
  end

  @doc """
  Move `field` onto `new_base`, rows that were just written.

  * `{:after, rev, client}` — `client` saved the state it read at `rev`. The
    ops after `rev` are replayed onto the saved rows; everything before is in
    them now.
  * `:carry` — someone wrote the rows outside the session. All unsaved work
    is carried over with `Ops.carry/3`.

  The rebase counts as one revision. Returns the data and the blocks whose
  unsaved work could not be carried (`Ops.carry/3`).
  """
  @spec rebase(t(), field(), Ops.t(), {:after, non_neg_integer(), term()} | :carry, integer()) ::
          {:ok, t(), [String.t()]} | {:error, term()}
  def rebase(%__MODULE__{} = data, field, %Ops{} = new_base, mode, now \\ 0) do
    case Map.get(data.fields, field) do
      nil ->
        {:ok, put_field(data, field, %{new_field(new_base, new_base) | rev: 1}), []}

      entry ->
        {state, conflicts, marks} = rebased_state(entry, new_base, mode, now)
        entry = prune(%{entry | base: new_base, state: state, marks: marks, rev: entry.rev + 1})
        {:ok, put_field(data, field, entry), conflicts}
    end
  end

  defp rebased_state(entry, new_base, {:after, rev, client}, now) do
    case Map.get(entry.marks, client) do
      {^rev, _at} ->
        state =
          entry.log
          |> Enum.filter(fn {op_rev, _op} -> op_rev > rev end)
          |> Enum.reverse()
          |> Enum.reduce(new_base, &replay/2)

        {state, [], entry.marks |> Map.delete(client) |> expire_marks(now)}

      _ ->
        # No record of what the save read (it took longer than the mark
        # lives): treat the rows as written by someone else.
        {state, conflicts, marks} = rebased_state(entry, new_base, :carry, now)
        {state, conflicts, Map.delete(marks, client)}
    end
  end

  defp rebased_state(entry, new_base, :carry, now) do
    {state, conflicts} = Ops.carry(entry.state, entry.base, new_base)
    {state, conflicts, expire_marks(entry.marks, now)}
  end

  # An op that no longer applies is an insert the save already made or a
  # delete of a row it already removed: its effect is in the rows.
  defp replay({_rev, op}, state) do
    case safe_apply(state, op) do
      {:ok, state} -> state
      {:error, _} -> state
    end
  end

  # Keep only the log the remaining saves need.
  defp prune(%{marks: marks} = entry) when marks == %{}, do: %{entry | log: []}

  defp prune(%{marks: marks, log: log} = entry) do
    oldest = marks |> Map.values() |> Enum.map(&elem(&1, 0)) |> Enum.min()
    %{entry | log: Enum.filter(log, fn {rev, _} -> rev > oldest end)}
  end

  defp expire_marks(marks, now) do
    marks |> Enum.reject(fn {_client, {_rev, at}} -> now - at > @mark_ttl_ms end) |> Map.new()
  end

  defp put_field(data, field, entry), do: %{data | fields: Map.put(data.fields, field, entry)}

  defp update_field(data, field, fun) do
    case data.fields do
      %{^field => entry} -> put_field(data, field, fun.(entry))
      _ -> data
    end
  end
end
