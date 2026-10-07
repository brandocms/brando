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

  Returns `{:ok, info}` with `:session`, `:epoch`, `:rev`, `:state` and
  `:seeded?`. When the caller's rows are not the ones the session is built
  on, `{:error, :base_mismatch}`, unless `rebase: true` is given: then the
  caller's freshly loaded rows are taken as written outside the session and
  the unsaved work is carried onto them for everyone (see `rebase/4`).

  Options: `:user_id` (for the session's own bookkeeping) and `:rebase`.
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

  `mode` is `{:after, rev}` when the caller saved the state it fetched at
  `rev`, `:carry` when the rows were written outside the session.
  """
  @spec rebase(pid(), term(), Ops.t(), {:after, non_neg_integer()} | :carry) :: {:ok, map()} | {:error, term()}
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
  def sync_saved(%schema{} = entry) do
    with pid when is_pid(pid) <- whereis(ref_for(entry)),
         true <- schema.has_trait(Brando.Trait.Blocks) do
      entry = Brando.Repo.preload(entry, Brando.Content.BlockPreloads.for_schema(schema), force: true)

      for %{name: field} <- schema.__blocks_fields__() do
        base = entry |> Map.get(:"entry_#{field}") |> List.wrap() |> Ops.from_entry_blocks()
        rebase(pid, field, base, :carry)
      end
    end

    :ok
  rescue
    error ->
      Logger.error("[EditSession] sync after an outside save failed: " <> Exception.message(error))
      :ok
  end

  ## Server

  def start_link(%{key: key} = args) do
    GenServer.start_link(__MODULE__, args, name: {:via, Registry, {@registry, key}}, hibernate_after: 15_000)
  end

  @impl true
  def init(%{key: {prefix, _schema, _id, _language} = key, topic: topic}) do
    if prefix, do: Tenant.put_prefix(prefix)

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
  def handle_call({:join, pid, field, base, state, opts}, _from, session) do
    session = track(session, pid, field, opts[:user_id])

    case Data.join(session.data, field, base, state) do
      {result, data} when result in [:seeded, :joined] ->
        {:reply, {:ok, info(%{session | data: data}, field, result == :seeded)}, %{session | data: data}}

      {:mismatch, data} ->
        if opts[:rebase] do
          session = do_rebase(%{session | data: data}, field, base, :carry, pid, :joined)
          {:reply, {:ok, info(session, field, false)}, session}
        else
          {:reply, {:error, :base_mismatch}, %{session | data: data}}
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
        {:reply, {:ok, info(session, field, false)}, session}
    end
  end

  def handle_call({:rebase, pid, field, base, mode}, _from, session) do
    mode = if match?({:after, _}, mode), do: {:after, elem(mode, 1), pid}, else: mode
    reason = if is_tuple(mode), do: :saved, else: :external
    session = do_rebase(session, field, base, mode, pid, reason)
    {:reply, {:ok, info(session, field, false)}, session}
  end

  @impl true
  def handle_cast({:op, pid, field, op, seq}, session) do
    case Data.apply_op(session.data, field, op) do
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
        {:noreply, session}
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

  defp do_rebase(session, field, base, mode, origin, reason) do
    {:ok, data, conflicts} = Data.rebase(session.data, field, base, mode, now())
    session = %{session | data: data}

    if conflicts != [] do
      Logger.warning("[EditSession] unsaved work on #{inspect(conflicts)} could not be carried onto the new rows")
    end

    broadcast(session, field, %{
      kind: :rebase,
      epoch: data.epoch,
      rev: Data.rev(data, field),
      base: base,
      state: Data.state(data, field),
      origin: origin,
      reason: reason,
      conflicts: conflicts
    })

    session
  end

  defp info(session, field, seeded?) do
    %{
      session: self(),
      epoch: session.data.epoch,
      rev: Data.rev(session.data, field),
      state: Data.state(session.data, field),
      seeded?: seeded?
    }
  end

  defp track(session, pid, field, user_id) do
    session = cancel_stop(session)

    case session.clients do
      %{^pid => client} ->
        put_in(session.clients[pid], %{client | fields: MapSet.put(client.fields, field)})

      _ ->
        ref = Process.monitor(pid)
        put_in(session.clients[pid], %{ref: ref, user_id: user_id, fields: MapSet.new([field])})
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
