defmodule BrandoAdmin.Components.Form.BlockField.Replica do
  @moduledoc """
  A BlockField's copy of its edit session's state (`Brando.EditSession`).

  The replica keeps two things apart:

  * `confirmed` — the session's state at `rev`: every op the session has
    broadcast, in its order.
  * `pending` — this editor's own ops, applied locally at once but not yet
    confirmed by the session, oldest first.

  What the editor shows is `confirmed` with `pending` applied on top
  (`displayed/1`). When another editor's op arrives, it goes onto
  `confirmed` and the pending ops are replayed after it, which is the order
  the session will apply them in. So every editor converges on the session's
  order, while its own typing never waits for a round trip.

  Pure: the BlockField does the messaging and the rendering.
  """

  alias BrandoAdmin.Components.Form.BlockField.Ops

  require Logger

  defstruct session: nil,
            monitor: nil,
            ref: nil,
            epoch: nil,
            rev: 0,
            seq: 0,
            confirmed: nil,
            pending: [],
            touched: MapSet.new(),
            read_only: false

  @type t :: %__MODULE__{
          session: pid() | nil,
          monitor: reference() | nil,
          ref: map() | nil,
          epoch: integer() | nil,
          rev: non_neg_integer(),
          seq: non_neg_integer(),
          confirmed: Ops.t() | nil,
          pending: [{non_neg_integer(), Ops.op()}],
          touched: MapSet.t(),
          read_only: boolean()
        }

  @doc "A replica of a session that answered a join with `info`."
  @spec new(map(), map(), reference() | nil) :: t()
  def new(ref, %{session: session, epoch: epoch, rev: rev, state: state}, monitor) do
    %__MODULE__{session: session, monitor: monitor, ref: ref, epoch: epoch, rev: rev, confirmed: state}
  end

  @doc "What the editor shows: the confirmed state with the pending ops on top."
  @spec displayed(t()) :: Ops.t()
  def displayed(%__MODULE__{confirmed: confirmed, pending: pending}), do: replay(confirmed, pending)

  defp replay(state, pending) do
    Enum.reduce(pending, state, fn {_seq, op}, acc ->
      case Ops.apply_op(acc, op) do
        {:ok, acc} -> acc
        # The session will reject it as well, and say so.
        {:error, _} -> acc
      end
    end)
  end

  @doc """
  Record an op this editor just applied locally. Returns the replica and the
  sequence number to cast it with.
  """
  @spec local(t(), Ops.op()) :: {t(), non_neg_integer()}
  def local(%__MODULE__{} = replica, op) do
    seq = replica.seq + 1
    touched = op |> op_uids() |> Enum.reduce(replica.touched, &MapSet.put(&2, &1))
    {%{replica | seq: seq, pending: replica.pending ++ [{seq, op}], touched: touched}, seq}
  end

  # The blocks an op changes, to know later whose work a lost block held.
  defp op_uids({kind, uid, _}) when kind in [:update, :move], do: [uid]
  defp op_uids({:insert, uid, _at, _params}), do: [uid]
  defp op_uids({:insert_child, parent, uid, _at, _params}), do: [parent, uid]
  defp op_uids({:move_to_parent, uid, parent, _at}), do: [uid, parent]
  defp op_uids({:remap_slot, uid, _destination, _params}), do: [uid]
  defp op_uids({:reorder_children, parent, _uids}), do: [parent]
  defp op_uids(_op), do: []

  @doc "Whether this editor changed the block `uid` (as far as this replica knows)."
  @spec touched?(t(), String.t()) :: boolean()
  def touched?(%__MODULE__{touched: touched}, uid), do: MapSet.member?(touched, uid)

  @doc """
  An op broadcast by the session.

  * `{:own, replica}` — this editor's op came back. It moves from pending to
    confirmed; what the editor shows does not change.
  * `{:remote, replica, displayed}` — another editor's op.
  * `:stale` — already part of the state (a broadcast that crossed the join).
  * `:resync` — a revision is missing or the op does not apply: ask the
    session for its state.
  """
  @spec receive_op(t(), map()) :: {:own, t()} | {:remote, t(), Ops.t()} | :stale | :resync
  def receive_op(%__MODULE__{epoch: epoch} = replica, %{epoch: epoch, rev: rev} = message) do
    cond do
      rev <= replica.rev -> :stale
      rev != replica.rev + 1 -> :resync
      true -> apply_broadcast(replica, message)
    end
  end

  def receive_op(%__MODULE__{}, _message), do: :stale

  defp apply_broadcast(replica, %{rev: rev, op: op, origin: origin}) do
    case Ops.apply_op(replica.confirmed, op) do
      {:ok, confirmed} ->
        settle(%{replica | confirmed: confirmed, rev: rev}, own_seq(origin))

      {:error, reason} ->
        Logger.warning("[EditSession] broadcast op did not apply on a replica: #{inspect(reason)}")
        :resync
    end
  end

  # Another editor's op: the pending ops replay on top of it.
  defp settle(replica, nil), do: {:remote, replica, displayed(replica)}

  defp settle(%{pending: [{seq, _op} | rest]} = replica, seq), do: {:own, %{replica | pending: rest}}

  # Our op, but not the one we expected next: drop what the session can no
  # longer confirm and carry on from its state.
  defp settle(replica, seq) do
    Logger.warning("[EditSession] replica lost track of op #{seq}")
    replica = %{replica | pending: Enum.reject(replica.pending, fn {pending_seq, _} -> pending_seq <= seq end)}
    {:remote, replica, displayed(replica)}
  end

  defp own_seq({pid, seq}) when pid == self(), do: seq
  defp own_seq(_origin), do: nil

  @doc """
  The session rejected one of this editor's ops. It leaves pending, and what
  the editor shows goes back to what the session holds.
  """
  @spec receive_rejected(t(), map()) :: {t(), Ops.t(), Ops.op() | nil} | :stale
  def receive_rejected(%__MODULE__{epoch: epoch} = replica, %{epoch: epoch, seq: seq}) do
    {rejected, pending} = Enum.split_with(replica.pending, fn {pending_seq, _} -> pending_seq == seq end)
    replica = %{replica | pending: pending}

    op =
      case rejected do
        [{_seq, op}] -> op
        _ -> nil
      end

    {replica, displayed(replica), op}
  end

  def receive_rejected(%__MODULE__{}, _message), do: :stale

  @doc """
  Replace the confirmed state wholesale: a rebase broadcast, a resync, or a
  join after the session was replaced.

  The session says which of this editor's ops the state already holds (the
  `:seq` of a reply, or this process's entry in a broadcast's `:seqs`).
  Those leave pending; replaying them over the new state would put an old
  value back over a later one from another editor. The rest stay pending
  and are replayed on top.
  """
  @spec reset(t(), map()) :: {t(), Ops.t()}
  def reset(%__MODULE__{} = replica, %{epoch: epoch, rev: rev, state: state} = info) do
    handled = handled_seq(info)

    replica = %{
      replica
      | epoch: epoch,
        rev: rev,
        confirmed: state,
        session: Map.get(info, :session, replica.session),
        pending: Enum.reject(replica.pending, fn {seq, _op} -> seq <= handled end)
    }

    {replica, displayed(replica)}
  end

  defp handled_seq(%{seq: seq}) when is_integer(seq), do: seq
  defp handled_seq(%{seqs: %{} = seqs}), do: Map.get(seqs, self(), 0)
  defp handled_seq(_info), do: 0

  @doc "Whether a rebase or resync message is newer than what the replica holds."
  @spec newer?(t(), map()) :: boolean()
  def newer?(%__MODULE__{epoch: epoch, rev: rev}, %{epoch: epoch, rev: message_rev}), do: message_rev > rev
  def newer?(%__MODULE__{}, %{epoch: _other}), do: false
end
