defmodule Brando.Cache do
  @moduledoc """
  Interface for the main cache module
  """
  use Brando.Tracing.Decorator

  alias Brando.Authorization.Boundary
  alias Brando.Cache.Freshness
  alias Brando.CacheSync
  alias Brando.Tenant

  @cache_module Application.compile_env(:brando, :cache_module, Cachex)

  # The site caches, by the name their module rebuilds them under
  @site_caches %{
    identity: Brando.Cache.Identity,
    seo: Brando.Cache.SEO,
    globals: Brando.Cache.Globals,
    palettes: Brando.Cache.Palettes,
    navigation: Brando.Cache.Navigation
  }

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
  navigation caches, on this node. For changes made where no node hears
  about them: a seed, a mix task, SQL. A save on another node reaches this
  one by itself (`Brando.CacheSync`); each node has its own caches, so on
  several nodes run this on each, or restart them.
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

  # Rebuilt rather than filled: a fill that read before the change cannot keep
  # what it stores
  defp reload_site_caches do
    for cache <- Map.keys(@site_caches), do: rebuild(cache)
    :ok
  end

  @doc """
  Rebuilds the site cache `cache` (`:identity`, `:seo`, `:globals`,
  `:palettes` or `:navigation`) from the database once the transaction
  around the caller has committed, or at once outside one
  (`Brando.Repo.after_commit/2`). Read inside the transaction, rows that roll
  back would stay in the cache. A transaction that saves several rows
  rebuilds it once.

  It runs under the caller's site, and unscoped: the cache is every
  visitor's, not what the saving user may read. The other nodes rebuild
  their copies when they hear of it, after the commit too
  (`Brando.CacheSync`).

  A fill or rebuild that read the database before another rebuild began
  does not keep what it stored: it may have read before that rebuild's write,
  and the next read fills the cache again. Nothing waits for another.
  """
  @spec rebuild_after_commit(atom()) :: :ok
  def rebuild_after_commit(cache) when is_map_key(@site_caches, cache) do
    context = context()
    rebuild = Tenant.capture_context(fn -> rebuild_for_write(cache) end)
    Brando.Repo.after_commit({__MODULE__, cache, context}, rebuild)
    unless Tenant.outside_site?(), do: CacheSync.broadcast(__MODULE__, {cache, context})
    :ok
  end

  # Render jobs queued from here on carry the token, so a node that has not
  # rebuilt since rebuilds before it renders. This node knows it only once
  # its own rebuild has run: one that raised leaves its jobs to rebuild too.
  defp rebuild_for_write(cache) do
    input = Freshness.input(:site_cache, cache)

    if input && not Tenant.outside_site?() do
      token = Freshness.make(input)
      rebuild(cache)
      Freshness.known(input, token)
    else
      rebuild(cache)
    end
  end

  @doc "Rebuilds this node's copy of a site cache another node rebuilt (`Brando.CacheSync`)."
  @spec refresh_node_cache({atom(), String.t() | :public | nil}) :: :ok
  def refresh_node_cache({cache, context}) when is_map_key(@site_caches, cache) do
    in_context(context, fn -> rebuild(cache) end)
    :ok
  end

  # Moves the cache's generation before it reads, so a fill or rebuild that
  # read before it withdraws what it stores
  defp rebuild(cache) do
    unless Tenant.outside_site?() do
      generation = System.unique_integer()
      put(generation_key(cache), generation, :infinite)
      Boundary.with_scope(nil, fn -> store(cache, generation) end)
    end

    :ok
  end

  @doc false
  # Fills the site cache `cache` from the database (its module's `set/0`, and
  # a read that found it empty), and returns what it read as `[key: value]`,
  # whether it kept it or not.
  @spec fill(atom()) :: keyword()
  def fill(cache) when is_map_key(@site_caches, cache), do: store(cache, get(generation_key(cache)))

  # Stores what the cache's module reads, unless a rebuild began since
  # `generation`, and withdraws it if one began while it stored
  defp store(cache, generation) do
    values = Map.fetch!(@site_caches, cache).load()
    if get(generation_key(cache)) == generation, do: keep(cache, values, generation)
    values
  end

  defp keep(cache, values, generation) do
    Enum.each(values, fn {key, value} -> put(key, value, :infinite) end)
    if get(generation_key(cache)) != generation, do: Enum.each(values, fn {key, _} -> del(key) end)
  end

  # Under the site's cache key: `public`'s copy and the unprefixed one are one
  defp generation_key(cache), do: {__MODULE__, :generation, cache}

  @doc """
  Runs `fun`, which reads the site cache `cache`, after every rebuild
  `rebuild_after_commit/1` held in the transaction: rendering the entries
  that show the cache, say, which would otherwise store what it held before.
  Once per `cache` in a transaction, at once outside one.
  """
  @spec after_rebuild(atom(), (-> any())) :: :ok
  def after_rebuild(cache, fun) when is_map_key(@site_caches, cache) do
    key = {__MODULE__, :after_rebuild, cache, context()}
    Brando.Repo.after_commit(key, Tenant.capture_context(fun), late: true)
  end

  @doc """
  Refreshes each render input in an entry render job's arguments that this
  node has not refreshed for since the job was queued: a site cache the
  renders read, or a query cache source they list. The job may run on a
  node that has not heard of the write that queued it yet, and would render
  from what its caches held before (`Brando.Cache.Freshness`).
  """
  @spec ensure_fresh(map()) :: :ok
  def ensure_fresh(args) do
    for {input, token} <- Freshness.unknown(args) do
      refresh(input)
      Freshness.known(input, token)
    end

    :ok
  end

  defp refresh({:site_cache, cache}), do: rebuild(cache)
  defp refresh({:query_source, source}), do: Brando.Cache.Query.refresh_node_cache({Tenant.current_prefix(), source})

  # Where the caller's site caches are: its site, `public` on purpose, or neither
  defp context, do: if(Tenant.public?(), do: :public, else: Tenant.current_prefix())

  defp in_context(nil, fun), do: fun.()
  defp in_context(:public, fun), do: Tenant.with_public(fun)
  defp in_context(prefix, fun), do: Tenant.with_prefix(prefix, fun)

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
