defmodule Brando.Cache do
  @moduledoc """
  Interface for the main cache module
  """
  use Brando.Tracing.Decorator

  alias Brando.Authorization.Boundary
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
  @held_locks {__MODULE__, :held_locks}
  @render_needs {__MODULE__, :render_needs}
  # Rebuilds a node remembers, per site cache, for the render jobs that ask
  @fresh_tokens 32

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

  defp reload_site_caches do
    Brando.Cache.Identity.set()
    Brando.Cache.SEO.set()
    Brando.Cache.Globals.set()
    Brando.Cache.Palettes.set()
    Brando.Cache.Navigation.set()
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
  (`Brando.CacheSync`). On a node, the site cache's rebuilds and fills run
  one at a time, so one that read the database before another cannot store
  after it.
  """
  @spec rebuild_after_commit(atom()) :: :ok
  def rebuild_after_commit(cache) when is_map_key(@site_caches, cache) do
    context = context()
    Brando.Repo.after_commit({__MODULE__, cache, context}, Tenant.capture_context(fn -> rebuild(cache) end))
    unless Tenant.outside_site?(), do: CacheSync.broadcast(__MODULE__, {cache, context})
    :ok
  end

  @doc "Rebuilds this node's copy of a site cache another node rebuilt (`Brando.CacheSync`)."
  @spec refresh_node_cache({atom(), String.t() | :public | nil}) :: :ok
  def refresh_node_cache({cache, context}) when is_map_key(@site_caches, cache) do
    in_context(context, fn -> rebuild(cache) end)
    :ok
  end

  defp rebuild(cache) do
    unless Tenant.outside_site?() do
      module = Map.fetch!(@site_caches, cache)
      serialize(cache, fn -> Boundary.with_scope(nil, &module.rebuild/0) end)
    end

    :ok
  end

  @doc false
  # Runs `fun`, which stores the site cache `cache` from the database, while
  # no other process on this node stores it for this site.
  @spec serialize(atom(), (-> result)) :: result when result: var
  def serialize(cache, fun) do
    lock = {__MODULE__, cache, context()}
    held = Process.get(@held_locks, [])

    if lock in held do
      fun.()
    else
      :global.trans({lock, self()}, fn -> holding([lock | held], held, fun) end, [node()], :infinity)
    end
  end

  defp holding(locks, held, fun) do
    Process.put(@held_locks, locks)

    try do
      fun.()
    after
      Process.put(@held_locks, held)
    end
  end

  @doc """
  Runs `fun`, which reads the site cache `cache`, after every rebuild
  `rebuild_after_commit/1` held in the transaction: rendering the entries
  that show the cache, say, which would otherwise store what it held before.
  Once per `cache` in a transaction, at once outside one.

  The render jobs `fun` queues may run on any node, and another node may not
  have heard of the rebuild yet. They carry a token for it, and a node that
  has not rebuilt its copy since rebuilds it before it renders
  (`ensure_fresh/1`).
  """
  @spec after_rebuild(atom(), (-> any())) :: :ok
  def after_rebuild(cache, fun) when is_map_key(@site_caches, cache) do
    key = {__MODULE__, :after_rebuild, cache, context()}
    Brando.Repo.after_commit(key, Tenant.capture_context(fn -> render_fresh(cache, fun) end), late: true)
  end

  # This node has rebuilt `cache` for the write
  defp render_fresh(cache, fun) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(9))
    mark_fresh(cache, token)
    needs = Process.get(@render_needs, %{})
    Process.put(@render_needs, Map.put(needs, to_string(cache), token))

    try do
      fun.()
    after
      if needs == %{}, do: Process.delete(@render_needs), else: Process.put(@render_needs, needs)
    end
  end

  @doc false
  # Adds the site caches an entry render queued from `after_rebuild/2` must
  # read rebuilt to the job's arguments.
  @spec put_render_needs(map()) :: map()
  def put_render_needs(args) do
    case Process.get(@render_needs) do
      nil -> args
      needs -> Map.put(args, "site_caches", needs)
    end
  end

  @doc """
  Rebuilds this node's copy of each site cache in `needs` (an entry render
  job's `"site_caches"`, from `after_rebuild/2`) that it has not rebuilt
  since the write that queued the job: a node that runs the job before it
  hears of the write would render from what its cache held before.
  """
  @spec ensure_fresh(map() | nil) :: :ok
  def ensure_fresh(needs) when is_map(needs) do
    for {name, token} <- needs, cache <- List.wrap(cache_named(name)), not fresh?(cache, token) do
      serialize(cache, fn ->
        unless fresh?(cache, token) do
          rebuild(cache)
          mark_fresh(cache, token)
        end
      end)
    end

    :ok
  end

  def ensure_fresh(_needs), do: :ok

  defp cache_named(name), do: Enum.find_value(@site_caches, fn {cache, _} -> to_string(cache) == name && cache end)

  defp fresh?(cache, token), do: token in (get({__MODULE__, :fresh, cache}) || [])

  defp mark_fresh(cache, token) do
    tokens = get({__MODULE__, :fresh, cache}) || []
    put({__MODULE__, :fresh, cache}, Enum.take([token | tokens], @fresh_tokens), :infinite)
  end

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
