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

  Read when each check runs, so a release sets it in `config/runtime.exs`,
  and again as each answer or write comes back: with the file unset, the
  work under way is dropped and nothing more is written or broadcast; with
  another file, it is dropped and a check of the new file starts.

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

  The process never waits for DNS or the file. A registry write returns once
  every host it bound has a state, `:checking` for one never looked up; the
  check runs after that, and neither it nor a slow disk holds up the next
  registry write. The file is read, merged and written by a task of its own,
  one at a time: a write asked for while one runs follows it once, with what
  is known then. A check's lookups start when its write has read the file,
  for the bound hosts neither in it nor admitted. Each host looked up gets a
  task of its own, at most eight at a time while the rest queue, and its
  lookup timeout starts when its lookup does. A host looked up again, or
  queued, keeps its last state meanwhile. Each answer is kept as it arrives,
  and a host that answered is not looked up again before a write has used
  its answer; the file is written and the status published once no lookup
  of its check is left, or within a fifth of a second while some are
  (`:flush_interval`, in milliseconds, which tests change), so many answers
  cost one write and a single host's result comes as soon as it answers. A
  host is `:served` once the write that put it in the file has succeeded.
  The file is read just before each write, then the bindings, and every
  bound host another node wrote there stays. When that read fails, the file is left as
  it is and the error reported, while the hosts' states still follow the
  registry and their lookups.

  Without `:addresses`, this server's addresses are what the endpoint's host
  resolves to, looked up on their own once per check that looks a host up.
  A failed lookup of them keeps the last ones found, for an hour after they
  were found (`:addresses_max_age`, in milliseconds); after that it forgets
  them, and no host is admitted until a lookup of them answers again.

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
  that raises, exits or throws, fails for that host; so does one whose task
  cannot be stopped at its timeout (a resolver blocking in a NIF), half a
  second later, and that task is left to its supervisor. A `:lookup_timeout`,
  `:retry_interval`, `:recheck_interval`, `:flush_interval` or
  `:addresses_max_age` that is not a positive integer counts as unset.
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
  # How long after its timeout a lookup's task may still answer before it
  # counts as failed here
  @lookup_grace 500
  @call_timeout :timer.seconds(5)
  # Lookups running at once; OTP's native resolver has four workers
  @max_lookups 8
  # How long answers of a check still running gather before they are written
  @flush_interval 200
  # How long this server's looked-up addresses are trusted while their
  # lookup keeps failing
  @addresses_max_age :timer.hours(1)
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
    # `lookups`: each lookup under way, by its task's reference, with its batch
    # and the timer of its deadline.
    # `queue`: lookups waiting for one of the `@max_lookups` slots.
    # `batch`: the number of the last check that queued lookups.
    # `results`: what host lookups answered, by host, until admitted or
    # looked up again. `fresh`: the hosts whose answer no write has decided
    # on yet, which no check looks up again.
    # `own`: this server's addresses as last looked up, with the name and
    # when (monotonic milliseconds).
    # `writing`: the reference of the write under way, `write_job` what it was
    # given. `write_requested`, `check_requested`: a write, or a check (a write
    # whose result queues lookups), asked for and not started yet.
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
      fresh: MapSet.new(),
      own: nil,
      writing: nil,
      write_job: nil,
      write_requested: false,
      check_requested: false,
      waiters: []
    }

    # A restart after boot finds the cache warmed and hears no warm for it
    if enabled?() and Cache.warmed?(), do: {:ok, state, {:continue, :check}}, else: {:ok, state}
  end

  @impl true
  def handle_continue(:check, state), do: {:noreply, run(state)}

  @impl true
  # Quick, and nothing the file or DNS does can slow it: every write to the
  # registry waits for this reply, and the check after it only starts tasks
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
    state = %{state | flush_timer: nil, flush: nil}

    case current(state) do
      {:ok, state} -> {:noreply, state |> flush() |> settle()}
      {:stopped, state} -> {:noreply, settle(state)}
    end
  end

  def handle_info({ref, result}, %{writing: ref} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, written(state, result)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{writing: ref} = state) do
    {:noreply, written(state, write_failed(state.write_job, "the write stopped: #{inspect(reason)}"))}
  end

  def handle_info({ref, result}, %{lookups: lookups} = state) when is_map_key(lookups, ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, answered(state, ref, result)}
  end

  # The task did not answer by its own timeout, as when the lookup cannot be
  # killed: the host's lookup fails, and the task is left to its supervisor
  def handle_info({:lookup_deadline, ref}, %{lookups: lookups} = state) when is_map_key(lookups, ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, answered(state, ref, {:error, :timeout})}
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
    {{target, batch, deadline}, lookups} = Map.pop!(state.lookups, ref)
    Process.cancel_timer(deadline)

    case current(%{state | lookups: lookups}) do
      {:ok, state} ->
        state = state |> record(target, result) |> pump()
        state = if batch_done?(state, batch), do: flush(state), else: flush_soon(state)
        settle(state)

      {:stopped, state} ->
        settle(state)
    end
  end

  # The configuration as it is now, before anything goes on with the work
  # under way: turned off, or a new file, drops it all, and a new file gets a
  # check of its own
  defp current(%{settings: nil} = state), do: {:stopped, drop(state)}

  defp current(%{settings: %{file: file}} = state) do
    case settings() do
      {:ok, %{file: ^file} = settings} -> {:ok, %{state | settings: settings}}
      {:ok, _new_file} -> {:stopped, state |> drop() |> run()}
      :off -> {:stopped, %{drop(state) | error: nil}}
      {:error, error} -> {:stopped, state |> drop() |> failed(error)}
    end
  rescue
    exception -> {:stopped, state |> drop() |> failed(Exception.message(exception))}
  end

  # Lookups under way are left to their tasks, which stop at their timeout,
  # and a write under way to its own check of the configuration
  defp drop(state) do
    for {ref, {_target, _batch, deadline}} <- state.lookups do
      Process.demonitor(ref, [:flush])
      Process.cancel_timer(deadline)
    end

    %{
      cancel_flush(state)
      | settings: nil,
        lookups: %{},
        queue: :queue.new(),
        results: %{},
        fresh: MapSet.new(),
        admitted: MapSet.new(),
        write_requested: false,
        check_requested: false
    }
  end

  defp record(state, {:host, host}, {:ok, [_ | _] = addresses}),
    do: put_result(state, host, {:ok, normalize_addresses(addresses)})

  defp record(state, {:host, host}, _failed), do: put_result(state, host, :unresolved)

  defp record(state, {:own, name}, {:ok, [_ | _] = addresses}),
    do: %{state | own: {name, normalize_addresses(addresses), System.monotonic_time(:millisecond)}}

  # A failed lookup of this server's addresses keeps the last ones it found,
  # for `:addresses_max_age` after they were found
  defp record(%{own: {_own_name, _addresses, found}} = state, {:own, _name}, _failed) do
    if System.monotonic_time(:millisecond) - found >= state.settings.addresses_max_age,
      do: %{state | own: nil},
      else: state
  end

  defp record(state, {:own, _name}, _failed), do: state

  defp put_result(state, host, result),
    do: %{state | results: Map.put(state.results, host, result), fresh: MapSet.put(state.fresh, host)}

  defp batch_done?(state, batch) do
    not Enum.any?(state.lookups, &match?({_ref, {_target, ^batch, _deadline}}, &1)) and
      not :queue.any(&match?({_target, ^batch}, &1), state.queue)
  end

  defp flush_soon(%{flush_timer: nil} = state) do
    flush = make_ref()
    %{state | flush_timer: Process.send_after(self(), {:flush, flush}, state.settings.flush_interval), flush: flush}
  end

  defp flush_soon(state), do: state

  defp cancel_flush(%{flush_timer: nil} = state), do: state

  defp cancel_flush(state) do
    Process.cancel_timer(state.flush_timer)
    %{state | flush_timer: nil, flush: nil}
  end

  defp wait(state, from), do: settle(%{state | waiters: [from | state.waiters]})

  # Replies to the waiters once no lookup runs or waits and no write is under
  # way or asked for
  defp settle(%{waiters: [_ | _] = waiters} = state) do
    state = if state.flush_timer && idle_lookups?(state), do: flush(state), else: state

    if idle_lookups?(state) and idle_writer?(state) do
      status = status()
      Enum.each(waiters, &GenServer.reply(&1, status))
      %{state | waiters: []}
    else
      state
    end
  end

  defp settle(state), do: state

  defp idle_lookups?(state), do: map_size(state.lookups) == 0 and :queue.is_empty(state.queue)

  defp idle_writer?(state), do: is_nil(state.writing) and not state.write_requested and not state.check_requested

  defp run(state) do
    state = cancel_tick(state)

    case settings() do
      :off ->
        %{drop(state) | error: nil}

      {:error, error} ->
        failed(%{state | settings: nil}, error)

      {:ok, settings} ->
        request_write(%{state | settings: settings, check_requested: true})
    end
  rescue
    # A bad config or a broken cache must not restart this process until its
    # supervisor, and the application with it, gives up. A lookup started
    # before the failure stops at its own timeout.
    exception -> failed(state, Exception.message(exception))
  end

  defp failed(state, error) do
    state = report(%{state | results: %{}, fresh: MapSet.new()}, nil, error)
    publish(%{status() | error: error})
    schedule(state, true)
  end

  # The answers so far go to the file now
  defp flush(state), do: state |> cancel_flush() |> request_write()

  defp request_write(state), do: maybe_start_write(%{state | write_requested: true})

  # One write at a time, in a task: a write asked for while one runs starts
  # when it ends, once, with what is known then
  defp maybe_start_write(%{writing: nil, settings: %{}, write_requested: write?, check_requested: check?} = state)
       when write? or check? do
    start_write(state)
  rescue
    exception -> failed(%{state | write_requested: false, check_requested: false}, Exception.message(exception))
  end

  defp maybe_start_write(state), do: state

  # The hosts to keep are worked out here; the task reads the file, keeps
  # every bound host it lists or this process keeps, and replaces it if that
  # changed
  defp start_write(state) do
    state = cancel_flush(state)
    decided = decide_outside(state, servable_bound_hosts())
    admit = for {host, :admit} <- decided, do: host

    job = %{
      file: state.settings.file,
      keep: MapSet.union(state.admitted, MapSet.new(admit)),
      check?: state.check_requested
    }

    # An answer still waiting for this server's addresses stays fresh
    fresh = MapSet.filter(state.fresh, &(decided[&1] == :pending))
    state = %{state | write_requested: false, check_requested: false, write_job: job, fresh: fresh}

    case Process.whereis(Brando.Tenant.ServedHosts.TaskSupervisor) do
      nil ->
        written(%{state | writing: make_ref()}, write_failed(job, "no task supervisor to write it"))

      supervisor ->
        task = Task.Supervisor.async_nolink(supervisor, fn -> write_hosts(job) end)
        %{state | writing: task.ref}
    end
  end

  # In the task: the file read just before the write, and every bound host it
  # lists kept
  defp write_hosts(%{file: file, keep: keep}) do
    run_before_write_hook()
    if Keyword.get(config(), :file) == file, do: read_and_write(file, keep), else: :cancelled
  end

  # The bindings are read after the file: a host bound and admitted by another
  # node while the write waited is then in both, and stays
  defp read_and_write(file, keep) do
    read = read_file(file)
    listed = MapSet.new(listed(read))
    hosts = Enum.filter(servable_bound_hosts(), &(MapSet.member?(listed, &1) or MapSet.member?(keep, &1)))

    {written?, error} =
      case read do
        {:ok, existing, _listed} -> write(file, existing, hosts)
        {:error, reason} -> {false, "#{file}: #{:file.format_error(reason)}"}
      end

    %{read?: match?({:ok, _, _}, read), listed: listed, hosts: hosts, written?: written?, error: error}
  end

  # Tests hold a write here
  defp run_before_write_hook do
    case Keyword.get(config(), :before_write) do
      hook when is_function(hook, 0) -> hook.()
      _none -> :ok
    end
  end

  # The file left as it is: what was meant to be in it is still admitted
  defp write_failed(%{file: file, keep: keep}, reason) do
    %{
      read?: false,
      listed: MapSet.new(),
      hosts: Enum.filter(servable_bound_hosts(), &MapSet.member?(keep, &1)),
      written?: false,
      error: "#{file}: #{reason}"
    }
  end

  defp written(state, result) do
    job = state.write_job
    state = %{state | writing: nil, write_job: nil}

    case current(state) do
      {:ok, state} when result == :cancelled -> state |> request_write() |> settle()
      {:ok, state} -> state |> apply_write(job, result) |> maybe_start_write() |> settle()
      {:stopped, state} -> settle(state)
    end
  end

  # What a write found, in the state and the status: the hosts in the file
  # now, the others' last answers, and lookups for any host a check found
  # neither in the file nor admitted. A host admitted since the write started
  # waits for the next one, which follows at once.
  defp apply_write(state, job, result) do
    %{file: file} = state.settings
    {bound, invalid} = Enum.split_with(Cache.bound_hosts(), &servable?/1)
    admitted = MapSet.new(result.hosts)
    # Answers are kept for bound hosts not in the file only
    outside = bound |> MapSet.new() |> MapSet.difference(admitted)

    state = %{
      report(state, file, result.error)
      | admitted: admitted,
        results: Map.take(state.results, MapSet.to_list(outside)),
        fresh: MapSet.intersection(state.fresh, outside)
    }

    state = if job.check?, do: look_up_missing(state), else: state
    decided = decide_outside(state, bound)
    hosts = host_statuses(state, result, bound, decided) |> Map.merge(Map.new(invalid, &{&1, :invalid}))
    publish(%{file: file, hosts: hosts, addresses: format_addresses(own_addresses(state)), error: result.error})
    state = if Enum.any?(decided, &match?({_host, :admit}, &1)), do: %{state | write_requested: true}, else: state
    schedule(state, retry?(state, decided) or result.error != nil)
  end

  # What each bound host not in the file gets from its last answer
  defp decide_outside(state, bound) do
    pending = pending_hosts(state)
    for host <- bound, not MapSet.member?(state.admitted, host), into: %{}, do: {host, decide(state, host, pending)}
  end

  # A host admitted but not written yet, or with no answer yet, keeps its
  # last state
  defp host_statuses(state, result, bound, decided) do
    previous = status().hosts

    in_file =
      for host <- bound, MapSet.member?(state.admitted, host), into: %{}, do: {host, file_state(host, result, previous)}

    Map.merge(
      in_file,
      Map.new(decided, fn
        {host, decision} when decision in [:admit, :pending] -> {host, pending_state(host, previous)}
        {host, host_state} -> {host, host_state}
      end)
    )
  end

  # Soon while a host waits for its DNS, or no lookup runs for a host that
  # has no answer yet: it waits for the next check
  defp retry?(state, decided) do
    pending = pending_hosts(state)

    Enum.any?(decided, fn
      {_host, :admit} -> false
      {host, :pending} -> not MapSet.member?(pending, host)
      {_host, _waiting_or_unresolved} -> true
    end)
  end

  # Every bound host neither in the file nor admitted, unless a lookup of it
  # runs or waits already, or answered and no write has decided on it yet
  defp look_up_missing(%{settings: %{admit: :dns}} = state) do
    candidates =
      Cache.bound_hosts()
      |> Enum.filter(&servable?/1)
      |> Enum.reject(&(MapSet.member?(state.admitted, &1) or MapSet.member?(state.fresh, &1)))

    look_up(state, candidates)
  end

  defp look_up_missing(state), do: state

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
    Enum.any?(state.lookups, &match?({_ref, {{:own, _name}, _batch, _deadline}}, &1)) or
      :queue.any(&match?({{:own, _name}, _batch}, &1), state.queue)
  end

  defp pending_hosts(state) do
    running = for {_ref, {{:host, host}, _batch, _deadline}} <- state.lookups, do: host
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
  # nothing else. The task stops itself at the timeout; when it has not
  # answered shortly after, the lookup fails here all the same, so a task that
  # never answers holds no slot. Without the supervisor every lookup fails at
  # once.
  defp start_lookup(state, {target, batch}) do
    case Process.whereis(Brando.Tenant.ServedHosts.TaskSupervisor) do
      nil ->
        record(state, target, {:error, :no_supervisor})

      supervisor ->
        %{resolver: resolver, lookup_timeout: timeout} = state.settings
        name = target_name(target)
        task = Task.Supervisor.async_nolink(supervisor, fn -> timed_lookup(resolver, name, timeout) end)
        deadline = Process.send_after(self(), {:lookup_deadline, task.ref}, timeout + @lookup_grace)
        %{state | lookups: Map.put(state.lookups, task.ref, {target, batch, deadline})}
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

  defp listed({:ok, _existing, listed}), do: listed
  defp listed({:error, _reason}), do: []

  # In the file now, or in it before a read failed
  defp file_state(host, result, previous) do
    cond do
      result.written? or MapSet.member?(result.listed, host) -> :served
      not result.read? and previous[host] == :served -> :served
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
      {{:lookup, name}, {name, addresses, _found}} -> addresses
      {{:lookup, _name}, _none} -> []
    end
  end

  # Known when configured, looked up before, or when no lookup of them runs
  defp own_known?(state) do
    case {state.settings.own_source, state.own} do
      {{:fixed, _addresses}, _own} -> true
      {{:lookup, name}, {name, _addresses, _found}} -> true
      {{:lookup, _name}, _none} -> not own_pending?(state)
    end
  end

  # A host looked up again keeps the state its last lookup gave it meanwhile;
  # a host never looked up is checking
  defp pending_state(host, previous) do
    case Map.get(previous, host) do
      {:waiting, _addresses} = waiting -> waiting
      :unresolved -> :unresolved
      _none -> :checking
    end
  end

  defp servable_bound_hosts, do: Enum.filter(Cache.bound_hosts(), &servable?/1)

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
      recheck_interval: milliseconds(config, :recheck_interval, @recheck_interval),
      flush_interval: milliseconds(config, :flush_interval, @flush_interval),
      addresses_max_age: milliseconds(config, :addresses_max_age, @addresses_max_age)
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
