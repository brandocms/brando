defmodule Brando.Tenant.ServedHosts do
  @moduledoc """
  Keeps a file of the hosts this installation serves, for the reverse proxy in
  front of it to route and certify.

  On a `tenancy_mode: :multi` installation a superuser binds a host to a
  site's environment in the admin. The proxy learns about the host from this
  file: whatever deploys the installation turns it into routes and
  certificates. Brando writes no proxy configuration.

      config :brando, Brando.Tenant.ServedHosts,
        # Unset: the feature is off, and nothing is written
        file: "/srv/my_app/shared/served_hosts",
        # Optional. Default: the addresses the endpoint's host resolves to
        addresses: ["203.0.113.10"],
        # Optional. `:always` admits every bound host without the DNS check,
        # for an installation behind a CDN or another proxy
        admit: :dns

  Read when each check runs, so a release sets it in `config/runtime.exs`.

  ## Which hosts

  Every host the registry binds (`Brando.Tenant.Cache.bound_hosts/0`) that is a
  full host name: valid (`Brando.Environments.Environment.valid_host?/1`), with
  a dot, and not an IP address. A bound domain without a dot (`intranet`), an
  address, or a domain stored before Brando checked it is still answered on,
  but never written. A bound host that is not in the file yet is admitted
  when it resolves, and every address it resolves to, IPv4 and IPv6, is one
  of this server's: a proxy asks for a certificate as soon as it gets a host,
  and a host whose DNS still points elsewhere fails that request. Once in the file, a host stays until no
  environment binds it; a failed lookup never removes one. The file is the
  state: nothing is stored in the database, and on a new server each host is
  admitted again when its DNS arrives there.

  ## When

  After every warm of `Brando.Tenant.Cache`, which runs at boot and on every
  node after a registry write, and once a minute (`:retry_interval`, in
  milliseconds) while a bound host waits for its DNS or the file could not be
  written. Otherwise every five minutes (`:recheck_interval`): the file is
  read again, as another node sharing the path may have written over it. A
  bound host this process has seen in the file or admitted itself goes back
  in without a lookup; one it has not is admitted again. That memory is the
  process's own, so after a restart a lost host is admitted again too.
  Nothing is looked up while the file holds every bound host. Each node keeps
  its own file.

  ## The file

  Sorted, one host per line, each followed by a newline, empty when no host
  is admitted. Written to a temporary file in the same directory, synced to
  disk and renamed over the old one, and only when the content changes. A
  line that is not a bound host is dropped on the next write. A file that
  cannot be written is logged once and retried on the next check.

  Lookups go through `:resolver`, a module implementing
  `Brando.Tenant.ServedHosts.Resolver` (default
  `Brando.Tenant.ServedHosts.DNS`), which tests replace. A lookup that does
  not answer within `:lookup_timeout` milliseconds (default ten seconds), or
  that raises, exits or throws, fails for that host.
  """

  use GenServer

  alias Brando.Environments.Environment
  alias Brando.Tenant.Cache

  require Logger

  @topic "brando:served_hosts"
  @status_key {__MODULE__, :status}
  @retry_interval :timer.minutes(1)
  @recheck_interval :timer.minutes(5)
  @lookup_timeout :timer.seconds(10)
  # Seconds
  @leftover_age 60

  @typedoc """
  Where a bound host stands: in the file (`:served`), admitted but the file
  could not be written (`:not_written`), resolving to addresses that are not
  all this server's (`{:waiting, addresses}`), not resolving, or never written
  because it is not a full host name (`:invalid`).
  """
  @type host_state :: :served | :not_written | {:waiting, [String.t()]} | :unresolved | :invalid

  @type status :: %{
          file: String.t() | nil,
          hosts: %{String.t() => host_state()},
          addresses: [String.t()],
          error: String.t() | nil
        }

  # Public API

  @doc "Whether a file is configured."
  @spec enabled?() :: boolean()
  def enabled?, do: config() |> Keyword.get(:file) |> configured_file?()

  @doc """
  What the last check found, for the admin: the file, each bound host's
  state, this server's addresses as looked up then, and the error writing the
  file, if any. Nothing is looked up here.
  """
  @spec status() :: status()
  def status, do: :persistent_term.get(@status_key, empty_status())

  @doc "The PubSub topic a changed `status/0` is broadcast on, on this node only, as `{:served_hosts, status}`."
  @spec topic() :: String.t()
  def topic, do: @topic

  @doc "Asks this node's process to check, after a registry refresh. Does nothing when no file is configured."
  @spec registry_changed() :: :ok
  def registry_changed do
    if enabled?(), do: GenServer.cast(__MODULE__, :check)
    :ok
  end

  @doc "Checks now and returns the status. For tests."
  @spec check() :: status()
  def check, do: GenServer.call(__MODULE__, :check, :timer.minutes(1))

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  # Server

  @impl true
  def init(nil) do
    # `admitted`: the hosts this process saw in the file or admitted itself, kept
    # while bound. In memory only: a new process starts from the file alone.
    # `tick`: the reference the pending timer's message carries
    state = %{timer: nil, tick: nil, error: nil, admitted: MapSet.new()}
    # A restart after boot finds the cache warmed and hears no warm for it
    if enabled?() and Cache.warmed?(), do: {:ok, state, {:continue, :check}}, else: {:ok, state}
  end

  @impl true
  def handle_continue(:check, state), do: {:noreply, run(state)}

  @impl true
  def handle_cast(:check, state), do: {:noreply, run(state)}

  @impl true
  def handle_call(:check, _from, state) do
    state = run(state)
    {:reply, status(), state}
  end

  @impl true
  # A cold cache binds no host, and a check then would empty the file. A tick
  # of a timer cancelled after it fired is not the current one, and ignored.
  def handle_info({:tick, tick}, %{tick: tick} = state) do
    state = %{state | timer: nil, tick: nil}
    if Cache.warmed?(), do: {:noreply, run(state)}, else: {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp run(state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    state = %{state | timer: nil, tick: nil}
    config = config()

    if configured_file?(config[:file]) do
      check(state, config)
    else
      %{state | error: nil}
    end
  rescue
    # A bad config or a resolver that raises must not restart this process
    # until its supervisor, and the application with it, gives up
    exception ->
      error = Exception.message(exception)
      state = report(state, nil, error)
      publish(%{status() | error: error})
      schedule(state, true)
  end

  defp check(state, config) do
    file = config[:file]

    case read_file(file) do
      {:ok, existing, listed} ->
        bound = Enum.filter(Cache.bound_hosts(), &servable?/1)
        listed = MapSet.new(listed)
        # Another node sharing the path may have written over a host this one
        # admitted: it goes back in without a lookup
        known = MapSet.union(listed, state.admitted)
        {kept, candidates} = Enum.split_with(bound, &MapSet.member?(known, &1))
        {admitted, waiting, addresses} = admit(candidates, config)
        # The registry may have changed while the lookups ran
        {still_bound, invalid} = Enum.split_with(Cache.bound_hosts(), &servable?/1)
        still_bound = MapSet.new(still_bound)
        hosts = (kept ++ admitted) |> Enum.filter(&MapSet.member?(still_bound, &1)) |> Enum.sort()
        waiting = Map.filter(waiting, fn {host, _state} -> MapSet.member?(still_bound, host) end)

        {written?, error} = write(file, existing, hosts)
        state = %{report(state, file, error) | admitted: MapSet.new(hosts)}

        statuses =
          Map.new(hosts, &{&1, if(written? or MapSet.member?(listed, &1), do: :served, else: :not_written)})
          |> Map.merge(waiting)
          |> Map.merge(Map.new(invalid, &{&1, :invalid}))

        publish(%{file: file, hosts: statuses, addresses: Enum.map(addresses, &format_address/1), error: error})
        schedule(state, map_size(waiting) > 0 or error != nil)

      {:error, reason} ->
        error = "#{file}: #{:file.format_error(reason)}"
        state = report(state, file, error)
        publish(%{status() | file: file, error: error})
        schedule(state, true)
    end
  end

  # A stored domain is not checked again until it changes, and the file is read
  # by root: only a host name with a dot that is not an IP address gets a line.
  # Every top-level domain begins with a letter. A last label that does not
  # makes the name an IPv4 literal to some resolver: `203.0.113.10`, and the
  # relaxed forms `203.0.113.0x0a` or `0xcb.0x00.0x71.0x0a`, which
  # `:inet.parse_address/1` reads only in part.
  defp servable?(host) do
    Environment.valid_host?(host) and String.contains?(host, ".") and
      host |> String.split(".") |> List.last() |> String.match?(~r/\A[a-z]/i)
  end

  # Soon while a host waits or something failed. Otherwise slowly, all the
  # same: another node sharing the path may have written over the file.
  defp schedule(state, retry?) do
    interval =
      if retry?,
        do: interval(:retry_interval, @retry_interval),
        else: interval(:recheck_interval, @recheck_interval)

    tick = make_ref()
    %{state | timer: Process.send_after(self(), {:tick, tick}, interval), tick: tick}
  end

  defp interval(key, default) do
    config = config()

    case Keyword.keyword?(config) && Keyword.get(config, key) do
      milliseconds when is_integer(milliseconds) and milliseconds > 0 -> milliseconds
      _unset -> default
    end
  end

  # Hosts not yet in the file. No lookups at all when there are none.
  defp admit([], _config), do: {[], %{}, []}

  defp admit(candidates, config) do
    case Keyword.get(config, :admit, :dns) do
      :always -> {candidates, %{}, []}
      _dns -> admit_by_dns(candidates, config)
    end
  end

  defp admit_by_dns(candidates, config) do
    resolver = Keyword.get(config, :resolver, Brando.Tenant.ServedHosts.DNS)
    own = own_addresses(config, resolver)

    Enum.reduce(lookup_all(candidates, resolver, config), {[], %{}, own}, fn
      {host, {:ok, [_ | _] = addresses}}, {admitted, waiting, own} ->
        addresses = normalize_addresses(addresses)

        if own != [] and Enum.all?(addresses, &(&1 in own)) do
          {[host | admitted], waiting, own}
        else
          {admitted, Map.put(waiting, host, {:waiting, Enum.map(addresses, &format_address/1)}), own}
        end

      {host, _not_found}, {admitted, waiting, own} ->
        {admitted, Map.put(waiting, host, :unresolved), own}
    end)
  end

  # Under a task supervisor, unlinked: a lookup that raises, exits, throws,
  # dies of a link or times out fails for its host and nothing else. Without
  # the supervisor every lookup fails: the stream would exit through a process
  # linked to this one, which no `catch` here sees.
  defp lookup_all(hosts, resolver, config) do
    case Process.whereis(Brando.Tenant.ServedHosts.TaskSupervisor) do
      nil -> Enum.map(hosts, &{&1, {:error, :noproc}})
      supervisor -> lookup_all(supervisor, hosts, resolver, config)
    end
  end

  defp lookup_all(supervisor, hosts, resolver, config) do
    supervisor
    |> Task.Supervisor.async_stream_nolink(hosts, &lookup(resolver, &1),
      max_concurrency: 8,
      timeout: Keyword.get(config, :lookup_timeout, @lookup_timeout),
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.zip_with(hosts, fn
      {:ok, result}, host -> {host, result}
      {:exit, reason}, host -> {host, {:error, reason}}
    end)
  end

  defp lookup(resolver, host) do
    resolver.lookup(host)
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  # The configured addresses, or what the endpoint's host resolves to now
  defp own_addresses(config, resolver) do
    case Keyword.get(config, :addresses) do
      addresses when is_list(addresses) -> addresses |> Enum.flat_map(&parse_address/1) |> normalize_addresses()
      nil -> endpoint_addresses(endpoint_host(), resolver, config)
    end
  end

  defp endpoint_addresses(nil, _resolver, _config), do: []

  defp endpoint_addresses(host, resolver, config) do
    with [] <- parse_address(host),
         [{^host, {:ok, addresses}}] <- lookup_all([host], resolver, config) do
      normalize_addresses(addresses)
    else
      [{^host, _failed}] -> []
      [address] -> [address]
    end
  end

  defp endpoint_host do
    Brando.endpoint().host()
  rescue
    _ ->
      endpoint = Brando.endpoint()
      config = Application.get_env(Application.get_application(endpoint) || Brando.config(:otp_app), endpoint, [])
      config[:url][:host]
  end

  defp parse_address(address) when is_binary(address) do
    case :inet.parse_strict_address(String.to_charlist(String.trim(address))) do
      {:ok, address} -> [unmap(address)]
      {:error, _reason} -> []
    end
  end

  defp parse_address({_, _, _, _} = address), do: [address]
  defp parse_address({_, _, _, _, _, _, _, _} = address), do: [unmap(address)]
  defp parse_address(_address), do: []

  # Sorted and unique wherever kept or compared: round-robin records answer
  # in turn, and must not change a status from one check to the next
  defp normalize_addresses(addresses), do: addresses |> Enum.map(&unmap/1) |> Enum.sort() |> Enum.uniq()

  defp unmap({0, 0, 0, 0, 0, 0xFFFF, high, low}), do: {div(high, 256), rem(high, 256), div(low, 256), rem(low, 256)}
  defp unmap(address), do: address

  defp format_address(address), do: address |> :inet.ntoa() |> to_string()

  # The file as it is on disk (nil when missing) and the hosts it lists
  defp read_file(file) do
    case File.read(file) do
      {:ok, content} ->
        listed = content |> String.split("\n") |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
        {:ok, content, listed}

      {:error, :enoent} ->
        {:ok, nil, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Rewritten only when the content changes: through a temporary file in the
  # same directory, renamed over the old one, so a reader never sees half
  defp write(file, existing, hosts) do
    # Each line checked on its own, whatever produced the list
    content = hosts |> Enum.filter(&servable?/1) |> Enum.map_join(&[&1, "\n"])

    if content == existing do
      {true, nil}
    else
      replace(file, content)
    end
  end

  # A random name created exclusively, removed when the write or the rename
  # fails. Temporary files a crash left behind are removed first.
  defp replace(file, content) do
    dir = Path.dirname(file)
    prefix = ".#{Path.basename(file)}."
    remove_leftovers(dir, prefix)
    temporary = Path.join(dir, prefix <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower) <> ".tmp")

    case File.open(temporary, [:write, :exclusive, :binary]) do
      {:ok, io} ->
        # On disk before the rename, or a crash could leave the new name empty
        written = with :ok <- :file.write(io, content), do: :file.sync(io)
        closed = File.close(io)

        with :ok <- written,
             :ok <- closed,
             :ok <- File.rename(temporary, file) do
          {true, nil}
        else
          {:error, reason} ->
            File.rm(temporary)
            {false, "#{file}: #{:file.format_error(reason)}"}
        end

      {:error, reason} ->
        {false, "#{file}: #{:file.format_error(reason)}"}
    end
  end

  # Only ones a minute old: during a blue/green switch another node may share
  # the path and be between its write and its rename
  defp remove_leftovers(dir, prefix) do
    case File.ls(dir) do
      {:ok, names} ->
        for name <- names,
            String.starts_with?(name, prefix) and String.ends_with?(name, ".tmp") and
              byte_size(name) > byte_size(prefix) + 4,
            path = Path.join(dir, name),
            stale?(path),
            do: File.rm(path)

      {:error, _reason} ->
        :ok
    end
  end

  defp stale?(path) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} -> System.os_time(:second) - mtime >= @leftover_age
      {:error, _reason} -> false
    end
  end

  # Logged once per failure: when it starts or changes, and when it clears
  defp report(%{error: same} = state, _file, same), do: state

  defp report(state, file, nil) do
    Logger.info("[Brando.Tenant.ServedHosts] Wrote #{file} again")
    %{state | error: nil}
  end

  defp report(state, _file, error) do
    Logger.error(
      "[Brando.Tenant.ServedHosts] Could not update the served hosts file, trying again in a minute: " <> error
    )

    %{state | error: error}
  end

  defp publish(status) do
    unless status == status() do
      :persistent_term.put(@status_key, status)
      broadcast(status)
    end
  end

  defp broadcast(status) do
    # Each node keeps its own file, so its status is its own
    Phoenix.PubSub.local_broadcast(Brando.pubsub(), @topic, {:served_hosts, status})
  rescue
    # No PubSub registry under that name
    ArgumentError -> :ok
  end

  defp empty_status, do: %{file: nil, hosts: %{}, addresses: [], error: nil}

  defp config, do: Application.get_env(:brando, __MODULE__, [])

  defp configured_file?(file), do: is_binary(file) and String.trim(file) != ""
end
