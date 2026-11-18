defmodule Brando.Content.Definitions.ReleaseStatus do
  @moduledoc """
  What the release's module definitions would change, planned in the
  background and kept per environment, for the admin to show: superusers see
  how many changes wait, and Block modules marks each module that differs
  (`Brando.Content.Definitions.Release`).

  It starts with Brando when `release_path` is configured, on every node but
  a sandboxed test's. On a node whose endpoint serves (not a Mix task or a
  release's `eval`), a few seconds after boot it plans every environment, one
  after another, without holding up anything else; planning also records the
  definitions that equal the files as applied. It applies nothing.

  The result is kept with the release's and the database's digests. A change
  to an environment's definitions (`changed/1`: a module saved or deleted, a
  table template saved, definitions applied or imported, the environment
  copied over, restored from an archive or created) plans that environment
  again, on the node that made the change, once the burst has settled (half a
  second after the last change, five at most). That node keeps the result
  and sends it to the others through `Brando.CacheSync`, which keep it
  without planning. A node running another release (during a rolling deploy)
  plans that environment itself instead, and keeps the result to itself.
  Results are ordered by when their database digest was taken: an older one
  never replaces a newer.
  """
  use GenServer

  require Logger

  alias Brando.Content.Definition.{Baselines, Snapshot, Value}
  alias Brando.Content.Definitions
  alias Brando.Content.Definitions.Release
  alias Brando.Tenant

  @table __MODULE__
  @boot_delay 3_000
  @debounce 500
  @max_wait 5_000
  @server_opts [:boot, :delay, :debounce, :max_wait]

  @doc """
  Its child spec when release definitions are configured, outside a sandboxed
  test, otherwise none. It plans at boot only where the endpoint serves.
  """
  def children do
    if Release.enabled?() and not sandbox?(), do: [{__MODULE__, boot: serving?()}], else: []
  end

  defp serving? do
    endpoint = Brando.endpoint()
    Phoenix.Endpoint.server?(Brando.otp_app(), endpoint)
  rescue
    _ -> false
  end

  defp sandbox?, do: Brando.Repo.repo().config()[:pool] == Ecto.Adapters.SQL.Sandbox

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Plans `prefix` (nil without tenancy) again on this node once the burst of
  changes has settled, and sends the result to the other nodes. Call it once
  the change has committed (`Brando.Content.Definitions.changed/1` does).
  Without a running server here (a Mix task, a test) it does nothing.
  """
  def changed(prefix), do: GenServer.cast(__MODULE__, {:changed, prefix, true})

  @impl GenServer
  def init(opts) do
    ensure_table()

    if Keyword.get(opts, :boot, true),
      do: Process.send_after(self(), :boot, Keyword.get(opts, :delay, @boot_delay))

    {:ok, %{opts: opts, pending: %{}, timer: nil, first_at: nil}}
  end

  @impl GenServer
  def handle_cast({:changed, prefix, broadcast?}, state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    now = System.monotonic_time(:millisecond)
    first_at = state.first_at || now

    wait =
      min(Keyword.get(state.opts, :debounce, @debounce), first_at + Keyword.get(state.opts, :max_wait, @max_wait) - now)

    pending = Map.update(state.pending, prefix, broadcast?, &(&1 or broadcast?))
    {:noreply, %{state | pending: pending, first_at: first_at, timer: Process.send_after(self(), :run, max(wait, 0))}}
  end

  @impl GenServer
  def handle_info(:boot, state) do
    Enum.each(Release.prefixes(), &refresh(&1, plan_opts(state)))
    {:noreply, state}
  end

  def handle_info(:run, state) do
    Enum.each(state.pending, fn {prefix, broadcast?} ->
      if refresh(prefix, plan_opts(state)) == :planned and broadcast?, do: broadcast(prefix)
    end)

    {:noreply, %{state | pending: %{}, timer: nil, first_at: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp plan_opts(state), do: Keyword.drop(state.opts, @server_opts)

  defp broadcast(prefix) do
    case lookup(prefix) do
      %{release: release} = value when is_binary(release) ->
        Brando.CacheSync.broadcast(__MODULE__, {:planned, prefix, value})

      _off ->
        :ok
    end
  end

  @doc """
  Keeps a result another node planned (`Brando.CacheSync`), unless this node
  has a newer one. One planned for another release than this node's is
  planned again here instead.
  """
  def refresh_node_cache({:planned, prefix, %{release: release} = value}) do
    case lookup(prefix) do
      nil ->
        store_newer(prefix, value)

      %{release: ^release} ->
        store_newer(prefix, value)

      _other_release ->
        GenServer.cast(__MODULE__, {:changed, prefix, false})
    end

    :ok
  end

  def refresh_node_cache(_refresh), do: :ok

  @doc """
  Plans `prefix` (nil without tenancy) again unless the release and the
  database are as they were when it last did, and keeps the result. Returns
  `:unchanged`, `:planned` or `:off`.
  """
  def refresh(prefix, opts \\ []) do
    ensure_table()
    Tenant.with_prefix(prefix, fn -> refresh_here(prefix, opts) end)
  rescue
    error -> off(prefix, Exception.message(error))
  end

  defp refresh_here(prefix, opts) do
    path = Release.path(opts)

    with true <- is_binary(path) and File.dir?(path),
         {:ok, bundle} <- Definitions.read(path) do
      release_digest = Value.digest(bundle)
      # Taken before planning: a change committed while it plans makes the
      # next check plan again rather than keep this result
      taken_at = System.os_time(:microsecond)
      database = database_digest()

      if cached?(prefix, release_digest, database),
        do: :unchanged,
        else: plan!(prefix, %{release: release_digest, database: database, taken_at: taken_at}, opts)
    else
      false -> off(prefix, nil)
      {:error, message} -> off(prefix, message)
    end
  end

  defp cached?(prefix, release_digest, database) do
    match?(%{release: ^release_digest, database: ^database}, lookup(prefix))
  end

  defp off(prefix, nil) do
    store(prefix, off())
    :off
  end

  defp off(prefix, message) do
    Logger.warning("==> Brando >> Could not plan the release's module definitions: #{message}")
    store(prefix, off())
    :off
  end

  # Nothing to show, and no release to compare another node's result with
  defp off, do: %{release: nil, error: :off}

  defp plan!(prefix, digests, opts) do
    case Release.plan(opts) do
      {:ok, %{} = report} ->
        states = for item <- report.items, item.state != :in_sync, into: %{}, do: {item.uid, item.state}

        store_newer(
          prefix,
          Map.merge(digests, %{version: report.version, pending: report.pending, states: states, error: nil})
        )

        :planned

      {:ok, :off} ->
        store(prefix, off())
        :off

      {:error, message} ->
        Logger.warning("==> Brando >> Could not plan the release's module definitions: #{message}")
        store_newer(prefix, Map.merge(digests, %{error: message, pending: 0, states: %{}}))
        :planned
    end
  end

  # Everything planning compares: the stored definitions and what was last
  # applied here
  defp database_digest do
    {snapshot, _records} = Snapshot.take!(all_tables: true)
    applied = Map.new(Baselines.latest(), fn {key, row} -> {key, row.digest} end)
    Value.digest(%{"definitions" => snapshot["baseline"], "applied" => applied})
  end

  @doc """
  The release's changes waiting in `prefix` (the current environment by
  default): `%{version: version, pending: count, states: %{uid => state}}`,
  or nil when there is nothing to say yet, or nothing configured.
  """
  def summary(prefix \\ Tenant.current_prefix()) do
    case lookup(prefix) do
      %{error: nil} = summary -> Map.take(summary, [:version, :pending, :states])
      _ -> nil
    end
  end

  @doc """
  How the module `uid` in the current environment relates to the release's
  file, for a marker: `:changed_in_release`, `:changed_in_admin`,
  `:changed_in_both`, `:never_applied`, `:new` or `:deleted`, or nil when they
  agree or nothing is known.
  """
  def state(uid, prefix \\ Tenant.current_prefix()) do
    case summary(prefix) do
      %{states: states} -> states[uid]
      nil -> nil
    end
  end

  defp lookup(prefix) do
    case :ets.lookup(@table, prefix || :public) do
      [{_, value}] -> value
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  defp store(prefix, value) do
    ensure_table()
    :ets.insert(@table, {prefix || :public, value})
  end

  # A result whose database digest was taken before the one kept is older
  defp store_newer(prefix, value) do
    taken_at = Map.get(value, :taken_at, 0)

    case lookup(prefix) do
      %{taken_at: kept} when is_integer(kept) and kept > taken_at -> false
      _ -> store(prefix, value)
    end
  end

  @doc """
  Creates the table the results are kept in. `Brando.Supervisor` owns it, so
  it outlives the server and whatever process planned.
  """
  def init_cache do
    ensure_table()
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined,
      do: :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc false
  def clear, do: if(:ets.whereis(@table) != :undefined, do: :ets.delete_all_objects(@table))
end
