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

  Every host the registry binds (`Brando.Tenant.Cache.bound_hosts/0`): each
  environment's domain and its redirect hosts, which need a route and a
  certificate for their redirect to be reached. Only a full host name is
  written: valid (`Brando.Environments.Environment.valid_host?/1`), with a
  dot, and not an IP address. A bound host without a dot (`intranet`), an
  address, or a host stored before Brando checked it is still answered on,
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

  A check never waits for DNS. Each host it looks up gets a task of its own,
  and a host never looked up before is `:checking` from the moment the check
  begins: a registry write returns once every host it bound has a state. A
  host looked up again keeps its last state meanwhile. Each answer is checked
  in on its own as it arrives, so a host's result comes within the lookup
  timeout, whatever other lookups or checks are under way. The file is read
  just before it is replaced, and every bound host another node wrote there
  stays; when that read fails, the file is left as it is.

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
  @call_timeout :timer.seconds(5)
  # Seconds
  @leftover_age 60

  @typedoc """
  Where a bound host stands: in the file (`:served`), admitted but the file
  could not be written (`:not_written`), its first lookup under way
  (`:checking`), resolving to addresses that are not all this server's
  (`{:waiting, addresses}`), not resolving, or never written because it is
  not a full host name (`:invalid`).
  """
  @type host_state ::
          :served | :not_written | :checking | {:waiting, [String.t()]} | :unresolved | :invalid

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
  state, this server's addresses as last looked up, and the error writing the
  file, if any. Nothing is looked up here.
  """
  @spec status() :: status()
  def status, do: :persistent_term.get(@status_key, empty_status())

  @doc "The PubSub topic a changed `status/0` is broadcast on, on this node only, as `{:served_hosts, status}`."
  @spec topic() :: String.t()
  def topic, do: @topic

  @doc """
  Asks this node's process to check, after a registry refresh, and returns
  once the check has begun: every host the refresh bound has a state in
  `status/0` by then, `:checking` while its lookup runs. Does nothing when no
  file is configured, nor when the process is not running.
  """
  @spec registry_changed() :: :ok
  def registry_changed do
    if enabled?() do
      try do
        GenServer.call(__MODULE__, :registry_changed, @call_timeout)
      catch
        # Not started yet (a warm at boot), or busy writing: the check runs
        # when the process gets to the message, or on its own when it starts
        :exit, _reason -> :ok
      end
    end

    :ok
  end

  @doc "Checks now and returns the status once every lookup has answered. For tests."
  @spec check() :: status()
  def check, do: GenServer.call(__MODULE__, :check, :timer.minutes(1))

  @doc "Returns the status once every lookup under way has answered, without checking. For tests."
  @spec settled() :: status()
  def settled, do: GenServer.call(__MODULE__, :settled, :timer.minutes(1))

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  # Server

  @impl true
  def init(nil) do
    # `admitted`: the hosts this process saw in the file or admitted itself, kept
    # while bound. In memory only: a new process starts from the file alone.
    # `tick`: the reference the pending timer's message carries.
    # `lookups`: each lookup under way, by its task's reference.
    # `results`: what lookups answered since the last check, by host.
    # `own`: this server's addresses as last looked up.
    # `waiters`: callers of `check/0` and `settled/0` waiting for the lookups.
    state = %{
      timer: nil,
      tick: nil,
      error: nil,
      admitted: MapSet.new(),
      lookups: %{},
      results: %{},
      own: [],
      waiters: []
    }

    # A restart after boot finds the cache warmed and hears no warm for it
    if enabled?() and Cache.warmed?(), do: {:ok, state, {:continue, :check}}, else: {:ok, state}
  end

  @impl true
  def handle_continue(:check, state), do: {:noreply, run(state)}

  @impl true
  def handle_call(:registry_changed, _from, state), do: {:reply, :ok, run(state)}

  def handle_call(:check, from, state), do: {:noreply, state |> run() |> wait(from)}

  def handle_call(:settled, from, state), do: {:noreply, wait(state, from)}

  @impl true
  # A cold cache binds no host, and a check then would empty the file. A tick
  # of a timer cancelled after it fired is not the current one, and ignored.
  def handle_info({:tick, tick}, %{tick: tick} = state) do
    state = %{state | timer: nil, tick: nil}
    if Cache.warmed?(), do: {:noreply, run(state)}, else: {:noreply, state}
  end

  def handle_info({ref, {result, endpoint}}, %{lookups: lookups} = state) when is_map_key(lookups, ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, answered(state, ref, result, endpoint)}
  end

  # The task died: of a link, say, which no `catch` inside it sees
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{lookups: lookups} = state)
      when is_map_key(lookups, ref),
      do: {:noreply, answered(state, ref, {:error, reason}, nil)}

  def handle_info({:lookup_timeout, ref}, %{lookups: lookups} = state) when is_map_key(lookups, ref) do
    {_host, pid, _timer, _source} = Map.fetch!(lookups, ref)
    Process.exit(pid, :kill)
    Process.demonitor(ref, [:flush])
    {:noreply, answered(state, ref, {:error, :timeout}, nil)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # A lookup answered, failed or timed out: its host's result goes into a
  # check at once, so it never waits for another host's lookup
  defp answered(state, ref, result, endpoint) do
    {{host, _pid, timer, source}, lookups} = Map.pop!(state.lookups, ref)
    Process.cancel_timer(timer)
    own = own(source, endpoint)

    %{state | lookups: lookups, results: Map.put(state.results, host, classify(result, own)), own: own}
    |> run(false)
    |> settle()
  end

  defp wait(state, from), do: settle(%{state | waiters: [from | state.waiters]})

  defp settle(%{lookups: lookups, waiters: [_ | _] = waiters} = state) when map_size(lookups) == 0 do
    status = status()
    Enum.each(waiters, &GenServer.reply(&1, status))
    %{state | waiters: []}
  end

  defp settle(state), do: state

  # `look_up?`: whether hosts without an answer are looked up. Not in the
  # check an answer runs, which would look the other waiting hosts up again
  # for every answer.
  defp run(state, look_up? \\ true) do
    if state.timer, do: Process.cancel_timer(state.timer)
    state = %{state | timer: nil, tick: nil}
    config = config()

    if configured_file?(config[:file]) do
      check(state, config, look_up?)
    else
      %{state | error: nil, results: %{}}
    end
  rescue
    # A bad config or a resolver that raises must not restart this process
    # until its supervisor, and the application with it, gives up
    exception ->
      error = Exception.message(exception)
      state = report(%{state | results: %{}}, nil, error)
      publish(%{status() | error: error})
      schedule(state, true)
  end

  # Quick: the lookups it needs run in tasks, and their answers come back as
  # messages, each running a check of its own
  defp check(state, config, look_up?) do
    file = config[:file]

    case read_file(file) do
      {:ok, existing, listed} ->
        {bound, invalid} = Enum.split_with(Cache.bound_hosts(), &servable?/1)
        listed = MapSet.new(listed)
        # Another node sharing the path may have written over a host this one
        # admitted: it goes back in without a lookup
        known = MapSet.union(listed, state.admitted)
        {kept, candidates} = Enum.split_with(bound, &MapSet.member?(known, &1))
        {state, decided, pending} = decide(state, candidates, config, look_up?)
        admitted = for {host, :admit} <- decided, do: host
        waiting = for {host, host_state} <- decided, host_state != :admit, into: %{}, do: {host, host_state}
        bound_set = MapSet.new(bound)

        hosts =
          (kept ++ admitted ++ Enum.filter(listed, &MapSet.member?(bound_set, &1)))
          |> Enum.uniq()
          |> Enum.sort()

        {written?, error} = write(file, existing, hosts)
        state = %{report(state, file, error) | admitted: MapSet.new(hosts)}

        statuses =
          Map.new(hosts, &{&1, if(written? or MapSet.member?(listed, &1), do: :served, else: :not_written)})
          |> Map.merge(waiting)
          |> Map.merge(pending_states(pending))
          |> Map.merge(Map.new(invalid, &{&1, :invalid}))

        publish(%{file: file, hosts: statuses, addresses: format_addresses(state.own), error: error})
        # A host no lookup runs for waits for the next check
        unlooked? = Enum.any?(pending, &(not looking_up?(state, &1)))
        schedule(state, map_size(waiting) > 0 or unlooked? or error != nil)

      {:error, reason} ->
        error = "#{file}: #{:file.format_error(reason)}"
        state = report(%{state | results: %{}}, file, error)
        publish(%{status() | file: file, error: error})
        schedule(state, true)
    end
  end

  # What each host not yet in the file gets: admitted or waiting by a lookup
  # that answered since the last check, or pending while one runs, started
  # here for each host without one. Each answer is used once: a host still
  # waiting is looked up again on the next check.
  defp decide(state, [], config, _look_up?),
    do: {%{state | results: %{}, own: own_without_lookups(state, config)}, [], []}

  defp decide(state, candidates, config, look_up?) do
    case Keyword.get(config, :admit, :dns) do
      :always ->
        {%{state | results: %{}, own: []}, Enum.map(candidates, &{&1, :admit}), []}

      _dns ->
        {answered, unanswered} = Enum.split_with(candidates, &Map.has_key?(state.results, &1))
        decided = Enum.map(answered, &{&1, Map.fetch!(state.results, &1)})
        to_look_up = if look_up?, do: Enum.reject(unanswered, &looking_up?(state, &1)), else: []
        {state, failed} = start_lookups(state, to_look_up, config)
        pending = Enum.reject(unanswered, &Map.has_key?(failed, &1))
        {%{state | results: %{}}, decided ++ Enum.to_list(failed), pending}
    end
  end

  defp looking_up?(state, host), do: Enum.any?(state.lookups, fn {_ref, lookup} -> elem(lookup, 0) == host end)

  # With configured addresses there is nothing to look up for them
  defp own_without_lookups(state, config) do
    case {Keyword.get(config, :admit, :dns), Keyword.get(config, :addresses)} do
      {:always, _addresses} -> []
      {_dns, addresses} when is_list(addresses) -> normalize_own(addresses)
      {_dns, _endpoint} -> state.own
    end
  end

  # A host looked up again keeps the state its last lookup gave it meanwhile;
  # a host never looked up is checking
  defp pending_states(pending) do
    previous = status().hosts

    Map.new(pending, fn host ->
      case Map.get(previous, host) do
        {:waiting, _addresses} = waiting -> {host, waiting}
        :unresolved -> {host, :unresolved}
        _none -> {host, :checking}
      end
    end)
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

  defp classify({:ok, [_ | _] = addresses}, own) do
    addresses = normalize_addresses(addresses)

    if own != [] and Enum.all?(addresses, &(&1 in own)),
      do: :admit,
      else: {:waiting, format_addresses(addresses)}
  end

  defp classify(_not_found, _own), do: :unresolved

  # One task per host, under a task supervisor, unlinked: a lookup that
  # raises, exits, throws, dies of a link or times out fails for its host and
  # nothing else. Without the supervisor every lookup fails at once, returned
  # as answered.
  defp start_lookups(state, [], _config), do: {state, %{}}

  defp start_lookups(state, hosts, config) do
    source = own_source(config)

    case Process.whereis(Brando.Tenant.ServedHosts.TaskSupervisor) do
      nil ->
        {%{state | own: own(source, nil)}, Map.new(hosts, &{&1, :unresolved})}

      supervisor ->
        lookups = Enum.reduce(hosts, state.lookups, &start_lookup(supervisor, &1, &2, source, config))
        {%{state | lookups: lookups}, %{}}
    end
  end

  defp start_lookup(supervisor, host, lookups, source, config) do
    resolver = Keyword.get(config, :resolver, Brando.Tenant.ServedHosts.DNS)
    timeout = Keyword.get(config, :lookup_timeout, @lookup_timeout)
    endpoint = endpoint_to_look_up(source)
    task = Task.Supervisor.async_nolink(supervisor, fn -> lookup_with_endpoint(resolver, host, endpoint) end)
    timer = Process.send_after(self(), {:lookup_timeout, task.ref}, timeout)
    Map.put(lookups, task.ref, {host, task.pid, timer, source})
  end

  defp endpoint_to_look_up({:lookup, host}), do: host
  defp endpoint_to_look_up({:fixed, _addresses}), do: nil

  # The endpoint's host alongside, when this server's addresses are what it
  # resolves to: both within the one timeout. Linked, so it dies with the task.
  defp lookup_with_endpoint(resolver, host, nil), do: {lookup(resolver, host), nil}

  defp lookup_with_endpoint(resolver, host, endpoint) do
    endpoint_lookup = Task.async(fn -> lookup(resolver, endpoint) end)
    result = lookup(resolver, host)
    {result, Task.await(endpoint_lookup, :infinity)}
  end

  defp lookup(resolver, host) do
    resolver.lookup(host)
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  # The configured addresses, or the endpoint's host: an address itself, or a
  # name looked up with each host
  defp own_source(config) do
    case Keyword.get(config, :addresses) do
      addresses when is_list(addresses) ->
        {:fixed, normalize_own(addresses)}

      nil ->
        endpoint_source(endpoint_host())
    end
  end

  defp endpoint_source(nil), do: {:fixed, []}

  defp endpoint_source(host) do
    case parse_address(host) do
      [] -> {:lookup, host}
      address -> {:fixed, address}
    end
  end

  defp own({:fixed, addresses}, _endpoint), do: addresses
  defp own({:lookup, _host}, {:ok, addresses}) when is_list(addresses), do: normalize_addresses(addresses)
  defp own({:lookup, _host}, _failed), do: []

  defp normalize_own(addresses), do: addresses |> Enum.flat_map(&parse_address/1) |> normalize_addresses()

  defp format_addresses(addresses), do: Enum.map(addresses, &format_address/1)

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
