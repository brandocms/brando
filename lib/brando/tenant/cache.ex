defmodule Brando.Tenant.Cache do
  @moduledoc """
  Read-optimized cache for Brando's public site and environment registry.

  Registry writes are deliberately rare. Warming after a mutation trades the
  global cost of updating `:persistent_term` for allocation-free lookups on
  every request. When tenancy is disabled, warming only clears old tenant
  entries and never queries the database.

  The cache is per node: `invalidate/0` warms this node and tells the others
  through `Brando.CacheSync`. Warms on a node run one at a time, so the last
  to publish read the registry last.
  """

  alias Brando.CacheSync
  alias Brando.Sites.Site
  alias Brando.Tenant

  @cache_keys_key {:brando, :tenant_cache_keys}
  @public_opts [prefix: "public"]

  @spec warm() :: :ok
  def warm do
    # One at a time on this node, read and publication together: a warm that
    # read the registry before another must not publish after it
    :global.trans({{__MODULE__, :warm}, self()}, &do_warm/0, [node()], :infinity)
    # Every warm, on every node, is a registry refresh the served hosts file follows
    Brando.Tenant.ServedHosts.registry_changed()
  end

  defp do_warm do
    if Tenant.enabled?() do
      Site
      |> Brando.Repo.all(@public_opts)
      |> Brando.Repo.preload(:environments, @public_opts)
      |> cache_sites()
    else
      clear()
    end

    :ok
  end

  @doc """
  Warms every node's cache once the transaction around the caller has
  committed (at once outside one): this node in the caller's process, the
  others through `Brando.CacheSync`. Warmed before then, a node could read the
  registry without the write, and a rollback would leave it cached.
  """
  @spec invalidate() :: :ok
  def invalidate do
    Brando.Repo.after_commit(:tenant_cache, fn ->
      warm()
      CacheSync.broadcast(__MODULE__, :registry)
    end)
  end

  @doc "Warms this node's cache for a registry write on another node (`Brando.CacheSync`)."
  @spec refresh_node_cache(:registry) :: :ok
  def refresh_node_cache(:registry), do: warm()

  @spec clear() :: :ok
  def clear do
    @cache_keys_key
    |> :persistent_term.get([])
    |> Enum.each(&:persistent_term.erase/1)

    :persistent_term.erase(@cache_keys_key)
    :ok
  end

  def get_site(site_key) do
    :persistent_term.get({:brando, :site, site_key}, nil)
  end

  def list_sites do
    :persistent_term.get({:brando, :sites}, [])
  end

  def get_env_by_domain(domain) when is_binary(domain) do
    normalized_domain = domain |> String.trim() |> String.downcase()
    :persistent_term.get({:brando, :env_domain, normalized_domain}, nil)
  end

  def get_env_by_domain(_domain), do: nil

  @doc """
  The site and environment `host` redirects to, when it is one of an active
  site's environment's redirect hosts, or nil.
  """
  def get_redirect(host) when is_binary(host) do
    :persistent_term.get({:brando, :redirect_host, host |> String.trim() |> String.downcase()}, nil)
  end

  def get_redirect(_host), do: nil

  def get_env(site_key, environment_key) do
    :persistent_term.get({:brando, :env, site_key, environment_key}, nil)
  end

  def get_live_env(site_key) do
    :persistent_term.get({:brando, :live_env, site_key}, nil)
  end

  @doc """
  Every host the registry binds, sorted and listed once: each environment's
  `domain` and its `redirect_hosts`, for every site in the registry,
  suspended and archived ones included, since Brando still answers for them.
  A redirect host answers with a redirect to its domain, and needs a route
  and a certificate as the domain does. The installation's own hosts
  (`Brando.Tenant.InstallationHosts`) are left out, and so is a stored
  spelling with a trailing dot, which no lookup answers, along with the
  redirect hosts of such a domain.

  This is the one list of bound hosts: a host an environment answers on
  belongs here, and `Brando.Tenant.ServedHosts` hands it to the reverse proxy.
  Read from this node's cache, so call it after `warm/0`.
  """
  @spec bound_hosts() :: [String.t()]
  def bound_hosts do
    installation_hosts = MapSet.new(Brando.Tenant.InstallationHosts.list())

    list_sites()
    |> Enum.flat_map(fn %Site{environments: environments} -> Enum.flat_map(environments, &environment_hosts/1) end)
    |> Enum.filter(&routable_domain?/1)
    |> Enum.map(&Brando.Environments.Environment.normalize_host/1)
    |> Enum.reject(&(is_nil(&1) or MapSet.member?(installation_hosts, &1)))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Redirect hosts redirect only to a domain that answers
  defp environment_hosts(%{domain: domain, redirect_hosts: redirect_hosts}) do
    if routable_domain?(domain), do: [domain | redirect_hosts || []], else: [domain]
  end

  @doc "Whether this node's cache holds the registry: `warm/0` has run since the last `clear/0` with tenancy on."
  @spec warmed?() :: boolean()
  def warmed?, do: :persistent_term.get(@cache_keys_key, nil) != nil

  defp cache_sites(sites) do
    Enum.each(sites, &Brando.Languages.warn_unconfigured/1)
    entries = [{{:brando, :sites}, sites} | Enum.flat_map(sites, &site_entries/1)]
    previous_keys = :persistent_term.get(@cache_keys_key, [])
    current_keys = Enum.map(entries, &elem(&1, 0))
    current_key_set = MapSet.new(current_keys)

    Enum.each(entries, fn {key, value} ->
      :persistent_term.put(key, value)
    end)

    previous_keys
    |> Enum.reject(&MapSet.member?(current_key_set, &1))
    |> Enum.each(&:persistent_term.erase/1)

    :persistent_term.put(@cache_keys_key, current_keys)
  end

  defp site_entries(%Site{} = site) do
    site_entry = [{{:brando, :site, site.key}, site}]

    environment_entries =
      Enum.flat_map(site.environments, fn environment ->
        by_key = [{{:brando, :env, site.key, environment.key}, environment}]

        by_domain =
          if site.status == :active and routable_domain?(environment.domain) do
            domain = environment.domain |> String.trim() |> String.downcase()
            [{{:brando, :env_domain, domain}, {site, environment}}]
          else
            []
          end

        live =
          if site.status == :active and environment.live,
            do: [{{:brando, :live_env, site.key}, environment}],
            else: []

        # Only to a domain that answers: a suspended or archived site's
        # redirect hosts answer as its domain does
        redirects =
          if by_domain != [],
            do: Enum.map(environment.redirect_hosts || [], &{{:brando, :redirect_host, &1}, {site, environment}}),
            else: []

        by_key ++ by_domain ++ redirects ++ live
      end)

    site_entry ++ environment_entries
  end

  # A trailing dot stored before `Environment` refused it names the same host
  # as the spelling without one, and must not answer beside it.
  defp routable_domain?(domain) when is_binary(domain), do: not (domain |> String.trim() |> String.ends_with?("."))
  defp routable_domain?(_domain), do: false
end
