defmodule Brando.Cache do
  @moduledoc """
  Interface for the main cache module
  """
  use Brando.Tracing.Decorator

  alias Brando.Tenant

  @cache_module Application.compile_env(:brando, :cache_module, Cachex)

  @spec get(any) :: any
  def get(key) do
    case get_from_cache(key) do
      {:ok, val} -> val
      {:error, _} -> nil
    end
  end

  @doc """
  A site's cached data (identity, SEO, globals, menus, palettes): `nil`
  outside every site in multi-site mode (`Brando.Tenant.outside_site?/0`),
  whatever `public`'s copy put under the unprefixed key.
  """
  @spec get_site(any) :: any
  def get_site(key), do: if(Tenant.outside_site?(), do: nil, else: get(key))

  @spec get(any, atom) :: any
  def get(key, sub_key) do
    case get_from_cache(key) do
      {:ok, val} -> Map.get(val, sub_key, nil)
      {:error, _} -> nil
    end
  end

  def put(key, var, ttl \\ :timer.minutes(15))

  def put(key, val, :infinite) do
    @cache_module.put(:cache, cache_key(key), val)
  end

  def put(key, val, ttl) do
    @cache_module.put(:cache, cache_key(key), val, expire: ttl)
  end

  def update(key, val) do
    @cache_module.update(:cache, cache_key(key), val)
  end

  def del(key) do
    @cache_module.del(:cache, cache_key(key))
  end

  @doc """
  Empties every cache and reloads the site-wide ones: the query cache (pages,
  fragments, modules, …) and the identity, SEO, globals, palettes and
  navigation caches. For changes made outside this server — a seed, a mix
  task, another node — that it can't have heard about.
  """
  @decorate span("brando.cache.reload_all")
  def reload_all do
    Cachex.clear(:query)
    reload_site_caches()
  end

  @doc """
  As `reload_all/0`, but empties only the given query cache keys: for a user
  who may not empty other sites' entries.
  """
  @decorate span("brando.cache.reload_all")
  def reload_all(query_keys) when is_list(query_keys) do
    Enum.each(query_keys, &Cachex.del(:query, &1))
    reload_site_caches()
  end

  defp reload_site_caches do
    Brando.Cache.Identity.set()
    Brando.Cache.SEO.set()
    Brando.Cache.Globals.set()
    Brando.Cache.Palettes.set()
    Brando.Cache.Navigation.set()
    :ok
  end

  @doc """
  Runs `rebuild`, which rebuilds the site cache `cache` from the database,
  once the transaction around the caller has committed, or at once outside
  one (`Brando.Repo.after_commit/2`). Read inside the transaction, rows that
  roll back would stay in the cache. A transaction that saves several rows
  rebuilds it once.

  It runs under the caller's site, and unscoped: the cache is every
  visitor's, not what the saving user may read.
  """
  @spec rebuild_after_commit(atom(), (-> any())) :: :ok
  def rebuild_after_commit(cache, rebuild) do
    key = {__MODULE__, cache, Tenant.current_prefix(), Tenant.public?()}
    unscoped = fn -> Brando.Authorization.Boundary.with_scope(nil, rebuild) end
    Brando.Repo.after_commit(key, Tenant.capture_context(unscoped))
  end

  @doc """
  Runs `fun`, which reads the site cache `cache`, after every rebuild
  `rebuild_after_commit/2` held in the transaction: rendering the entries
  that show the cache, say, which would otherwise store what it held before.
  Once per `cache` in a transaction, at once outside one.
  """
  @spec after_rebuild(atom(), (-> any())) :: :ok
  def after_rebuild(cache, fun) do
    key = {__MODULE__, :after_rebuild, cache, Tenant.current_prefix(), Tenant.public?()}
    Brando.Repo.after_commit(key, Tenant.capture_context(fun), late: true)
  end

  @doc """
  Rebuilds the site cache that holds `entry` (a palette, global set, menu or
  menu item, identity or SEO record) and renders the entries that show it,
  as its context's mutation callbacks do, for a write that runs none: a
  restore from the trash, a status set from a listing in legacy mode. Leaves
  any other entry alone.
  """
  @spec entry_changed(struct()) :: :ok
  def entry_changed(%{__struct__: Brando.Content.Palette} = entry),
    do: refreshed(Brando.Cache.Palettes.update({:ok, entry}))

  def entry_changed(%{__struct__: Brando.Sites.GlobalSet} = entry),
    do: {:ok, entry} |> Brando.Cache.Globals.update() |> Brando.Sites.update_villains_referencing_global() |> refreshed()

  def entry_changed(%{__struct__: schema} = entry) when schema in [Brando.Navigation.Menu, Brando.Navigation.Item],
    do:
      {:ok, entry}
      |> Brando.Cache.Navigation.update()
      |> Brando.Navigation.update_villains_referencing_navigation()
      |> refreshed()

  def entry_changed(%{__struct__: Brando.Sites.Identity} = entry),
    do:
      {:ok, entry} |> Brando.Cache.Identity.update() |> Brando.Sites.update_villains_referencing_identity() |> refreshed()

  def entry_changed(%{__struct__: Brando.Sites.SEO} = entry), do: refreshed(Brando.Cache.SEO.update({:ok, entry}))
  def entry_changed(_entry), do: :ok

  defp refreshed({:ok, _entry}), do: :ok

  defp get_from_cache(key) do
    @cache_module.get(:cache, cache_key(key))
  end

  defp cache_key(key), do: Tenant.cache_key(key)
end
