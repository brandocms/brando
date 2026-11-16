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
  at most eight at a time while the rest queue, and its lookup timeout
  starts when its lookup does. A registry write returns once every host it
  bound has a state, `:checking` for one never looked up; the check itself
  (the file, the lookups) runs after that. A host looked up again, or
  queued, keeps its last state meanwhile. Each answer is kept as it arrives;
  the file is written and the status published once no lookup of its check
  is left, or within a fifth of a second while some are, so many answers
  cost one write and a single host's result comes as soon as it answers.
  The file is read just before each write, and every bound host another
  node wrote there stays. When that read fails, the file is left as it is
  and the error reported, while the hosts' states still follow the registry
  and their lookups.

  Without `:addresses`, this server's addresses are what the endpoint's host
  resolves to, looked up on their own once per check that looks a host up.
  A failed lookup of them keeps the last ones found.

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
  that raises, exits or throws, fails for that host. A `:lookup_timeout`,
  `:retry_interval` or `:recheck_interval` that is not a positive integer
  counts as unset.
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
  # Lookups running at once; OTP's native resolver has four workers
  @max_lookups 8
  # How long answers of a check still running gather before they are written
  @flush_interval 200
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
  once every host the refresh bound has a state in `status/0`: `:checking`
  until its lookup answers. The check itself (the file, the lookups) runs
  after the reply. Does nothing when no file is configured, nor when the
  process is not running.
  """
  @spec registry_changed() :: :ok
  def registry_changed do
    if enabled?() do
      try do
        GenServer.call(__MODULE__, :registry_changed, @call_timeout)
      catch
        # Not started yet (a warm at boot), or busy: the check runs when the
        # process gets to the message, or on its own when it starts
        :exit, _reason -> :ok
      end
    end

    :ok
  end

  @doc "Checks now and returns the status once every lookup has answered. For tests."
  @spec check() :: status()
  def check, do: GenServer.call(__MODULE__, :check, :timer.minutes(1))

  @doc "Returns the status once every lookup under way or queued has answered, without checking. For tests."
  @spec settled() :: status()
  def settled, do: GenServer.call(__MODULE__, :settled, :timer.minutes(1))

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  # Server

  @impl true
  def init(nil) do
    # `admitted`: the hosts this process saw in the file or admitted itself, kept
    # while bound. In memory only: a new process starts from the file alone.
    # `settings`: the configuration the last check read, nil when off.
    # `tick`, `flush`: the references the pending timers' messages carry.
    # `lookups`: each lookup under way, by its task's reference, with its batch.
    # `queue`: lookups waiting for one of the `@max_lookups` slots.
    # `batch`: the number of the last check that queued lookups.
    # `results`: what host lookups answered, by host, until admitted or
    # looked up again.
    # `own`: this server's addresses as last looked up, with the name.
    # `waiters`: callers of `check/0` and `settled/0` waiting for the lookups.
    state = %{
      timer: nil,
      tick: nil,
      flush_timer: nil,
      flush: nil,
      error: nil,
      settings: nil,
      admitted: MapSet.new(),
      lookups: %{},
      queue: :queue.new(),
      batch: 0,
      results: %{},
      own: nil,
      waiters: []
    }

    # A restart after boot finds the cache warmed and hears no warm for it
    if enabled?() and Cache.warmed?(), do: {:ok, state, {:continue, :check}}, else: {:ok, state}
  end

  @impl true
  def handle_continue(:check, state), do: {:noreply, run(state)}

  @impl true
  # Quick, and nothing the file or DNS does can slow it: every write to the
  # registry waits for this reply
  def handle_call(:registry_changed, _from, state) do
    if enabled?() do
      mark_bound()
      {:reply, :ok, state, {:continue, :check}}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call(:check, from, state), do: {:noreply, state |> run() |> wait(from)}

  def handle_call(:settled, from, state), do: {:noreply, wait(state, from)}

  @impl true
  # A cold cache binds no host, and a check then would empty the file. A tick
  # of a timer cancelled after it fired is not the current one, and ignored.
  def handle_info({:tick, tick}, %{tick: tick} = state) do
    state = %{state | timer: nil, tick: nil}
    if Cache.warmed?(), do: {:noreply, run(state)}, else: {:noreply, state}
  end

  def handle_info({:flush, flush}, %{flush: flush} = state) do
    {:noreply, flush(%{state | flush_timer: nil, flush: nil})}
  end

  def handle_info({ref, result}, %{lookups: lookups} = state) when is_map_key(lookups, ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, answered(state, ref, result)}
  end

  # The task died: of a link, say, which no `catch` inside it sees
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{lookups: lookups} = state)
      when is_map_key(lookups, ref),
      do: {:noreply, answered(state, ref, {:error, reason})}

  def handle_info(_message, state), do: {:noreply, state}

  # Every bound host gets a state at once: the one it has, or `:checking`
  defp mark_bound do
    {bound, invalid} = Enum.split_with(Cache.bound_hosts(), &servable?/1)
    previous = status()

    hosts =
      bound
      |> Map.new(&{&1, Map.get(previous.hosts, &1, :checking)})
      |> Map.merge(Map.new(invalid, &{&1, :invalid}))

    publish(%{previous | file: config()[:file], hosts: hosts})
  rescue
    # The check after the reply reports what is wrong
    _exception -> :ok
  end

  # A lookup answered, failed or timed out. Its answer is kept at once; the
  # file, the status and the broadcast follow when no lookup of its check is
  # left, or shortly while some are, so that many answers cost one write.
  defp answered(state, ref, result) do
    {{target, batch}, lookups} = Map.pop!(state.lookups, ref)
    state = %{state | lookups: lookups} |> record(target, result) |> pump()
    state = if batch_done?(state, batch), do: flush(state), else: flush_soon(state)
    settle(state)
  end

  defp record(state, {:host, host}, {:ok, [_ | _] = addresses}),
    do: %{state | results: Map.put(state.results, host, {:ok, normalize_addresses(addresses)})}

  defp record(state, {:host, host}, _failed), do: %{state | results: Map.put(state.results, host, :unresolved)}
  defp record(state, {:own, name}, {:ok, [_ | _] = addresses}), do: %{state | own: {name, normalize_addresses(addresses)}}
  # A failed lookup of this server's addresses keeps the last ones it found
  defp record(state, {:own, _name}, _failed), do: state

  defp batch_done?(state, batch) do
    not Enum.any?(state.lookups, &match?({_ref, {_target, ^batch}}, &1)) and
      not :queue.any(&match?({_target, ^batch}, &1), state.queue)
  end

  defp flush_soon(%{flush_timer: nil} = state) do
    flush = make_ref()
    %{state | flush_timer: Process.send_after(self(), {:flush, flush}, @flush_interval), flush: flush}
  end

  defp flush_soon(state), do: state

  defp cancel_flush(%{flush_timer: nil} = state), do: state

  defp cancel_flush(state) do
    Process.cancel_timer(state.flush_timer)
    %{state | flush_timer: nil, flush: nil}
  end

  defp wait(state, from), do: settle(%{state | waiters: [from | state.waiters]})

  defp settle(%{waiters: [_ | _] = waiters} = state) do
    if map_size(state.lookups) == 0 and :queue.is_empty(state.queue) do
      state = if state.flush_timer, do: flush(state), else: state
      status = status()
      Enum.each(waiters, &GenServer.reply(&1, status))
      %{state | waiters: []}
    else
      state
    end
  end

  defp settle(state), do: state

  defp run(state) do
    state = cancel_tick(state)

    case settings() do
      :off ->
        %{state | error: nil, results: %{}, settings: nil}

      {:error, error} ->
        failed(%{state | settings: nil}, error)

      {:ok, settings} ->
        check(%{state | settings: settings})
    end
  rescue
    # A bad config or a broken cache must not restart this process until its
    # supervisor, and the application with it, gives up. A lookup started
    # before the failure stops at its own timeout.
    exception -> failed(state, Exception.message(exception))
  end

  defp failed(state, error) do
    state = report(%{state | results: %{}}, nil, error)
    publish(%{status() | error: error})
    schedule(state, true)
  end

  # Reads the file, queues a lookup for each bound host not in it and not
  # already being looked up, and writes what it knows now. A host looked up
  # again keeps the state its last lookup gave it meanwhile.
  defp check(state) do
    %{file: file, admit: admit} = state.settings
    read = read_file(file)
    known = MapSet.union(MapSet.new(listed(read)), state.admitted)

    candidates =
      Cache.bound_hosts()
      |> Enum.filter(&servable?/1)
      |> Enum.reject(&MapSet.member?(known, &1))

    state = if admit == :dns, do: look_up(state, candidates), else: state
    apply_results(state, read)
  end

  defp flush(state) do
    state = cancel_flush(state)

    case state.settings do
      nil -> state
      %{file: file} -> apply_results(state, read_file(file))
    end
  rescue
    exception -> failed(state, Exception.message(exception))
  end

  defp look_up(state, candidates) do
    pending = pending_hosts(state)

    case Enum.reject(candidates, &MapSet.member?(pending, &1)) do
      [] ->
        state

      hosts ->
        batch = state.batch + 1
        state = queue_own(%{state | batch: batch, results: Map.drop(state.results, hosts)}, batch)
        queue = Enum.reduce(hosts, state.queue, &:queue.in({{:host, &1}, batch}, &2))
        pump(%{state | queue: queue})
    end
  end

  # This server's addresses, when they are a name to look up: once per check
  # that looks a host up, ahead of the hosts
  defp queue_own(%{settings: %{own_source: {:lookup, name}}} = state, batch) do
    if own_pending?(state),
      do: state,
      else: %{state | queue: :queue.in_r({{:own, name}, batch}, state.queue)}
  end

  defp queue_own(state, _batch), do: state

  defp own_pending?(state) do
    Enum.any?(state.lookups, &match?({_ref, {{:own, _name}, _batch}}, &1)) or
      :queue.any(&match?({{:own, _name}, _batch}, &1), state.queue)
  end

  defp pending_hosts(state) do
    running = for {_ref, {{:host, host}, _batch}} <- state.lookups, do: host
    queued = for {{:host, host}, _batch} <- :queue.to_list(state.queue), do: host
    MapSet.new(running ++ queued)
  end

  # Starts queued lookups while fewer than `@max_lookups` run: the system
  # resolver answers a few at a time, and a lookup's timeout starts with it
  defp pump(%{settings: nil} = state), do: %{state | queue: :queue.new()}

  defp pump(state) do
    with true <- map_size(state.lookups) < @max_lookups,
         {{:value, item}, queue} <- :queue.out(state.queue) do
      pump(start_lookup(%{state | queue: queue}, item))
    else
      _full_or_empty -> state
    end
  end

  # One task per lookup, under a task supervisor, unlinked: a lookup that
  # raises, exits, throws, dies of a link or times out fails for its host and
  # nothing else. The task stops itself at the timeout, so none outlives it,
  # whatever happens to this process's state. Without the supervisor every
  # lookup fails at once.
  defp start_lookup(state, {target, batch}) do
    case Process.whereis(Brando.Tenant.ServedHosts.TaskSupervisor) do
      nil ->
        record(state, target, {:error, :no_supervisor})

      supervisor ->
        %{resolver: resolver, lookup_timeout: timeout} = state.settings
        name = target_name(target)
        task = Task.Supervisor.async_nolink(supervisor, fn -> timed_lookup(resolver, name, timeout) end)
        %{state | lookups: Map.put(state.lookups, task.ref, {target, batch})}
    end
  end

  defp target_name({_kind, name}), do: name

  defp timed_lookup(resolver, name, timeout) do
    lookup = Task.async(fn -> lookup(resolver, name) end)

    case Task.yield(lookup, timeout) || Task.shutdown(lookup, :brutal_kill) do
      {:ok, result} -> result
      {:exit, reason} -> {:error, reason}
      nil -> {:error, :timeout}
    end
  end

  defp lookup(resolver, host) do
    resolver.lookup(host)
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  # The expensive part, once per check or batch of answers: the file read
  # again, merged and replaced if it changed, the status published. A file
  # that cannot be read is left as it is, and the hosts' states still follow
  # the registry.
  defp apply_results(state, read) do
    %{file: file} = state.settings
    {bound, invalid} = Enum.split_with(Cache.bound_hosts(), &servable?/1)
    listed = MapSet.new(listed(read))
    # Another node sharing the path may have written over a host this one
    # admitted: it goes back in without a lookup
    known = MapSet.union(listed, state.admitted)
    {kept, candidates} = Enum.split_with(bound, &MapSet.member?(known, &1))
    pending = pending_hosts(state)
    decided = Map.new(candidates, &{&1, decide(state, &1, pending)})
    admitted = for {host, :admit} <- decided, do: host
    waiting = for {host, host_state} <- decided, host_state not in [:admit, :pending], into: %{}, do: {host, host_state}
    undecided = for {host, :pending} <- decided, do: host
    hosts = (kept ++ admitted) |> Enum.uniq() |> Enum.sort()

    {written?, error} =
      case read do
        {:ok, existing, _listed} -> write(file, existing, hosts)
        {:error, reason} -> {false, "#{file}: #{:file.format_error(reason)}"}
      end

    previous = status().hosts

    state = %{
      report(state, file, error)
      | admitted: MapSet.new(hosts),
        results: Map.take(state.results, Map.keys(waiting) ++ undecided)
    }

    statuses =
      Map.new(hosts, &{&1, file_state(&1, written?, listed, read, previous)})
      |> Map.merge(waiting)
      |> Map.merge(pending_states(undecided, previous))
      |> Map.merge(Map.new(invalid, &{&1, :invalid}))

    publish(%{file: file, hosts: statuses, addresses: format_addresses(own_addresses(state)), error: error})
    # A host no lookup runs for waits for the next check
    unlooked? = Enum.any?(undecided, &(not MapSet.member?(pending, &1)))
    schedule(state, map_size(waiting) > 0 or unlooked? or error != nil)
  end

  defp listed({:ok, _existing, listed}), do: listed
  defp listed({:error, _reason}), do: []

  # In the file now, or in it before a read failed
  defp file_state(host, written?, listed, read, previous) do
    cond do
      written? or MapSet.member?(listed, host) -> :served
      match?({:error, _}, read) and previous[host] == :served -> :served
      true -> :not_written
    end
  end

  # What a host not in the file gets from its last answer: admitted, waiting,
  # unresolved, or `:pending` while its lookup runs or this server's
  # addresses are not known yet
  defp decide(%{settings: %{admit: :always}}, _host, _pending), do: :admit

  defp decide(state, host, pending) do
    cond do
      MapSet.member?(pending, host) -> :pending
      not Map.has_key?(state.results, host) -> :pending
      state.results[host] == :unresolved -> :unresolved
      own_known?(state) -> classify(elem(state.results[host], 1), own_addresses(state))
      true -> :pending
    end
  end

  defp own_addresses(%{settings: nil}), do: []

  defp own_addresses(state) do
    case {state.settings.own_source, state.own} do
      {{:fixed, addresses}, _own} -> addresses
      {{:lookup, name}, {name, addresses}} -> addresses
      {{:lookup, _name}, _none} -> []
    end
  end

  # Known when configured, looked up before, or when no lookup of them runs
  defp own_known?(state) do
    case {state.settings.own_source, state.own} do
      {{:fixed, _addresses}, _own} -> true
      {{:lookup, name}, {name, _addresses}} -> true
      {{:lookup, _name}, _none} -> not own_pending?(state)
    end
  end

  # A host looked up again keeps the state its last lookup gave it meanwhile;
  # a host never looked up is checking
  defp pending_states(pending, previous) do
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
    state = cancel_tick(state)
    settings = state.settings || %{retry_interval: @retry_interval, recheck_interval: @recheck_interval}
    interval = if retry?, do: settings.retry_interval, else: settings.recheck_interval
    tick = make_ref()
    %{state | timer: Process.send_after(self(), {:tick, tick}, interval), tick: tick}
  end

  defp cancel_tick(%{timer: nil} = state), do: state

  defp cancel_tick(state) do
    Process.cancel_timer(state.timer)
    %{state | timer: nil, tick: nil}
  end

  defp classify(addresses, own) do
    if own != [] and Enum.all?(addresses, &(&1 in own)),
      do: :admit,
      else: {:waiting, format_addresses(addresses)}
  end

  # The configuration, read and checked once per check, before anything
  # starts: `:off` without a file, an error for addresses that are not a list
  defp settings do
    config = config()
    config = if Keyword.keyword?(config), do: config, else: []
    file = Keyword.get(config, :file)
    admit = if Keyword.get(config, :admit) == :always, do: :always, else: :dns

    cond do
      not configured_file?(file) ->
        :off

      admit == :always ->
        {:ok, settings(config, file, admit, {:fixed, []})}

      true ->
        with {:ok, own_source} <- own_source(config), do: {:ok, settings(config, file, admit, own_source)}
    end
  end

  defp settings(config, file, admit, own_source) do
    %{
      file: file,
      admit: admit,
      own_source: own_source,
      resolver: Keyword.get(config, :resolver, Brando.Tenant.ServedHosts.DNS),
      lookup_timeout: milliseconds(config, :lookup_timeout, @lookup_timeout),
      retry_interval: milliseconds(config, :retry_interval, @retry_interval),
      recheck_interval: milliseconds(config, :recheck_interval, @recheck_interval)
    }
  end

  # Anything but a positive number of milliseconds falls back to the default
  defp milliseconds(config, key, default) do
    case Keyword.get(config, key) do
      milliseconds when is_integer(milliseconds) and milliseconds > 0 -> milliseconds
      _unset -> default
    end
  end

  # The configured addresses, or the endpoint's host: an address itself, or a
  # name looked up once per check
  defp own_source(config) do
    case Keyword.get(config, :addresses) do
      addresses when is_list(addresses) -> {:ok, {:fixed, normalize_own(addresses)}}
      nil -> {:ok, endpoint_source(endpoint_host())}
      other -> {:error, ":addresses must be a list of IP addresses, not #{inspect(other)}"}
    end
  end

  defp endpoint_source(nil), do: {:fixed, []}

  defp endpoint_source(host) do
    case parse_address(host) do
      [] -> {:lookup, host}
      address -> {:fixed, address}
    end
  end

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
