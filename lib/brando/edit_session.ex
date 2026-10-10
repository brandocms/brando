defmodule Brando.EditSession do
  @moduledoc """
  One process per entry being edited: the single order of block changes.

  Every editor with the entry open holds a replica of the entry's block
  state (`BrandoAdmin.Components.Form.BlockField.Ops`). Editors do not send
  each other anything. They cast their ops here; the session applies each
  with the same pure reducer, gives it the next revision and broadcasts it.
  Replicas apply the broadcast ops in revision order, so every editor ends up
  with the same state. This is Livebook's model (`Livebook.Session` and
  `Session.Data`), applied to Brando's block store.

  ## Lifecycle

  * Started on demand by the first editor that opens the entry
    (`join/4`), under `Brando.EditSession.Supervisor`, and found through
    `Brando.EditSession.Registry` by `{tenant prefix, schema, id, language}`.
  * Seeded from what that editor loaded. The session never reads the
    database; joiners bring their rows and the session checks they are the
    ones it was built on.
  * Monitors its editors. When the last one leaves it waits a grace period
    (`config :brando, Brando.EditSession, grace_period: 30_000`) so a
    reconnecting editor finds its unsaved work, then stops. Unsaved work in a
    stopped session is gone from here; recovery copies (`Brando.Drafts`) keep
    each editor's own.
  * Started with `restart: :temporary`. If it crashes, nothing restarts it
    empty: each replica notices (`:DOWN`), joins a new session seeded from
    its own state and casts again the ops the old one never confirmed.

  ## Saves

  The session holds unsaved state, never a second copy of the saved entry.
  A save reads the state (`fetch/3` with `purpose: :save`), goes through the
  entry's normal changeset and form pipeline, and then hands the session the
  rows it wrote (`rebase/4`): the session replays only the ops that arrived
  after the save read the state, and every replica refreshes its rows.
  Writes from outside the editor (an applied Assistant proposal, an
  activated revision) arrive through `sync_saved/1`, which carries everyone's
  unsaved work onto the new rows as ordinary ops (`Ops.carry/3`), like
  Livebook's `DataSync`.

  ## Tenancy

  The tenant prefix of the process that starts the session is part of its
  key and is set in the session process, as `Brando.Tenant.Job` does for
  jobs, so topics and anything else it does stay in that site.

  ## Clustering

  The session is local to the node that started it, and so are its
  replicas' PubSub broadcasts. Editors on different nodes of a cluster would
  each get their own session today. Clustering needs a cluster-wide name
  (`:pg` or Horde instead of the local Registry), cluster-wide PubSub (which
  Phoenix.PubSub already is) and replicas that re-seed after a netsplit, which
  the crash path already does. Nothing here assumes a single node beyond the
  Registry lookup in `whereis/1`.
  """
  use GenServer, restart: :temporary

  alias Brando.EditSession.Data
  alias Brando.Tenant
  alias BrandoAdmin.Components.Form.BlockField.Ops
  alias Phoenix.PubSub

  require Logger

  @registry Brando.EditSession.Registry
  @supervisor Brando.EditSession.Supervisor

  @type key :: {String.t() | nil, module(), term(), String.t() | nil}
  @type ref :: %{key: key(), topic: String.t()}

  @doc "The Registry and DynamicSupervisor the sessions run under."
  @spec children() :: [Supervisor.child_spec()]
  def children do
    [
      {Registry, keys: :unique, name: @registry},
      {DynamicSupervisor, name: @supervisor, strategy: :one_for_one}
    ]
  end

  @doc """
  The session reference for an entry, in the current tenant: its Registry key
  and the topic its ops are broadcast on.
  """
  @spec ref(module(), term(), term()) :: ref()
  def ref(schema, id, language \\ nil) do
    language = language && to_string(language)
    topic = Brando.Tenant.Topic.entry("edit_session", schema, if(language, do: "#{id}:#{language}", else: id))
    %{key: {Tenant.current_prefix(), schema, id, language}, topic: topic}
  end

  @doc "The session reference for an entry struct."
  @spec ref_for(struct()) :: ref()
  def ref_for(%schema{id: id} = entry), do: ref(schema, id, Map.get(entry, :language))

  @doc "The running session for `ref` or key, if any."
  @spec whereis(ref() | key()) :: pid() | nil
  def whereis(%{key: key}), do: whereis(key)

  # A session that died stays registered until the Registry has handled its
  # exit, which can be after its editors have handled theirs and come back
  # to join: a dead pid is no session. (Registering a new one replaces the
  # stale entry, as `Registry` does for a dead process.)
  def whereis(key) do
    case Registry.lookup(@registry, key) do
      [{pid, _}] -> if Process.alive?(pid), do: pid
      [] -> nil
    end
  end

  @doc """
  Join the session for `ref` as a replica of `field`, starting it if needed.

  `base` is the rows the caller loaded (`Ops.from_entry_blocks/1`) and
  `state` what the caller holds now: the same on a fresh open, more when a
  replica re-seeds after the session died.

  Returns `{:ok, info}` with `:session`, `:epoch`, `:rev`, `:state`,
  `:seq` (the last of the caller's ops the session handled) and `:seeded?`.
  Work the caller holds beyond its rows is carried onto the session's state
  (a replica coming back after a crash). When the caller's rows are not the
  ones the session is built on, `{:error, :base_mismatch}`, unless
  `rebase: true` is given: then the caller's freshly loaded rows are taken
  as written outside the session and the unsaved work is carried onto them
  for everyone (see `rebase/4`).

  Options:

    * `:user_id` — for the session's own bookkeeping;
    * `:rebase` — see above;
    * `:held_base` — the rows `state` was built on, when the caller read its
      rows again before joining;
    * `:read_only` — the editor may look but not change the entry: the
      session rejects its ops.
  """
  @spec join(ref(), term(), {Ops.t(), Ops.t()}, keyword()) :: {:ok, map()} | {:error, term()}
  def join(ref, field, {%Ops{} = base, %Ops{} = state}, opts \\ []) do
    message = {:join, self(), field, base, state, opts}

    with {:ok, pid} <- ensure_started(ref) do
      try do
        GenServer.call(pid, message)
      catch
        # Stopped between the lookup and the call (end of a grace period).
        :exit, _ ->
          with {:ok, pid} <- ensure_started(ref), do: GenServer.call(pid, message)
      end
    end
  end

  defp ensure_started(%{key: key, topic: topic}) do
    case whereis(key) do
      nil ->
        spec = {__MODULE__, %{key: key, topic: topic}}

        case DynamicSupervisor.start_child(@supervisor, spec) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, reason} -> {:error, reason}
        end

      pid ->
        {:ok, pid}
    end
  end

  @doc """
  Cast an op for `field`. `seq` is the caller's own counter: the broadcast
  carries `{caller, seq}` as its origin so the caller can tell its own ops
  from everyone else's, and a rejected op comes back to the caller alone.
  """
  @spec submit(pid(), term(), Ops.op(), non_neg_integer()) :: :ok
  def submit(session, field, op, seq), do: GenServer.cast(session, {:op, self(), field, op, seq})

  @doc """
  The current state of `field`: `{:ok, %{epoch, rev, state}}`.

  `purpose: :save` keeps the ops that arrive from now on until this caller
  rebases (or leaves), so the rebase can replay them onto the saved rows.
  """
  @spec fetch(pid(), term(), keyword()) :: {:ok, map()} | {:error, term()}
  def fetch(session, field, opts \\ []) do
    GenServer.call(session, {:fetch, self(), field, Keyword.get(opts, :purpose)})
  catch
    :exit, _ -> {:error, :no_session}
  end

  @doc """
  Move `field` onto rows that were just written (`Ops.from_entry_blocks/1`
  of the reloaded entry) and broadcast the result to every replica.

  `mode` is `:own_save` when the caller saved the state it fetched with
  `purpose: :save` (only the ops after that are replayed), `{:after, rev}`
  for a given revision, and `:carry` when the rows were written outside the
  session.

  `replica: true` when the caller is the field's replica, which moves on
  with the reply and never sees the broadcast: it is not asked to bring
  back removed work then (any other caller, `sync_saved/1` from the
  editor's own process, is).
  """
  @spec rebase(pid(), term(), Ops.t(), :own_save | {:after, non_neg_integer()} | :carry, keyword()) ::
          {:ok, map()} | {:error, term()}
  def rebase(session, field, %Ops{} = base, mode, opts \\ []) do
    GenServer.call(session, {:rebase, self(), field, base, mode, opts})
  catch
    :exit, _ -> {:error, :no_session}
  end

  @doc "Stop being a replica of `field` (the block field went away)."
  @spec leave(pid(), term()) :: :ok
  def leave(session, field), do: GenServer.cast(session, {:leave, self(), field})

  @doc """
  Leave `field` to show something the others do not see: a revision loaded
  as a working copy, which replaces the editor's unsaved changes.

  The unsaved work the session holds now is what this editor replaced. If
  this editor then writes the entry (activates the revision, or saves the
  working copy), the session moves onto the written rows keeping only the
  ops that arrived after this call, instead of carrying the replaced work
  back over what was written. Joining again forgets it.
  """
  @spec detach(pid(), term()) :: :ok
  def detach(session, field), do: GenServer.cast(session, {:detach, self(), field})

  @doc """
  The entry was written outside the editor. If a session is running for
  it, its block fields are rebased onto the rows as they are now, carrying
  every editor's unsaved work over (`Ops.carry/3`). The open editors receive
  the change like any other and do not reload.

  Call it in the process that wrote the entry, after the write, with the
  tenant prefix the entry belongs to. Inside a `Brando.Repo.transaction/2`
  it waits until the transaction commits (`Brando.Repo.after_commit/1`), and
  a rollback drops it: the session must never read rows that may not exist.
  """
  @spec sync_saved(struct()) :: :ok
  def sync_saved(%_{} = entry),
    do: Brando.Repo.after_commit(Tenant.capture_context(fn -> rebase_all(entry, :carry) end))

  @doc """
  This process saved the entry from the state it fetched with `purpose:
  :save`. The session moves onto the saved rows and keeps only the ops that
  arrived after the save read the state. For a save that leaves the editor
  (save and close, save and create new): the block fields that would
  otherwise do it are going away.
  """
  @spec saved(struct()) :: :ok
  def saved(%_{} = entry), do: rebase_all(entry, :own_save)

  @doc """
  This process is done bringing back the blocks of `group`, as the session
  asked: after the insert it cast, or without one. The session checks its
  state for the copy and tells every editor, or asks the next one.
  """
  @spec rescued(pid(), term(), String.t()) :: :ok
  def rescued(session, field, group), do: GenServer.cast(session, {:rescued, self(), field, group})

  @doc """
  This process's save of `entry`, from the state it fetched with `purpose:
  :save`, failed: the session stops keeping the ops that arrived since for
  its rebase.
  """
  @spec save_failed(struct()) :: :ok
  def save_failed(%_{id: id} = entry) when not is_nil(id) do
    case whereis(ref_for(entry)) do
      pid when is_pid(pid) -> GenServer.cast(pid, {:save_failed, self()})
      _ -> :ok
    end
  end

  def save_failed(_entry), do: :ok

  defp rebase_all(%schema{id: id} = entry, mode) do
    with pid when is_pid(pid) <- whereis(ref_for(entry)),
         true <- schema.has_trait(Brando.Trait.Blocks) do
      for {field, base} <- saved_bases(schema, id), do: rebase(pid, field, base, mode)
    end

    :ok
  rescue
    error ->
      Logger.error("[EditSession] rebase after a save failed: " <> Exception.message(error))
      :ok
  end

  @doc "Each block field's rows as they are in the database, as `Ops` bases."
  @spec saved_bases(module(), term()) :: [{atom(), Ops.t()}]
  def saved_bases(schema, id) do
    import Ecto.Query, only: [from: 2]

    for {assoc, query} <- Brando.Content.BlockPreloads.for_schema(schema) do
      field = assoc |> to_string() |> String.replace_prefix("entry_", "") |> String.to_existing_atom()
      {field, Ops.from_entry_blocks(Brando.Repo.all(from(j in query, where: j.entry_id == ^id)))}
    end
  end

  ## Server

  def start_link(%{key: key} = args) do
    GenServer.start_link(__MODULE__, args, name: {:via, Registry, {@registry, key}}, hibernate_after: 15_000)
  end

  @impl true
  def init(%{key: {prefix, _schema, _id, _language} = key, topic: topic}) do
    if prefix, do: Tenant.put_prefix(prefix)

    Process.send_after(self(), :expire_marks, Data.mark_check_ms())

    {:ok,
     %{
       key: key,
       topic: topic,
       data: Data.new(System.unique_integer([:positive, :monotonic])),
       clients: %{},
       # the blocks each editor changed (`Ops.op_uids/1`), kept after they
       # leave: whose work a block another write removes holds
       touched: %{},
       # blocks with unsaved work a write removed, waiting for the editor
       # asked to bring them back (`assign_rescues/6`)
       rescues: %{},
       # the uids of the copies joiners were told to make (`copies/5`):
       # taken, though not in the state until their inserts arrive
       copy_uids: MapSet.new(),
       # editors that left to show something else (`detach/2`), monitored so
       # their marks go when they do
       detached: %{},
       grace_ms: grace_period(),
       stop_timer: nil
     }}
  end

  @impl true
  def handle_call({:join, pid, field, base, held, opts}, _from, session) do
    how = if detached?(session, field, pid) and opts[:rebase] == true, do: :wrote_working_copy, else: :join
    {reply, session} = do_join(track(session, pid, field, opts), pid, field, base, held, opts, how)

    # The mark of a working copy this editor left for (`detach/2`) goes with
    # the join, used by its rebase if it had one.
    {:reply, reply, %{session | data: Data.unmark(session.data, field, {:detached, pid})}}
  end

  def handle_call({:fetch, pid, field, purpose}, _from, session) do
    case Data.state(session.data, field) do
      nil ->
        {:reply, {:error, :unknown_field}, session}

      _state ->
        data =
          if purpose == :save,
            do: Data.mark_save(session.data, field, pid, now()),
            else: session.data

        session = %{session | data: data}
        {:reply, {:ok, info(session, field, pid, false)}, session}
    end
  end

  def handle_call({:rebase, pid, field, base, mode, opts}, _from, session) do
    mode =
      case {mode, detached?(session, field, pid)} do
        # this editor wrote what it showed in place of the session's state
        {mode, true} when mode in [:own_save, :carry] -> {:client, {:detached, pid}}
        {:own_save, false} -> {:client, pid}
        {{:after, rev}, false} -> {:after, rev, pid}
        {:carry, false} -> :carry
      end

    reason = if mode == :carry, do: :external, else: :saved
    exclude = if opts[:replica], do: pid
    session = do_rebase(session, field, base, mode, pid, reason, exclude)
    {:reply, {:ok, info(session, field, pid, false)}, session}
  end

  @impl true
  def handle_cast({:op, pid, field, op, seq}, session) do
    result =
      if read_only?(session, pid),
        do: {:error, :read_only},
        else: Data.apply_op(session.data, field, op, {pid, seq})

    case result do
      {:ok, data} ->
        uids = MapSet.new(Ops.op_uids(op))
        session = %{session | data: data, touched: Map.update(session.touched, pid, uids, &MapSet.union(&1, uids))}

        broadcast(session, field, %{
          kind: :op,
          epoch: data.epoch,
          rev: Data.rev(data, field),
          op: op,
          origin: {pid, seq}
        })

        # an insert that brings back removed work settles its rescue
        {:noreply, if(session.rescues == %{}, do: session, else: settle_rescues(session, field))}

      {:error, reason} ->
        Logger.warning("[EditSession] rejected #{inspect(elem(op, 0))} for #{inspect(field)}: #{inspect(reason)}")
        send(pid, {:edit_session, field, %{kind: :rejected, epoch: session.data.epoch, seq: seq, reason: reason}})
        {:noreply, %{session | data: Data.note_seq(session.data, field, pid, seq)}}
    end
  end

  def handle_cast({:detach, pid, field}, session) do
    session =
      case Data.state(session.data, field) do
        nil ->
          session

        _state ->
          detached = Map.put_new_lazy(session.detached, pid, fn -> Process.monitor(pid) end)
          %{session | detached: detached, data: Data.mark_detached(session.data, field, {:detached, pid})}
      end

    handle_cast({:leave, pid, field}, session)
  end

  def handle_cast({:save_failed, pid}, session), do: {:noreply, %{session | data: Data.release(session.data, pid)}}

  # The editor asked says it is done. The insert it cast came first, so the
  # state says whether it worked: if not, the next editor is asked.
  def handle_cast({:rescued, pid, field, group}, session) do
    session = settle_rescues(session, field)

    case session.rescues do
      %{{^field, ^group} => %{rescuer: ^pid}} -> {:noreply, reassign_rescue(session, field, group)}
      _ -> {:noreply, session}
    end
  end

  def handle_cast({:leave, pid, field}, session) do
    session =
      case session.clients do
        %{^pid => client} ->
          fields = MapSet.delete(client.fields, field)

          if MapSet.size(fields) == 0,
            do: remove_client(session, pid),
            else: put_in(session.clients[pid].fields, fields)

        _ ->
          session
      end

    {:noreply, maybe_schedule_stop(session)}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, session) do
    session = %{
      session
      | detached: Map.delete(session.detached, pid),
        data: Data.drop_client(session.data, {:detached, pid})
    }

    {:noreply, session |> remove_client(pid) |> maybe_schedule_stop()}
  end

  def handle_info({:rescue_timeout, field, group, token}, session) do
    case session.rescues do
      %{{^field, ^group} => %{token: ^token}} -> {:noreply, reassign_rescue(session, field, group)}
      _ -> {:noreply, session}
    end
  end

  def handle_info({:stop_if_idle, token}, %{stop_timer: {token, _}, clients: clients} = session)
      when map_size(clients) == 0,
      do: {:stop, :normal, session}

  def handle_info({:stop_if_idle, _token}, session), do: {:noreply, session}

  # A save that never rebased (it failed, or the editor went away mid-save)
  # must not keep the op log growing.
  def handle_info(:expire_marks, session) do
    Process.send_after(self(), :expire_marks, Data.mark_check_ms())
    {:noreply, %{session | data: Data.expire(session.data, now())}}
  end

  # A replica rejoining onto a session that moved on to other rows: what it
  # holds is carried onto the session's state.
  defp merge_held(session, field, held, held_base, pid) do
    case Data.merge_held(session.data, field, held, held_base) do
      {:joined, _data} ->
        {session, []}

      {{:merged, conflicts}, data} ->
        # Work only the joiner held: only it can bring it back, from the
        # join's reply (`joiner_info/5`).
        session = %{session | data: data}
        broadcast_state(session, field, pid, :joined, conflicts, [])
        {session, conflicts}
    end
  end

  # The join's reply, with the joiner's own work the session could not take
  # (`rescues`, for it alone): its blocks another write removed meanwhile.
  defp joiner_info(session, field, pid, held, conflicts) do
    new = Data.state(session.data, field)

    rescues =
      conflicts
      |> Enum.group_by(&removed_top(held, new, &1))
      |> Enum.map(fn {group, uids} ->
        %{
          group: group,
          kept: kept_uid(session, field, held, new, group),
          uids: uids,
          rescuer: pid,
          owners: [pid],
          orphan?: false
        }
      end)

    {copies, session} = copies(session, field, pid, held, new)
    {Map.put(info(session, field, pid, false), :rescues, rescues ++ copies), session}
  end

  # New blocks the joiner held that the session has in another version (an
  # editor who came back first seeded it with theirs): the session keeps
  # its own, and the joiner brings its version back as a copy beside it.
  defp copies(session, field, pid, %Ops{} = held, %Ops{} = new) do
    held
    |> Ops.diverged_inserts(new)
    |> Enum.map_reduce(session, fn group, session ->
      kept = kept_uid(session, field, held, new, group)

      copy = %{
        group: group,
        kept: kept,
        uids: [group | Ops.descendants(held, group)],
        rescuer: pid,
        owners: [pid],
        orphan?: false,
        copy?: true
      }

      {copy, %{session | copy_uids: MapSet.put(session.copy_uids, {field, kept})}}
    end)
  end

  defp copies(session, _field, _pid, _held, _new), do: {[], session}

  # `exclude`: an editor whose replica moves on with the reply of the call
  # that caused this rebase (a join, the replica's own rebase), and never
  # sees the broadcast.
  defp do_rebase(session, field, base, mode, origin, reason, exclude) do
    old = Data.state(session.data, field)
    {:ok, data, conflicts} = Data.rebase(session.data, field, base, mode, now())
    session = %{session | data: data}

    if conflicts != [] do
      Logger.warning("[EditSession] unsaved work on #{inspect(conflicts)} could not be carried onto the new rows")
    end

    {session, rescues} = assign_rescues(session, field, old, Data.state(data, field), conflicts, exclude)
    broadcast_state(session, field, origin, reason, conflicts, rescues)
    session
  end

  # The field's whole state, for every replica: after a rebase, or when a
  # joiner carried work onto it. `seqs` tells each replica which of its
  # pending ops the state already holds.
  defp broadcast_state(session, field, origin, reason, conflicts, rescues) do
    data = session.data
    entry = Map.fetch!(data.fields, field)

    broadcast(session, field, %{
      kind: :rebase,
      epoch: data.epoch,
      rev: entry.rev,
      # the names and order of every saved row stay in the session
      # (`Data.merge_held/4`); replicas compare rows by structure alone
      base: Ops.keep_rel_ids(entry.base),
      state: entry.state,
      seqs: entry.seqs,
      origin: origin,
      reason: reason,
      conflicts: conflicts,
      rescues: rescues,
      worked: worked(session)
    })
  end

  defp worked(session), do: session.touched |> Map.values() |> Enum.reduce(MapSet.new(), &MapSet.union/2)

  ## Rescues
  #
  # Unsaved work in blocks a write removed is brought back by one editor
  # still here: the blocks under one removed block (`group`, the top-most
  # one the write removed) all at once, as one copy (`kept_uid/5`), so two
  # editors' work in two children of one container comes back in one copy
  # of the container. One who changed them is asked first, else any editor
  # still here (the ones who did have left: `orphan?`). Never one whose
  # replica moved on with the reply of the call that caused the rebase (a
  # join, or the replica's own rebase: `exclude`), nor one that is going
  # away.
  #
  # Every editor computes what it would bring back; the one asked inserts
  # it and says so (`rescued/3`). The group is brought back when the
  # session has the copy's uid, whoever's insert put it there. If the one
  # asked has not brought it back within `rescue_timeout`, or leaves, the
  # next is asked (`:rescue`); with nobody left, the session waits once
  # more for a late insert before it reports the work lost. Every editor
  # that was here when the work was removed hears how it went.

  defp assign_rescues(session, _field, _old, _new, [], _exclude), do: {session, []}

  defp assign_rescues(session, field, old, new, conflicts, exclude) do
    here = session.clients |> Map.keys() |> Enum.filter(&Process.alive?/1) |> Enum.sort()
    able = Enum.reject(here, &(&1 == exclude or session.clients[&1].read_only))
    touched? = fn pid, uid -> MapSet.member?(Map.get(session.touched, pid, MapSet.new()), uid) end

    conflicts
    |> Enum.group_by(&removed_top(old, new, &1))
    |> Enum.reduce({session, []}, fn {group, uids}, {session, rescues} ->
      owners = Enum.filter(here, fn pid -> Enum.any?(uids, &touched?.(pid, &1)) end)
      orphan? = Enum.any?(uids, fn uid -> not Enum.any?(owners, &touched?.(&1, uid)) end)
      own_able = Enum.filter(owners, &(&1 in able))

      pending = %{
        group: group,
        kept: kept_uid(session, field, old, new, group),
        uids: uids,
        owners: owners,
        orphan?: orphan?,
        present: here
      }

      case own_able ++ (able -- own_able) do
        [] ->
          # nobody can bring it back: those it concerns are told at once
          rescued_broadcast(session, field, pending, false)
          {session, rescues}

        [rescuer | waiting] ->
          pending = Map.put(pending, :rescuer, rescuer)
          {put_rescue(session, field, pending, waiting), [pending | rescues]}
      end
    end)
    |> then(fn {session, rescues} -> {session, Enum.reverse(rescues)} end)
  end

  # The uid the group's copy takes, chosen here so every editor asked
  # inserts the same one, and only it settles the rescue: `<group>-kept`,
  # or `<group>-kept-2` and on when that is taken (an earlier copy of the
  # group, still there after the group came back, or one a rescue still
  # waits for). The blocks under the group take the same suffix, so none of
  # theirs is taken either.
  defp kept_uid(session, field, old, new, group) do
    claimed = for {{^field, _group}, %{kept: kept}} <- session.rescues, into: MapSet.new(), do: kept
    claimed = for {^field, kept} <- session.copy_uids, into: claimed, do: kept
    uids = [group | if(match?(%Ops{}, old), do: Ops.descendants(old, group), else: [])]
    taken? = fn uid -> uid in claimed or (match?(%Ops{}, new) and Ops.known?(new, uid)) end

    1
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(fn
      1 -> "-kept"
      n -> "-kept-#{n}"
    end)
    |> Enum.find(fn suffix -> not Enum.any?(uids, &taken?.(&1 <> suffix)) end)
    |> then(&(group <> &1))
  end

  # The top-most block above `uid` (or `uid`) that the write removed.
  defp removed_top(%Ops{} = old, %Ops{} = new, uid) do
    case Map.get(old.parents, uid) do
      nil -> uid
      parent -> if Ops.known?(new, parent), do: uid, else: removed_top(old, new, parent)
    end
  end

  defp removed_top(_old, _new, uid), do: uid

  defp put_rescue(session, field, pending, waiting) do
    token = make_ref()
    Process.send_after(self(), {:rescue_timeout, field, pending.group, token}, rescue_timeout())
    pending = Map.merge(pending, %{waiting: waiting, token: token, lost?: false})
    %{session | rescues: Map.put(session.rescues, {field, pending.group}, pending)}
  end

  # The copy is in the state: the group is back, whoever put it there.
  defp settle_rescues(session, field) do
    state = Data.state(session.data, field)

    session.rescues
    |> Enum.filter(fn {{f, _group}, pending} -> (f == field and state) && Ops.known?(state, pending.kept) end)
    |> Enum.reduce(session, fn {key, pending}, session ->
      rescued_broadcast(session, field, pending, true)
      %{session | rescues: Map.delete(session.rescues, key)}
    end)
  end

  # The one asked did not bring the group back: ask the next one still
  # here. With nobody left, wait once more for an insert still on its way,
  # then report the work lost.
  defp reassign_rescue(session, field, group) do
    case Map.fetch(session.rescues, {field, group}) do
      :error ->
        session

      {:ok, %{lost?: true} = pending} ->
        rescued_broadcast(session, field, pending, false)
        %{session | rescues: Map.delete(session.rescues, {field, group})}

      {:ok, pending} ->
        waiting = Enum.filter(pending.waiting, &(Map.has_key?(session.clients, &1) and Process.alive?(&1)))

        case waiting do
          [rescuer | rest] ->
            broadcast(session, field, %{kind: :rescue, epoch: session.data.epoch, group: group, rescuer: rescuer})
            put_rescue(session, field, %{Map.drop(pending, [:waiting, :token]) | rescuer: rescuer}, rest)

          [] ->
            session
            |> put_rescue(field, Map.drop(pending, [:waiting, :token]), [])
            |> update_in([Access.key(:rescues), {field, group}], &%{&1 | lost?: true})
        end
    end
  end

  defp rescued_broadcast(session, field, pending, ok?) do
    broadcast(session, field, %{
      kind: :rescued,
      epoch: session.data.epoch,
      group: pending.group,
      uids: pending.uids,
      owners: pending.owners,
      present: pending.present,
      orphan?: pending.orphan?,
      ok?: ok?
    })
  end

  defp reassign_rescues_of(session, pid) do
    session.rescues
    |> Enum.filter(fn {_key, pending} -> pending.rescuer == pid end)
    |> Enum.reduce(session, fn {{field, group}, _}, session -> reassign_rescue(session, field, group) end)
  end

  defp rescue_timeout do
    :brando |> Application.get_env(__MODULE__, []) |> Keyword.get(:rescue_timeout, 5_000)
  end

  defp info(session, field, pid, seeded?) do
    %{
      session: self(),
      epoch: session.data.epoch,
      rev: Data.rev(session.data, field),
      state: Data.state(session.data, field),
      seq: Data.seq(session.data, field, pid),
      seeded?: seeded?
    }
  end

  defp read_only?(session, pid) do
    match?(%{^pid => %{read_only: true}}, session.clients)
  end

  defp track(session, pid, field, opts) do
    session = cancel_stop(session)
    read_only = Keyword.get(opts, :read_only, false)

    case session.clients do
      %{^pid => client} ->
        put_in(session.clients[pid], %{client | fields: MapSet.put(client.fields, field), read_only: read_only})

      _ ->
        ref = Process.monitor(pid)

        put_in(session.clients[pid], %{
          ref: ref,
          user_id: opts[:user_id],
          read_only: read_only,
          fields: MapSet.new([field])
        })
    end
  end

  # An editor that left for a working copy (`detach/2`) and wrote it joins
  # with the rows it wrote: they replace what the session held when it
  # left, even when only their content changed (equal rows would join).
  defp do_join(session, pid, field, base, held, opts, :wrote_working_copy) do
    {session, conflicts} =
      session
      # the rows were written: every replica reads them again
      |> do_rebase(field, base, {:client, {:detached, pid}}, pid, :saved, pid)
      |> merge_held(field, held, opts[:held_base] || base, pid)

    {info, session} = joiner_info(session, field, pid, held, conflicts)
    {{:ok, info}, session}
  end

  defp do_join(session, pid, field, base, held, opts, _how) do
    rebase? = opts[:rebase] == true
    # Someone who may not change the entry brings nothing into the session,
    # not even through a rejoin with work it holds.
    {held, held_base} = if opts[:read_only], do: {base, base}, else: {held, opts[:held_base] || base}

    case Data.join(session.data, field, base, held, held_base) do
      {result, data} when result in [:seeded, :joined] ->
        session = %{session | data: data}
        {{:ok, info(session, field, pid, result == :seeded)}, session}

      {{:merged, conflicts}, data} ->
        session = %{session | data: data}
        broadcast_state(session, field, pid, :joined, conflicts, [])
        {info, session} = joiner_info(session, field, pid, held, conflicts)
        {{:ok, info}, session}

      {:mismatch, data} when rebase? ->
        {session, conflicts} =
          %{session | data: data}
          # the joiner read the rows again and they are not the ones the
          # session was built on: every editor reads them (`:rows_read`)
          |> do_rebase(field, base, :carry, pid, :rows_read, pid)
          |> merge_held(field, held, held_base, pid)

        {info, session} = joiner_info(session, field, pid, held, conflicts)
        {{:ok, info}, session}

      {:mismatch, data} ->
        {{:error, :base_mismatch}, %{session | data: data}}
    end
  end

  defp detached?(session, field, pid), do: Data.marked?(session.data, field, {:detached, pid})

  defp remove_client(session, pid) do
    case Map.pop(session.clients, pid) do
      {nil, _} ->
        session

      {client, clients} ->
        Process.demonitor(client.ref, [:flush])
        reassign_rescues_of(%{session | clients: clients, data: Data.drop_client(session.data, pid)}, pid)
    end
  end

  defp maybe_schedule_stop(%{clients: clients, stop_timer: nil} = session) when map_size(clients) == 0 do
    token = make_ref()
    %{session | stop_timer: {token, Process.send_after(self(), {:stop_if_idle, token}, session.grace_ms)}}
  end

  defp maybe_schedule_stop(session), do: session

  defp cancel_stop(%{stop_timer: nil} = session), do: session

  defp cancel_stop(%{stop_timer: {_token, timer}} = session) do
    Process.cancel_timer(timer)
    %{session | stop_timer: nil}
  end

  defp broadcast(session, field, message) do
    PubSub.broadcast(Brando.pubsub(), session.topic, {:edit_session, field, message})
  end

  defp grace_period do
    :brando |> Application.get_env(__MODULE__, []) |> Keyword.get(:grace_period, 30_000)
  end

  defp now, do: System.monotonic_time(:millisecond)
end
