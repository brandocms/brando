defmodule Brando.Crypto.Marker do
  @moduledoc """
  The installation's record of which secret and which host wrote its
  database: one row in `public.crypto_marker`, holding a value encrypted with
  `Brando.Crypto` and, in plain text, the endpoint's configured host.

  A database can differ from the installation it starts under in two ways,
  and `state/0` tells them apart:

    * the key: `:ours` (the value decrypts), `:foreign` (it does not: another
      secret wrote the database), `:none` (no row yet) or `:unknown` (the
      table is not there, or the database could not be read);
    * the host: `:same` or `:other` (the database is a copy from another
      installation), nil without a row.

  ## At start

  A node that serves the endpoint checks the marker before Oban starts
  (`children/0`, the first child of `Brando.Supervisor`), within five
  seconds, and never stops the boot:

    * another host wrote it: every active webhook and notification route, in
      `public` and every site environment, is paused by hand (`:manual`, its
      secret kept), so a copy of production's database calls no real
      endpoint; so is every one paused for an environment copy, which would
      resume when that environment goes live. The row records where the database came from, when, and
      what was paused, for the dashboard's notice, and takes this host. That
      happens once per move: the next start finds the same host.
    * no marker: written now, with this secret and host, when
      `Brando.Crypto.Audit` finds nothing this secret cannot read; otherwise
      nothing is written and the warning below is logged.
    * another secret wrote it: one warning in the log. Nothing is changed;
      `Brando.Crypto.Audit.forget/2` is the clean-up, run by hand.

  `mix brando.doctor`, `bin/my_app eval`, other Mix tasks and the test suite
  do not run it.
  """
  use Ecto.Schema

  import Ecto.Query, only: [from: 2]

  alias Brando.Repo

  require Logger

  @schema_prefix "public"
  @primary_key {:id, :integer, autogenerate: false}
  @context "brando.crypto_marker"
  @plaintext "brando"
  @start_timeout 5_000
  # How many paused webhooks and routes the record names; the rest are counted
  @named_paused 20

  @type key_state :: :ours | :foreign | :none | :unknown
  @type host_state :: :same | :other | nil
  @type t :: %__MODULE__{}

  schema "crypto_marker" do
    field :value, :string, redact: true
    field :host, :string
    field :moved_from, :string
    field :moved_at, :utc_datetime_usec
    field :moved_key, :string
    field :paused, {:array, :map}, default: []
    field :paused_dismissed_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  ## Reading

  @doc """
  The key and host states, and the row (nil without one). Reads only.
  """
  @spec state() :: %{key: key_state(), host: host_state(), marker: t() | nil}
  def state do
    if table?() do
      case Repo.one(from(m in __MODULE__, where: m.id == 1)) do
        nil -> %{key: :none, host: nil, marker: nil}
        marker -> %{key: key_state(marker), host: host_state(marker), marker: marker}
      end
    else
      %{key: :unknown, host: nil, marker: nil}
    end
  rescue
    error ->
      Logger.warning("[Brando.Crypto.Marker] Could not read the marker: " <> Exception.message(error))
      %{key: :unknown, host: nil, marker: nil}
  end

  defp key_state(%__MODULE__{value: value}) do
    if Brando.Crypto.decrypt(value, @context) == {:ok, @plaintext}, do: :ours, else: :foreign
  end

  defp host_state(%__MODULE__{host: host}), do: if(host == host(), do: :same, else: :other)

  @doc false
  def table? do
    %{rows: [[table]]} = Repo.repo().query!("SELECT to_regclass('public.crypto_marker')::text")
    not is_nil(table)
  end

  @doc """
  The host this installation writes as: the endpoint's configured URL host
  (`config :my_app, MyAppWeb.Endpoint, url: [host: …]`), `"localhost"`
  without one. Read from the configuration when the endpoint is not started.
  """
  @spec host() :: String.t()
  def host do
    endpoint = Brando.endpoint()

    url =
      try do
        endpoint.config(:url)
      rescue
        ArgumentError -> Keyword.get(Application.get_env(Brando.otp_app(), endpoint, []), :url)
      end

    (url || [])[:host] || "localhost"
  end

  ## Writing

  @doc """
  Writes the marker with this secret, after `Brando.Crypto.Audit.forget/2`.
  A row there keeps its host, so a database from another host is still
  paused and recorded as a move at the next serving start, and keeps a move
  already recorded, except for the key it came with: what this secret
  cannot read is forgotten, so another secret found later means this
  installation's changed. Without a row, one is written with this host; two
  nodes doing it at once write one.
  """
  @spec write() :: :ok
  def write do
    now = DateTime.utc_now()

    Repo.insert!(
      %__MODULE__{
        id: 1,
        value: Brando.Crypto.encrypt(@plaintext, @context),
        host: host(),
        inserted_at: now,
        updated_at: now
      },
      on_conflict: {:replace, [:value, :moved_key, :updated_at]},
      conflict_target: :id
    )

    :ok
  end

  @doc "The notice of a move is put away: `paused_dismissed_at` is set."
  @spec dismiss_paused() :: :ok
  def dismiss_paused do
    Repo.update_all(from(m in __MODULE__, where: m.id == 1 and not is_nil(m.moved_at)),
      set: [paused_dismissed_at: DateTime.utc_now()]
    )

    :ok
  end

  @doc """
  The move to show on the dashboard: where the database came from, when, and
  what was paused there, until the notice is dismissed. Nil otherwise.
  """
  @spec move_notice() :: nil | %{from: String.t(), at: DateTime.t(), paused: [map()]}
  def move_notice do
    case table?() && Repo.one(from(m in __MODULE__, where: m.id == 1)) do
      %__MODULE__{moved_at: %DateTime{} = at, paused_dismissed_at: nil} = marker ->
        %{from: marker.moved_from, at: at, paused: marker.paused}

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  ## At start

  @doc """
  The child that checks the marker as `Brando.Supervisor` starts, before
  Oban: only on a node that serves the endpoint, outside the SQL sandbox.
  """
  @spec children() :: [Supervisor.child_spec()]
  def children do
    if serving?() and not sandbox?(), do: [%{id: __MODULE__, start: {__MODULE__, :start_link, []}}], else: []
  end

  @doc false
  # Runs the check and starts nothing: the supervisor moves on to the next child
  def start_link do
    task = Task.async(fn -> safely(&check_at_start/0) end)

    case Task.yield(task, @start_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, :ok} ->
        :ok

      {:ok, {:error, message}} ->
        Logger.error("[Brando.Crypto.Marker] Could not check the encryption marker at start: " <> message)

      nil ->
        Logger.error(
          "[Brando.Crypto.Marker] The encryption marker check did not finish in time; the node starts without it"
        )
    end

    :ignore
  end

  defp safely(fun) do
    fun.()
  rescue
    error -> {:error, Exception.message(error)}
  catch
    kind, reason -> {:error, Exception.format(kind, reason)}
  end

  defp serving? do
    Phoenix.Endpoint.server?(Brando.otp_app(), Brando.endpoint())
  rescue
    _ -> false
  end

  defp sandbox?, do: Repo.repo().config()[:pool] == Ecto.Adapters.SQL.Sandbox

  @doc """
  What a serving node does with the marker at start (see the moduledoc).
  Returns `:ok`; logs what it found.
  """
  @spec check_at_start() :: :ok
  def check_at_start do
    case state() do
      %{key: :unknown} ->
        Logger.warning(
          "[Brando.Crypto.Marker] No encryption marker table: run the migrations. The database is not checked."
        )

      %{host: :other} ->
        after_move()

      %{key: :none} ->
        write_if_readable()

      %{key: :foreign} ->
        warn_foreign()

      %{key: :ours} ->
        :ok
    end

    :ok
  end

  defp write_if_readable do
    if Brando.Crypto.Audit.unreadable?(Brando.Crypto.Audit.run()), do: warn_foreign(), else: insert_new()
  end

  defp insert_new do
    now = DateTime.utc_now()

    Repo.insert!(
      %__MODULE__{
        id: 1,
        value: Brando.Crypto.encrypt(@plaintext, @context),
        host: host(),
        inserted_at: now,
        updated_at: now
      },
      on_conflict: :nothing,
      conflict_target: :id
    )

    :ok
  end

  defp warn_foreign do
    Logger.warning(
      "[Brando.Crypto.Marker] This database holds values encrypted with another secret than this installation's " <>
        "(Brando.Crypto). Two-factor sign-in, webhooks and notification routes written with it fail here. " <>
        "Run mix brando.doctor, or see \"Copying a database between environments\" in the deployment guide."
    )
  end

  # Under the row's lock, so that of two nodes starting at once one pauses
  # and the other then finds this host
  defp after_move do
    {:ok, result} =
      Repo.transaction(fn ->
        marker = Repo.one(from(m in __MODULE__, where: m.id == 1, lock: "FOR UPDATE"))

        if marker && marker.host != host() do
          record_move(marker, key_state(marker))
        else
          :already_recorded
        end
      end)

    if result != :already_recorded, do: log_move(result)
    :ok
  end

  defp record_move(marker, key) do
    paused = pause_everywhere()
    now = DateTime.utc_now()

    Repo.update_all(from(m in __MODULE__, where: m.id == 1),
      set: [
        host: host(),
        moved_from: marker.host,
        moved_at: now,
        moved_key: to_string(key),
        paused: paused,
        paused_dismissed_at: nil,
        updated_at: now
      ]
    )

    if key == :foreign, do: warn_foreign()
    %{from: marker.host, paused: paused}
  end

  defp log_move(%{from: from, paused: paused}) do
    count = paused |> Enum.map(& &1["count"]) |> Enum.sum()

    Logger.warning(
      "[Brando.Crypto.Marker] This database was written by #{from}, not #{host()}: #{count} webhook(s) and " <>
        "notification route(s) were paused so that the copy calls no real endpoint. Resume them by hand."
    )
  end

  # Per site environment and kind: how many were paused, naming the first
  # ones for the dashboard
  defp pause_everywhere do
    for prefix <- Brando.Crypto.Audit.prefixes(),
        {kind, pause} <- [
          {"webhook", &Brando.Webhooks.pause_active/3},
          {"notification_route", &Brando.Notifications.Routing.pause_active/3}
        ],
        paused = pause.(prefix, :system, @named_paused),
        paused.count > 0 do
      %{"prefix" => prefix, "kind" => kind, "count" => paused.count, "named" => paused.named}
    end
  end
end
