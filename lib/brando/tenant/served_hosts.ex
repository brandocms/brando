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
  another file, it is dropped, with every host remembered as admitted, and a
  check of the new file starts, so a host goes into the new file only once
  it is listed there or admitted again. A write under way then leaves the
  file alone: it checks the configuration, and that its work was not dropped,
  again just before it renames its temporary file over it.

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
  and a host whose DNS still points elsewhere fails that request. A lookup
  that failed, or that could not read one of the two families (its query
  timed out, or the name server failed), admits nothing, whatever the
  family it did read holds: the host is `{:lookup_failed, failures}`, with
  each unread family and why, whatever an earlier lookup found, and is
  looked up again at the next check. A warning is logged when a host enters
  that state and when what failed changes, not at each retry. Brando
  removes a host from the file only once no environment binds it; a failed
  lookup never removes one. The file is the state: nothing is stored in the
  database, and on a new server each host is admitted again when its DNS
  arrives there.

  A lookup that fails the same way at every check is not passing trouble. A
  domain whose name servers fail one family's query every time (an `AAAA`
  query answered with a server failure, say) is never admitted, and a
  certificate authority that looks up both families fails on it too: fix
  the domain's name servers. A server with no name server configured, or
  hosts that resolve only through `/etc/hosts` or the platform's resolver
  configuration, fail every lookup of the default resolver, so every host
  ends there: choose `Brando.Tenant.ServedHosts.SystemResolver` (below), or
  `admit: :always` when the proxy need not wait for DNS.

  ## When

  After every warm of `Brando.Tenant.Cache`, which runs at boot and on every
  node after a registry write, and once a minute (`:retry_interval`, in
  milliseconds) while a bound host waits for its DNS, does not resolve, or
  could not be looked up, or the file could not be written. A host whose
  lookup timed out is looked up again once sooner, five seconds after its
  answer was written (`:timeout_retry_interval`, in milliseconds): a local
  caching resolver can take longer than a family's budget to answer its first
  query for a name, so a name that does not exist would otherwise read as a
  failed lookup for a minute. A timeout again waits for the minute; an
  answer that is no timeout ends it, and a later timeout gets its own quick
  retry. Otherwise every five minutes (`:recheck_interval`): the file is
  read again, as another node sharing the path may have written over it. A
  bound host this process has seen in the file or admitted itself goes back
  in without a lookup; one it has not is admitted again. That memory is the
  process's own, so after a restart a lost host is admitted again too.
  Nothing is looked up while the file holds every bound host. Each node keeps
  its own file.

  A few seconds after each write that succeeded (`:verify_interval`, in
  milliseconds, default five seconds) the file is read again, by the same
  task as a write. A host this process admitted that is still bound and
  missing from the file goes back in without a lookup, and that write is
  verified in turn; with none missing, nothing is written or looked up. A
  later write replaces a verification still pending.

  The process never waits for DNS or the file. A registry write returns once
  every host it bound has a state, `:checking` for one never looked up; the
  check runs after that, and neither it nor a slow disk holds up the next
  registry write. The file is read, merged and written by a task of its own,
  one at a time: a write asked for while one runs follows it once, with what
  is known then. Its rename lands only while the process that started it is
  still the running one, so a write left over from before a restart never
  replaces its successor's file. A check's lookups start when its write has read the file,
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
  resolves to, looked up on their own once per check that looks a host up,
  and by a check that looks no host up while none are known, as the first
  one after a start: the status names them before any host needs a lookup.
  A lookup of them that fails, or that could not read one of the families,
  leaves them unknown for that check and keeps the last ones found, which count for an hour
  after they were found (`:addresses_max_age`, in milliseconds); after that
  no host is admitted, not even while a new lookup of them runs, until one
  answers.

  ## Two installations sharing the file

  Each write reads the file, merges and replaces it, and nothing locks the
  file between two installations. Two installations that share one file path
  at the same moment, as during a blue/green switch, can overwrite each
  other's newest admission. The host is put back by the verification a few
  seconds later when the node that admitted it is still running, and
  otherwise is admitted again at the next check, since its DNS still points
  at the server.

  ## The file

  Sorted, one host per line, each followed by a newline, empty when no host
  is admitted. Written to a temporary file in the same directory, synced to
  disk and renamed over the old one, and only when the content changes. A
  line that is not a bound host is dropped on the next write. A file that
  cannot be written is logged once and retried on the next check.

  Lookups go through `:resolver`, a module implementing
  `Brando.Tenant.ServedHosts.Resolver`, which tests replace. The default,
  `Brando.Tenant.ServedHosts.DNS`, asks the name servers of the system's
  resolver configuration itself, through `:inet_res`, and tells a family
  that timed out from one with no records; it does not read `/etc/hosts` or
  platform-specific resolver configuration. An installation whose hosts
  resolve only through those sets
  `resolver: Brando.Tenant.ServedHosts.SystemResolver`, which asks the
  operating system and counts a family whose lookup failed as one with no
  records. A lookup that does not answer within `:lookup_timeout`
  milliseconds (default ten seconds), or that raises, exits or throws, fails
  for that host, which counts as not looked up; so does one whose task
  cannot be stopped at its timeout (a resolver blocking in a NIF), half a
  second later, and that task is left to its supervisor. A `:lookup_timeout`,
  `:retry_interval`, `:timeout_retry_interval`, `:recheck_interval`, `:flush_interval`,
  `:verify_interval` or `:addresses_max_age` that is not a positive integer
  counts as unset.
  """

  use GenServer

  alias Brando.Environments.Environment
  alias Brando.Tenant.Cache

  require Logger

  @topic "brando:served_hosts"
  @status_key {__MODULE__, :status}
  @retry_interval :timer.minutes(1)
  # How soon a host whose lookup timed out is looked up again, once, before
  # the retry above: a caching resolver's first answer for a name can take
  # longer than a family's budget
  @timeout_retry_interval :timer.seconds(5)
  @recheck_interval :timer.minutes(5)
  # How long after a write the file is read again for a host another
  # installation sharing the path wrote over
  @verify_interval :timer.seconds(5)
  @lookup_timeout :timer.seconds(10)
  # How long after its timeout a lookup's task may still answer before it
  # counts as failed here
  @lookup_grace 500
  @call_timeout :timer.seconds(5)
  @families [:inet, :inet6]
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
  (`{:waiting, addresses}`), not resolving (`:unresolved`), its latest
  lookup failed or left an address family unread
  (`{:lookup_failed, failures}`, each unread family and why, see
  `t:Brando.Tenant.ServedHosts.Resolver.reason/0`), or never written
  because it is not a full host name (`:invalid`).
  """
  @type host_state ::
          :served
          | :not_written
          | :checking
          | {:waiting, [String.t()]}
          | :unresolved
          | {:lookup_failed,
             %{Brando.Tenant.ServedHosts.Resolver.family() => Brando.Tenant.ServedHosts.Resolver.reason()}}
          | :invalid

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
    # `file`: the file what is remembered here belongs to.
    # `tick`, `flush`, `verify`, `timeout_tick`: the references the pending
    # timers' messages carry.
    # `lookups`: each lookup under way, by its task's reference, with its batch
    # and the timer of its deadline.
    # `queue`: lookups waiting for one of the `@max_lookups` slots.
    # `batch`: the number of the last check that queued lookups.
    # `results`: what host lookups answered, by host, until admitted or
    # looked up again. `fresh`: the hosts whose answer no write has decided
    # on yet, which no check looks up again. `timeout_retries`: the hosts
    # whose lookup timed out, `:pending` until their quick retry looks them up
    # again, then `:done` until an answer that is no timeout.
    # `own`: this server's addresses as last looked up, with the name and
    # when (monotonic milliseconds).
    # `writing`: the reference of the write under way, `write_job` what it was
    # given. `generation`: counts the drops of the work under way; a write's
    # result counts only for the file and generation it started with, and
    # `generation_ref` holds it for the write task, which checks it before its
    # rename. `write_requested`, `check_requested`, `verify_requested`: a
    # write, a check (a write whose result queues lookups), or a verification
    # (a write only when an admitted host is missing), asked for and not
    # started yet.
    # `waiters`: callers of `check/0` and `settled/0` waiting for the lookups.
    state = %{
      timer: nil,
      tick: nil,
      flush_timer: nil,
      flush: nil,
      verify_timer: nil,
      verify: nil,
      timeout_timer: nil,
      timeout_tick: nil,
      error: nil,
      settings: nil,
      file: nil,
      admitted: MapSet.new(),
      lookups: %{},
      queue: :queue.new(),
      batch: 0,
      results: %{},
      fresh: MapSet.new(),
      timeout_retries: %{},
      own: nil,
      writing: nil,
      write_job: nil,
      generation: 0,
      generation_ref: :atomics.new(1, []),
      write_requested: false,
      check_requested: false,
      verify_requested: false,
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

  # The file read again a while after a write. A write under way or asked for
  # is verified once it ends.
  def handle_info({:verify, verify}, %{verify: verify} = state) do
    state = %{state | verify_timer: nil, verify: nil}

    case current(state) do
      {:ok, %{writing: nil, write_requested: false, check_requested: false} = state} ->
        {:noreply, state |> Map.put(:verify_requested, true) |> maybe_start_write() |> settle()}

      {_ok_or_stopped, state} ->
        {:noreply, settle(state)}
    end
  end

  def handle_info({:retry_timeouts, ref}, %{timeout_tick: ref} = state) do
    state = %{state | timeout_timer: nil, timeout_tick: nil}

    case current(state) do
      {:ok, state} -> {:noreply, state |> retry_timeouts() |> settle()}
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
      {:ok, %{file: ^file} = settings} -> {:ok, put_settings(state, settings)}
      {:ok, _new_file} -> {:stopped, state |> drop() |> run()}
      :off -> {:stopped, %{drop(state) | error: nil}}
      {:error, error} -> {:stopped, state |> drop() |> failed(error)}
    end
  rescue
    exception -> {:stopped, state |> drop() |> failed(Exception.message(exception))}
  end

  # Lookups under way are left to their tasks, which stop at their timeout,
  # and a write under way to its own check of the configuration; a new
  # generation keeps either's result out of what follows
  defp drop(state) do
    for {ref, {_target, _batch, deadline}} <- state.lookups do
      Process.demonitor(ref, [:flush])
      Process.cancel_timer(deadline)
    end

    :atomics.put(state.generation_ref, 1, state.generation + 1)
    state = state |> cancel_flush() |> cancel_verify() |> cancel_timeout_retry()

    %{
      state
      | settings: nil,
        file: nil,
        generation: state.generation + 1,
        lookups: %{},
        queue: :queue.new(),
        results: %{},
        fresh: MapSet.new(),
        timeout_retries: %{},
        admitted: MapSet.new(),
        write_requested: false,
        check_requested: false,
        verify_requested: false
    }
  end

  # A host with addresses, with none, or whose lookup failed or left a family
  # unread (`{:lookup_failed, failures}`), which is not admitted on the
  # families read
  defp record(state, {:host, host}, result) do
    case complete(result) do
      {:ok, [_ | _] = addresses} -> put_result(state, host, {:ok, normalize_addresses(addresses)})
      {:ok, []} -> put_result(state, host, :unresolved)
      {:error, :nxdomain} -> put_result(state, host, :unresolved)
      failed_or_incomplete -> put_result(state, host, {:lookup_failed, failures(failed_or_incomplete)})
    end
  end

  # A failed or incomplete lookup of this server's addresses keeps the last
  # ones it found, which count for `:addresses_max_age` after they were found
  defp record(state, {:own, name}, result) do
    case complete(result) do
      {:ok, [_ | _] = addresses} ->
        %{state | own: {name, normalize_addresses(addresses), System.monotonic_time(:millisecond)}}

      _failed_or_incomplete ->
        state
    end
  end

  # An incomplete answer with no family unread is a complete one
  defp complete({:incomplete, addresses, []}) when is_list(addresses), do: {:ok, addresses}
  defp complete({:incomplete, addresses, [], _reasons}) when is_list(addresses), do: {:ok, addresses}
  defp complete(result), do: result

  # Each unread family and why, from the resolver's answer; a whole lookup
  # that failed failed for both families
  defp failures({:incomplete, _addresses, families, reasons}) when is_map(reasons),
    do: family_failures(families, &Map.get(reasons, &1))

  defp failures({:incomplete, _addresses, families}), do: family_failures(families, fn _family -> :other end)
  defp failures({:error, reason}), do: family_failures(@families, fn _family -> reason end)
  defp failures(_other), do: family_failures(@families, fn _family -> :other end)

  defp family_failures(families, reason_of) do
    families = if is_list(families), do: Enum.filter(@families, &(&1 in families)), else: []
    families = if families == [], do: @families, else: families
    Map.new(families, &{&1, failure_reason(reason_of.(&1))})
  end

  defp failure_reason(reason) do
    if reason in Brando.Tenant.ServedHosts.Resolver.reasons(), do: reason, else: :other
  end

  # An answer that is no timeout ends the host's quick retry at once, not at
  # the next write
  defp put_result(state, host, result) do
    retries = if timed_out?(result), do: state.timeout_retries, else: Map.delete(state.timeout_retries, host)

    %{
      state
      | results: Map.put(state.results, host, result),
        fresh: MapSet.put(state.fresh, host),
        timeout_retries: retries
    }
  end

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

  # One verification pending at a time: a later write's replaces it
  defp verify_soon(state, %{written?: true}) do
    state = cancel_verify(state)
    verify = make_ref()
    %{state | verify_timer: Process.send_after(self(), {:verify, verify}, state.settings.verify_interval), verify: verify}
  end

  defp verify_soon(state, _result), do: state

  defp cancel_verify(%{verify_timer: nil} = state), do: state

  defp cancel_verify(state) do
    Process.cancel_timer(state.verify_timer)
    %{state | verify_timer: nil, verify: nil}
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

  defp idle_writer?(state),
    do: is_nil(state.writing) and not state.write_requested and not state.check_requested and not state.verify_requested

  defp run(state) do
    state = cancel_tick(state)

    case settings() do
      :off ->
        %{drop(state) | error: nil}

      {:error, error} ->
        failed(%{state | settings: nil}, error)

      {:ok, settings} ->
        request_write(%{put_settings(state, settings) | check_requested: true})
    end
  rescue
    # A bad config or a broken cache must not restart this process until its
    # supervisor, and the application with it, gives up. A lookup started
    # before the failure stops at its own timeout.
    exception -> failed(state, Exception.message(exception))
  end

  # Every replacement of the settings goes through here: what is remembered
  # about one file, its admitted hosts among it, never carries over to another,
  # where a new server's addresses may differ
  defp put_settings(%{file: file} = state, settings) do
    state = if file in [nil, settings.file], do: state, else: drop(state)
    %{state | settings: settings, file: settings.file}
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
  defp maybe_start_write(
         %{writing: nil, settings: %{}, write_requested: write?, check_requested: check?, verify_requested: verify?} =
           state
       )
       when write? or check? or verify? do
    start_write(state)
  rescue
    exception ->
      failed(
        %{state | write_requested: false, check_requested: false, verify_requested: false},
        Exception.message(exception)
      )
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
      owner: self(),
      file: state.settings.file,
      generation: state.generation,
      generation_ref: state.generation_ref,
      keep: MapSet.union(state.admitted, MapSet.new(admit)),
      check?: state.check_requested,
      # Any other write asked for is a write all the same
      verify?: not state.write_requested and not state.check_requested
    }

    # An answer still waiting for this server's addresses stays fresh
    fresh = MapSet.filter(state.fresh, &(decided[&1] == :pending))

    state = %{
      state
      | write_requested: false,
        check_requested: false,
        verify_requested: false,
        write_job: job,
        fresh: fresh
    }

    case Process.whereis(Brando.Tenant.ServedHosts.TaskSupervisor) do
      nil ->
        written(%{state | writing: make_ref()}, write_failed(job, "no task supervisor to write it"))

      supervisor ->
        # Not linked: a write that crashes would take this process down with
        # it, and an exit does not reach a writer stalled in a file call until
        # that call returns. The writer checks its owner before the rename.
        task = Task.Supervisor.async_nolink(supervisor, fn -> write_hosts(job) end)
        %{state | writing: task.ref}
    end
  end

  # In the task, and in this order: read the file, read the bindings, work out
  # the hosts, write the temporary file and sync it, check that the owner, the
  # configuration and the generation still stand, rename. The bindings come
  # after the file, so a host bound and admitted by another node while the
  # write waited is in both and stays; the check comes last, so a write whose
  # process stopped, whose file was unset or changed, or whose work was
  # dropped, never replaces the file.
  defp write_hosts(job) do
    run_test_hook(:before_write)
    if may_write?(job), do: read_and_write(job), else: :cancelled
  end

  defp read_and_write(%{file: file, keep: keep} = job) do
    read = read_file(file)
    listed = MapSet.new(listed(read))
    hosts = Enum.filter(servable_bound_hosts(), &(MapSet.member?(listed, &1) or MapSet.member?(keep, &1)))

    written =
      case read do
        {:ok, existing, _listed} -> verify_or_write(job, existing, hosts, listed)
        {:error, reason} -> {false, "#{file}: #{:file.format_error(reason)}"}
      end

    case written do
      cancelled_or_verified when cancelled_or_verified in [:cancelled, :verified] ->
        cancelled_or_verified

      {written?, error} ->
        %{read?: match?({:ok, _, _}, read), listed: listed, hosts: hosts, written?: written?, error: error}
    end
  end

  # A verification writes only when a host this process keeps is missing
  defp verify_or_write(%{verify?: true} = job, existing, hosts, listed) do
    if Enum.all?(hosts, &MapSet.member?(listed, &1)), do: :verified, else: write(job, existing, hosts)
  end

  defp verify_or_write(job, existing, hosts, _listed), do: write(job, existing, hosts)

  # Only the registered process's writes land, a restarted one's writer not
  # being its successor's, only to the file configured now, and only while
  # the process has not dropped the work since: a file changed away and back
  # leaves the path as it was, but not the generation
  defp may_write?(%{owner: owner, file: file, generation: generation, generation_ref: generation_ref}) do
    Process.whereis(__MODULE__) == owner and Process.alive?(owner) and configured_file() == file and
      :atomics.get(generation_ref, 1) == generation
  end

  defp configured_file do
    config = config()
    if Keyword.keyword?(config), do: Keyword.get(config, :file)
  end

  # Tests hold a write at `:before_write`, before it reads the file, and at
  # `:before_rename`, once its temporary file is synced
  defp run_test_hook(key) do
    case Keyword.get(config(), key) do
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
      {:ok, state} ->
        cond do
          # Work dropped since it started, for another file or not: what it
          # found is not this file's, and the write asked for since follows
          not same_work?(state, job) -> state |> maybe_start_write() |> settle()
          result == :cancelled -> state |> request_write() |> settle()
          result == :verified -> state |> maybe_start_write() |> settle()
          true -> state |> apply_write(job, result) |> verify_soon(result) |> maybe_start_write() |> settle()
        end

      {:stopped, state} ->
        settle(state)
    end
  end

  defp same_work?(state, job), do: job.file == state.settings.file and job.generation == state.generation

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
    log_lookup_failures(hosts, status().hosts)
    publish(%{file: file, hosts: hosts, addresses: format_addresses(own_addresses(state)), error: result.error})
    state = if Enum.any?(decided, &match?({_host, :admit}, &1)), do: %{state | write_requested: true}, else: state
    state = state |> track_timeouts() |> retry_timeouts_soon()
    schedule(state, retry?(state, decided) or result.error != nil)
  end

  # A host whose lookup timed out gets one quick retry: `:pending` until its
  # retry looks it up again. An answer that is no timeout ends it; a host
  # looked up again, with no answer yet, keeps its entry.
  defp track_timeouts(state) do
    kept = Map.take(state.timeout_retries, Map.keys(state.results) ++ MapSet.to_list(pending_hosts(state)))
    %{state | timeout_retries: Enum.reduce(state.results, kept, &track_timeout/2)}
  end

  defp track_timeout({host, result}, retries) do
    if timed_out?(result), do: Map.put_new(retries, host, :pending), else: Map.delete(retries, host)
  end

  defp timed_out?({:lookup_failed, failures}), do: :timeout in Map.values(failures)
  defp timed_out?(_result), do: false

  defp retry_timeouts_soon(%{timeout_timer: nil} = state) do
    if Enum.any?(state.timeout_retries, &match?({_host, :pending}, &1)) do
      ref = make_ref()
      timer = Process.send_after(self(), {:retry_timeouts, ref}, state.settings.timeout_retry_interval)
      %{state | timeout_timer: timer, timeout_tick: ref}
    else
      state
    end
  end

  defp retry_timeouts_soon(state), do: state

  defp cancel_timeout_retry(%{timeout_timer: nil} = state), do: state

  defp cancel_timeout_retry(state) do
    Process.cancel_timer(state.timeout_timer)
    %{state | timeout_timer: nil, timeout_tick: nil}
  end

  # The quick retry: the timed-out hosts still outside the file, looked up
  # again, and only once. A host with an answer no write has used yet keeps it.
  defp retry_timeouts(state) do
    bound = MapSet.new(servable_bound_hosts())

    hosts =
      for {host, :pending} <- state.timeout_retries,
          MapSet.member?(bound, host) and not MapSet.member?(state.admitted, host) and
            not MapSet.member?(state.fresh, host),
          do: host

    retries = Map.new(state.timeout_retries, fn {host, _pending} -> {host, :done} end)
    look_up(%{state | timeout_retries: retries}, hosts)
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
        look_up_own(state)

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

  # This server's addresses on their own, for a check that looks no host up
  # while none are known, as after a start: the status names them from the
  # first check, and the lookup runs in a task like every other
  defp look_up_own(%{settings: %{own_source: {:lookup, _name}}} = state) do
    if is_nil(looked_up_own(state)) and not own_pending?(state) do
      batch = state.batch + 1
      pump(queue_own(%{state | batch: batch}, batch))
    else
      state
    end
  end

  defp look_up_own(state), do: state

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
  # unresolved, its lookup failed, or `:pending` while its lookup runs or this
  # server's addresses are not known yet
  defp decide(%{settings: %{admit: :always}}, _host, _pending), do: :admit

  defp decide(state, host, pending) do
    cond do
      MapSet.member?(pending, host) -> :pending
      not Map.has_key?(state.results, host) -> :pending
      state.results[host] == :unresolved -> :unresolved
      match?({:lookup_failed, _failures}, state.results[host]) -> state.results[host]
      own_known?(state) -> classify(elem(state.results[host], 1), own_addresses(state))
      true -> :pending
    end
  end

  defp own_addresses(%{settings: nil}), do: []
  defp own_addresses(%{settings: %{own_source: {:fixed, addresses}}}), do: addresses
  defp own_addresses(state), do: looked_up_own(state) || []

  # Known when configured, looked up within `:addresses_max_age`, or when no
  # lookup of them runs
  defp own_known?(%{settings: %{own_source: {:fixed, _addresses}}}), do: true
  defp own_known?(state), do: looked_up_own(state) != nil or not own_pending?(state)

  # This server's looked-up addresses, nil once older than `:addresses_max_age`:
  # the age is applied where they are read, so an expired value admits nothing
  # while its refresh runs
  defp looked_up_own(%{settings: %{own_source: {:lookup, name}} = settings, own: {name, addresses, found}}) do
    if System.monotonic_time(:millisecond) - found < settings.addresses_max_age, do: addresses
  end

  defp looked_up_own(_state), do: nil

  # A host looked up again keeps the state its last lookup gave it meanwhile;
  # a host never looked up is checking
  defp pending_state(host, previous) do
    case Map.get(previous, host) do
      {:waiting, _addresses} = waiting -> waiting
      {:lookup_failed, _failures} = failed -> failed
      :unresolved -> :unresolved
      _none -> :checking
    end
  end

  # Once per host as its lookups start failing, and again when what failed
  # changes; a retry that fails the same way says nothing
  defp log_lookup_failures(hosts, previous) do
    for {host, {:lookup_failed, failures} = failed} <- hosts, previous[host] != failed do
      Logger.warning(
        "[Brando.Tenant.ServedHosts] Could not look up #{host} (#{describe_failures(failures)}); " <>
          "it is not admitted, and is looked up again at each check"
      )
    end
  end

  defp describe_failures(failures) do
    @families
    |> Enum.filter(&Map.has_key?(failures, &1))
    |> Enum.map_join(", ", &"#{family_name(&1)}: #{failures[&1]}")
  end

  defp family_name(:inet), do: "IPv4"
  defp family_name(:inet6), do: "IPv6"

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
      timeout_retry_interval: milliseconds(config, :timeout_retry_interval, @timeout_retry_interval),
      recheck_interval: milliseconds(config, :recheck_interval, @recheck_interval),
      flush_interval: milliseconds(config, :flush_interval, @flush_interval),
      verify_interval: milliseconds(config, :verify_interval, @verify_interval),
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
  defp write(job, existing, hosts) do
    # Each line checked on its own, whatever produced the list
    content = hosts |> Enum.filter(&servable?/1) |> Enum.map_join(&[&1, "\n"])

    if content == existing do
      {true, nil}
    else
      replace(job, content)
    end
  end

  # A random name created exclusively, removed when the write or the rename
  # fails. Temporary files a crash left behind are removed first.
  defp replace(%{file: file} = job, content) do
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
             :ok <- run_test_hook(:before_rename),
             {:may_write, true} <- {:may_write, may_write?(job)},
             :ok <- File.rename(temporary, file) do
          {true, nil}
        else
          {:may_write, false} ->
            File.rm(temporary)
            :cancelled

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
