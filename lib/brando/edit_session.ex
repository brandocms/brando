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
  @written_key {__MODULE__, :written}
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

  def whereis(key) do
    case Registry.lookup(@registry, key) do
      [{pid, _}] -> pid
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
  """
  @spec rebase(pid(), term(), Ops.t(), :own_save | {:after, non_neg_integer()} | :carry) ::
          {:ok, map()} | {:error, term()}
  def rebase(session, field, %Ops{} = base, mode) do
    GenServer.call(session, {:rebase, self(), field, base, mode})
  catch
    :exit, _ -> {:error, :no_session}
  end

  @doc "Stop being a replica of `field` (the block field went away)."
  @spec leave(pid(), term()) :: :ok
  def leave(session, field), do: GenServer.cast(session, {:leave, self(), field})

  @doc """
  The entry was written outside the editor. If a session is running for
  it, its block fields are rebased onto the rows as they are now, carrying
  every editor's unsaved work over (`Ops.carry/3`). The open editors receive
  the change like any other and do not reload.

  Call it in the process that wrote the entry, after the write, with the
  tenant prefix the entry belongs to.
  """
  @spec sync_saved(struct()) :: :ok
  def sync_saved(%_{} = entry), do: rebase_all(entry, :carry)

  @doc """
  Note that `entry` was written outside the editor. Inside `collecting/1`
  the entries are synced once the work succeeds (after its transaction has
  committed); otherwise at once, with `sync_saved/1`.
  """
  @spec written(struct()) :: :ok
  def written(%_{} = entry) do
    case Process.get(@written_key) do
      nil -> sync_saved(entry)
      entries -> Process.put(@written_key, [entry | entries]) && :ok
    end
  end

  @doc """
  Run `fun`, which may write entries in a transaction and report them with
  `written/1`. When it returns `{:ok, _}` or `:ok`, the open editors of those
  entries move onto the new rows (`sync_saved/1`); on anything else the
  writes were rolled back and nothing is synced.
  """
  @spec collecting((-> result)) :: result when result: var
  def collecting(fun) when is_function(fun, 0) do
    case Process.get(@written_key) do
      nil ->
        Process.put(@written_key, [])

        try do
          result = fun.()

          if match?({:ok, _}, result) or result == :ok do
            @written_key
            |> Process.get()
            |> Enum.reverse()
            |> Enum.uniq_by(&{&1.__struct__, &1.id})
            |> Enum.each(&sync_saved/1)
          end

          result
        after
          Process.delete(@written_key)
        end

      _nested ->
        fun.()
    end
  end

  @doc """
  This process saved the entry from the state it fetched with `purpose:
  :save`. The session moves onto the saved rows and keeps only the ops that
  arrived after the save read the state. For a save that leaves the editor
  (save and close, save and create new): the block fields that would
  otherwise do it are going away.
  """
  @spec saved(struct()) :: :ok
  def saved(%_{} = entry), do: rebase_all(entry, :own_save)

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
       grace_ms: grace_period(),
       stop_timer: nil
     }}
  end

  @impl true
  def handle_call({:join, pid, field, base, held, opts}, _from, session) do
    session = track(session, pid, field, opts)
    held_base = opts[:held_base] || base

    case Data.join(session.data, field, base, held, held_base) do
      {result, data} when result in [:seeded, :joined] ->
        session = %{session | data: data}
        {:reply, {:ok, info(session, field, pid, result == :seeded)}, session}

      {{:merged, conflicts}, data} ->
        session = %{session | data: data}
        broadcast_state(session, field, pid, :joined, conflicts)
        {:reply, {:ok, info(session, field, pid, false)}, session}

      {:mismatch, data} ->
        session = %{session | data: data}

        if opts[:rebase] do
          session =
            session
            |> do_rebase(field, base, :carry, pid, :joined)
            |> merge_held(field, held, held_base, pid)

          {:reply, {:ok, info(session, field, pid, false)}, session}
        else
          {:reply, {:error, :base_mismatch}, session}
        end
    end
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

  def handle_call({:rebase, pid, field, base, mode}, _from, session) do
    mode =
      case mode do
        :own_save -> {:client, pid}
        {:after, rev} -> {:after, rev, pid}
        :carry -> :carry
      end

    reason = if mode == :carry, do: :external, else: :saved
    session = do_rebase(session, field, base, mode, pid, reason)
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
        session = %{session | data: data}

        broadcast(session, field, %{
          kind: :op,
          epoch: data.epoch,
          rev: Data.rev(data, field),
          op: op,
          origin: {pid, seq}
        })

        {:noreply, session}

      {:error, reason} ->
        Logger.warning("[EditSession] rejected #{inspect(elem(op, 0))} for #{inspect(field)}: #{inspect(reason)}")
        send(pid, {:edit_session, field, %{kind: :rejected, epoch: session.data.epoch, seq: seq, reason: reason}})
        {:noreply, %{session | data: Data.note_seq(session.data, field, pid, seq)}}
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
    {:noreply, session |> remove_client(pid) |> maybe_schedule_stop()}
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
        session

      {{:merged, conflicts}, data} ->
        session = %{session | data: data}
        broadcast_state(session, field, pid, :joined, conflicts)
        session
    end
  end

  defp do_rebase(session, field, base, mode, origin, reason) do
    {:ok, data, conflicts} = Data.rebase(session.data, field, base, mode, now())
    session = %{session | data: data}

    if conflicts != [] do
      Logger.warning("[EditSession] unsaved work on #{inspect(conflicts)} could not be carried onto the new rows")
    end

    broadcast_state(session, field, origin, reason, conflicts)
    session
  end

  # The field's whole state, for every replica: after a rebase, or when a
  # joiner carried work onto it. `seqs` tells each replica which of its
  # pending ops the state already holds.
  defp broadcast_state(session, field, origin, reason, conflicts) do
    data = session.data
    entry = Map.fetch!(data.fields, field)

    broadcast(session, field, %{
      kind: :rebase,
      epoch: data.epoch,
      rev: entry.rev,
      base: entry.base,
      state: entry.state,
      seqs: entry.seqs,
      origin: origin,
      reason: reason,
      conflicts: conflicts
    })
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

  defp remove_client(session, pid) do
    case Map.pop(session.clients, pid) do
      {nil, _} ->
        session

      {client, clients} ->
        Process.demonitor(client.ref, [:flush])
        %{session | clients: clients, data: Data.drop_client(session.data, pid)}
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
