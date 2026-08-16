defmodule Brando.Tenant.Cache do
  @moduledoc """
  Read-optimized cache for Brando's public site and environment registry.

  Registry writes are deliberately rare. Warming after a mutation trades the
  global cost of updating `:persistent_term` for allocation-free lookups on
  every request. When tenancy is disabled, warming only clears old tenant
  entries and never queries the database.
  """

  alias Brando.Sites.Site
  alias Brando.Tenant

  @cache_keys_key {:brando, :tenant_cache_keys}
  @public_opts [prefix: "public"]

  @spec warm() :: :ok
  def warm do
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

  @spec invalidate() :: :ok
  def invalidate, do: warm()

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

  def get_env(site_key, environment_key) do
    :persistent_term.get({:brando, :env, site_key, environment_key}, nil)
  end

  def get_live_env(site_key) do
    :persistent_term.get({:brando, :live_env, site_key}, nil)
  end

  defp cache_sites(sites) do
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
          if site.status == :active and environment.domain do
            domain = environment.domain |> String.trim() |> String.downcase()
            [{{:brando, :env_domain, domain}, {site, environment}}]
          else
            []
          end

        live =
          if site.status == :active and environment.live,
            do: [{{:brando, :live_env, site.key}, environment}],
            else: []

        by_key ++ by_domain ++ live
      end)

    site_entry ++ environment_entries
  end
end
