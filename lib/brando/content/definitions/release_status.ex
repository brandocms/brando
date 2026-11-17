defmodule Brando.Content.Definitions.ReleaseStatus do
  @moduledoc """
  What the release's module definitions would change, planned in the
  background after boot and kept per environment, for the admin to show:
  superusers see how many changes wait, and Block modules marks each module
  that differs (`Brando.Content.Definitions.Release`).

  It starts with Brando when `release_path` is configured and the endpoint
  serves (a running server, not a Mix task or a release's `eval`). A few
  seconds after boot it plans every environment, one after another, without
  holding up anything else; planning also records the definitions that equal
  the files as applied. It applies nothing.

  The result is kept with the release's and the database's digests. When a
  module is saved or definitions are applied, on any node, it works the
  digests out again and plans only the environments whose digest changed.
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

  @doc "Its child spec when release definitions are configured and this node serves, otherwise none."
  def children do
    if Release.enabled?() and serving?() and not sandbox?(), do: [__MODULE__], else: []
  end

  defp serving? do
    endpoint = Brando.endpoint()
    Phoenix.Endpoint.server?(Brando.otp_app(), endpoint)
  rescue
    _ -> false
  end

  defp sandbox?, do: Brando.Repo.repo().config()[:pool] == Ecto.Adapters.SQL.Sandbox

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl GenServer
  def init(opts) do
    ensure_table()
    Phoenix.PubSub.subscribe(Brando.pubsub(), Definitions.topic())
    Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:modules")
    timer = Process.send_after(self(), :refresh, Keyword.get(opts, :delay, @boot_delay))
    {:ok, %{timer: timer, opts: opts}}
  end

  @impl GenServer
  def handle_info(:refresh, state) do
    Enum.each(Release.prefixes(), &refresh(&1, state.opts))
    {:noreply, %{state | timer: nil}}
  end

  # A module saved in the admin, or definitions applied: check again, once
  # the burst has settled
  def handle_info(_changed, state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    {:noreply, %{state | timer: Process.send_after(self(), :refresh, @debounce)}}
  end

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
      if cached?(prefix, release_digest), do: :unchanged, else: plan!(prefix, release_digest, opts)
    else
      false -> off(prefix, nil)
      {:error, message} -> off(prefix, message)
    end
  end

  defp cached?(prefix, release_digest) do
    case lookup(prefix) do
      %{release: ^release_digest, database: database} when not is_nil(database) -> database == database_digest()
      _ -> false
    end
  end

  defp off(prefix, nil) do
    store(prefix, nil)
    :off
  end

  defp off(prefix, message) do
    Logger.warning("==> Brando >> Could not plan the release's module definitions: #{message}")
    store(prefix, nil)
    :off
  end

  # The database's digest is taken before planning: a change committed while
  # it plans makes the next check plan again rather than keep this result
  defp plan!(prefix, release_digest, opts) do
    database = database_digest()

    case Release.plan(opts) do
      {:ok, %{} = report} ->
        states = for item <- report.items, item.state != :in_sync, into: %{}, do: {item.uid, item.state}

        store(prefix, %{
          release: release_digest,
          database: database,
          version: report.version,
          pending: report.pending,
          states: states,
          error: nil
        })

        :planned

      {:ok, :off} ->
        store(prefix, nil)
        :off

      {:error, message} ->
        Logger.warning("==> Brando >> Could not plan the release's module definitions: #{message}")
        store(prefix, %{release: release_digest, database: database, error: message, pending: 0, states: %{}})
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
