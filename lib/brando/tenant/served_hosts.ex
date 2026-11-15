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
  valid host name (`Brando.Environments.Environment.valid_host?/1`) with a dot
  and not an IP address; a domain stored before Brando checked it may be
  neither, and is never written. A bound
  host that is not in the file yet is admitted when it resolves, and every
  address it resolves to, IPv4 and IPv6, is one of this server's: a proxy
  asks for a certificate as soon as it gets a host, and a host whose DNS still
  points elsewhere fails that request. Once in the file, a host stays until no
  environment binds it; a failed lookup never removes one. The file is the
  state: nothing is stored in the database, and on a new server each host is
  admitted again when its DNS arrives there.

  ## When

  After every warm of `Brando.Tenant.Cache`, which runs at boot and on every
  node after a registry write, and once a minute while a bound host waits for
  its DNS or the file could not be written. Each node keeps its own file.

  ## The file

  Sorted, one host per line, each followed by a newline, empty when no host
  is admitted. Written to a temporary file in the same directory and renamed
  over the old one, and only when the content changes. A line that is not a
  bound host is dropped on the next write. A file that cannot be written is
  logged once and retried on the next check.

  Lookups go through `:resolver`, a module implementing
  `Brando.Tenant.ServedHosts.Resolver` (default
  `Brando.Tenant.ServedHosts.DNS`), which tests replace.
  """

  use GenServer

  alias Brando.Environments.Environment
  alias Brando.Tenant.Cache

  require Logger

  @topic "brando:served_hosts"
  @status_key {__MODULE__, :status}
  @retry_after :timer.minutes(1)
  @lookup_timeout :timer.seconds(10)

  @typedoc """
  Where a bound host stands: in the file (`:served`), admitted but the file
  could not be written (`:not_written`), resolving to addresses that are not
  all this server's (`{:waiting, addresses}`), not resolving, or never written
  because the stored value is not a valid host name (`:invalid`).
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

  @doc "The PubSub topic a changed `status/0` is broadcast on, as `{:served_hosts, status}`."
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
    state = %{timer: nil, error: nil}
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
  def handle_info(:retry, state), do: {:noreply, run(%{state | timer: nil})}
  def handle_info(_message, state), do: {:noreply, state}

  defp run(state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    state = %{state | timer: nil}
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
        {bound, invalid} = Enum.split_with(Cache.bound_hosts(), &servable?/1)
        listed = MapSet.new(listed)
        {kept, candidates} = Enum.split_with(bound, &MapSet.member?(listed, &1))
        {admitted, waiting, addresses} = admit(candidates, config)
        hosts = Enum.sort(kept ++ admitted)

        {written?, error} = write(file, existing, hosts)
        state = report(state, file, error)

        statuses =
          Map.new(kept, &{&1, :served})
          |> Map.merge(Map.new(admitted, &{&1, if(written?, do: :served, else: :not_written)}))
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
  # by root: only a host name with a dot that is not an IP address (no
  # top-level domain is all digits) gets a line
  defp servable?(host) do
    Environment.valid_host?(host) and String.contains?(host, ".") and
      not (host |> String.split(".") |> List.last() |> String.match?(~r/\A[0-9]+\z/))
  end

  defp schedule(state, false), do: state
  defp schedule(state, true), do: %{state | timer: Process.send_after(self(), :retry, @retry_after)}

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

    Enum.reduce(lookup_all(candidates, resolver), {[], %{}, own}, fn
      {host, {:ok, [_ | _] = addresses}}, {admitted, waiting, own} ->
        addresses = addresses |> Enum.map(&unmap/1) |> Enum.uniq()

        if own != [] and Enum.all?(addresses, &(&1 in own)) do
          {[host | admitted], waiting, own}
        else
          {admitted, Map.put(waiting, host, {:waiting, Enum.map(addresses, &format_address/1)}), own}
        end

      {host, _not_found}, {admitted, waiting, own} ->
        {admitted, Map.put(waiting, host, :unresolved), own}
    end)
  end

  defp lookup_all(hosts, resolver) do
    hosts
    |> Task.async_stream(&lookup(resolver, &1),
      max_concurrency: 8,
      timeout: @lookup_timeout,
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
  end

  # The configured addresses, or what the endpoint's host resolves to now
  defp own_addresses(config, resolver) do
    case Keyword.get(config, :addresses) do
      addresses when is_list(addresses) -> addresses |> Enum.flat_map(&parse_address/1) |> Enum.uniq()
      nil -> endpoint_addresses(endpoint_host(), resolver)
    end
  end

  defp endpoint_addresses(nil, _resolver), do: []

  defp endpoint_addresses(host, resolver) do
    with [] <- parse_address(host),
         {:ok, addresses} <- lookup(resolver, host) do
      addresses |> Enum.map(&unmap/1) |> Enum.uniq()
    else
      [address] -> [address]
      {:error, _reason} -> []
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
      temporary = Path.join(Path.dirname(file), ".#{Path.basename(file)}.#{System.unique_integer([:positive])}.tmp")

      with :ok <- File.write(temporary, content),
           :ok <- File.rename(temporary, file) do
        {true, nil}
      else
        {:error, reason} ->
          File.rm(temporary)
          {false, "#{file}: #{:file.format_error(reason)}"}
      end
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
    Phoenix.PubSub.broadcast(Brando.pubsub(), @topic, {:served_hosts, status})
  rescue
    # No PubSub registry under that name
    ArgumentError -> :ok
  end

  defp empty_status, do: %{file: nil, hosts: %{}, addresses: [], error: nil}

  defp config, do: Application.get_env(:brando, __MODULE__, [])

  defp configured_file?(file), do: is_binary(file) and String.trim(file) != ""
end
