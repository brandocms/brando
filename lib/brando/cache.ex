defmodule Brando.Cache do
  @moduledoc """
  Interface for the main cache module
  """
  use Brando.Tracing.Decorator

  require Logger

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
  Clears what rendered content reads from the caches, for content written
  outside `Brando.Query`: a seed or a data migration, `Repo.update_all`, SQL.
  `Brando.Query` evicts what it writes, and nothing else does, so pages and
  fragments, which are read with no expiry, stay as they were until a
  restart.

  It empties the caller's site's query cache (pages, fragments, modules,
  containers, palettes and the other lists and entries `Brando.Query`
  caches) and rebuilds its identity, SEO, globals, palettes and menus from
  the database. With `all_sites: true` it does so for every site and
  environment in the registry, and empties the rest of the query cache too.

  It clears this node's caches at once, and the other nodes' through
  `Brando.CacheSync`. Inside a transaction begun with
  `Brando.Repo.transaction/2`, the site caches are rebuilt and the other
  nodes told once it has committed, and the query cache is emptied again
  then.

  It does not render anything again: entries keep the HTML stored when they
  were last rendered. After changing blocks, or what they render (modules,
  globals, fragments), clear the caches first and then render the entries
  with `Brando.Content.Blocks.render_entry/2`, which reads them.

  A script run in its own VM (`mix run`) clears that VM's caches, and those
  of the nodes its PubSub reaches. A server it cannot reach keeps its own:
  clear them from Configuration → Utilities → Clear caches, which runs
  `clear_all/0` on that server, or with `bin/my_app rpc
  "Brando.Cache.clear_content()"` on a release. A data migration runs where
  neither cache is running (`Ecto.Migrator` starts the repo alone), and
  there it clears nothing: clear the server's caches once the migration has
  run.

  Returns `{:ok, summary}`: how many query cache entries this node held
  (`:query_entries`), the site caches it rebuilt (`:site_caches`) and
  whether it cleared one site or all (`:scope`).
  """
  @spec clear_content(keyword()) ::
          {:ok, %{query_entries: non_neg_integer(), site_caches: [atom()], scope: :site | :all}}
  @decorate span("brando.cache.clear_content")
  def clear_content(opts \\ []) do
    opts = Keyword.validate!(opts, all_sites: false)
    scope = if opts[:all_sites], do: :all, else: :site

    cond do
      not caches_running?() -> {:ok, %{query_entries: 0, site_caches: [], scope: scope}}
      scope == :all -> clear_all_content()
      true -> clear_current_content()
    end
  end

  defp clear_all_content do
    entries = Enum.sum(for context <- contexts(), do: in_site(context, &clear_site_content/0))
    {:ok, %{query_entries: entries + Brando.Cache.Query.clear_all(), site_caches: site_cache_names(), scope: :all}}
  end

  defp clear_current_content do
    rebuilt? = not Tenant.outside_site?()
    entries = clear_site_content()
    {:ok, %{query_entries: entries, site_caches: if(rebuilt?, do: site_cache_names(), else: []), scope: :site}}
  end

  # A data migration's VM (`Ecto.Migrator`), or a mix task that does not
  # start the application, runs neither cache: nothing is cached to clear
  defp caches_running?, do: Process.whereis(:cache) != nil and Process.whereis(:query) != nil

  defp clear_site_content do
    entries = Brando.Cache.Query.clear()
    unless Tenant.outside_site?(), do: Enum.each(site_cache_names(), &rebuild_after_commit/1)
    entries
  end

  defp site_cache_names, do: ~w(identity seo globals palettes navigation)a

  # Every site's caches: each environment in the registry, and `public`'s (no
  # prefix outside multi-site mode)
  defp contexts do
    case Tenant.mode() do
      :none ->
        [nil]

      mode ->
        prefixes = for site <- Tenant.Registry.list_sites(), env <- site.environments, do: Tenant.prefix(site, env)
        [if(mode == :multi, do: :public) | prefixes]
    end
  end

  # Unlike `in_context/2`, with no prefix it leaves the caller's
  defp in_site(nil, fun), do: Tenant.with_prefix(nil, fun)
  defp in_site(context, fun), do: in_context(context, fun)

  @doc """
  What Configuration → Utilities → Clear caches runs: `clear_content/1` for
  every site and environment (`all_sites: true`), and, with tenancy, the
  site structure: it reloads the site and environment registry
  (`Brando.Tenant.Cache`), and on a multi-site install drops every site's
  shared-library allowlists, which the next read loads again. On every node,
  as `clear_content/1` does.

  The registry and the allowlists are kept up to date by the screens that
  change them. A row written outside them (a seed, a data migration, SQL)
  reaches no node: a domain changed that way, say, is not served until the
  registry is reloaded.

  It leaves the caches that hold no rows that change outside their screens,
  or whose loss costs something: the frontend asset sets (uploaded files,
  refreshed on every node when one is activated), compiled redirect patterns
  (cached under the rule they compile, whose rules come from the SEO cache
  this rebuilds), editors' copied blocks, live previews, rate limits and
  sign-in lockouts.

  An environment whose tables cannot be read (one being created, or whose
  setup failed) is skipped and logged, and the others are cleared. It
  raises `ArgumentError` inside a transaction: there the rebuilds would wait
  for the commit, where a failure is no longer the summary's to report, and
  a failed read would abort the caller's transaction.

  Returns `{:ok, summary}`: `clear_content/1`'s summary with
  `:site_structure`, what of the site structure it reloaded
  (`[:registry, :shared_library]`, `[:registry]` on a single-site install,
  none without tenancy), and `:skipped`, the schema prefixes of the
  environments it skipped.
  """
  @spec clear_all() ::
          {:ok,
           %{
             query_entries: non_neg_integer(),
             site_caches: [atom()],
             scope: :all,
             site_structure: [:registry | :shared_library],
             skipped: [String.t()]
           }}
  @decorate span("brando.cache.clear_all")
  def clear_all do
    if Brando.Repo.repo().in_transaction?(),
      do: raise(ArgumentError, "Brando.Cache.clear_all/0 runs outside a transaction")

    if caches_running?() do
      registry = if Tenant.enabled?(), do: [:registry], else: []
      if registry != [], do: :ok = Tenant.Cache.invalidate()

      # Before the site caches: the palette CSS holds the shared palettes
      # each site's allowlist enables
      shared_library = if Tenant.mode() == :multi, do: [:shared_library], else: []
      if shared_library != [], do: :ok = Brando.Content.SharedLibrary.forget_allowlists()

      {entries, skipped} = Enum.reduce(contexts(), {0, []}, &clear_context/2)

      {:ok,
       %{
         query_entries: entries + Brando.Cache.Query.clear_all(),
         site_caches: site_cache_names(),
         scope: :all,
         site_structure: registry ++ shared_library,
         skipped: Enum.reverse(skipped)
       }}
    else
      {:ok, %{query_entries: 0, site_caches: [], scope: :all, site_structure: [], skipped: []}}
    end
  end

  # An environment whose tables cannot be read (one being created, or whose
  # setup failed) must not keep the others' caches: its rebuild reads in a
  # transaction of its own (`clear_all/0` runs outside one), which the failed
  # read rolls back, and it is skipped and logged. Its query cache is
  # emptied all the same.
  defp clear_context(context, {entries, skipped}) do
    case clear_context(context) do
      {:ok, count} -> {entries + count, skipped}
      :skipped -> {entries, [context_name(context) | skipped]}
    end
  end

  defp clear_context(context) do
    Brando.Repo.repo().transaction(fn -> in_site(context, &clear_site_content/0) end)
  rescue
    error ->
      Logger.error(
        "[Brando.Cache] Did not rebuild the site caches of #{context_name(context)}: " <> Exception.message(error)
      )

      :skipped
  end

  defp context_name(nil), do: "public"
  defp context_name(:public), do: "public"
  defp context_name(prefix), do: prefix

  @doc """
  Empties every cache and reloads the site-wide ones: the query cache (pages,
  fragments, modules, …) and the identity, SEO, globals, palettes and
  navigation caches, on this node. For changes made where no node hears
  about them: a seed, a mix task, SQL. A save on another node reaches this
  one by itself (`Brando.CacheSync`); each node has its own caches, so on
  several nodes run this on each, restart them, or use `clear_all/0`, which
  reaches every node.
  """
  @decorate span("brando.cache.reload_all")
  def reload_all do
    Cachex.clear(:query)
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

  It runs under the caller's site, and unscoped, as does a read that finds
  the cache empty and fills it: the cache is every visitor's, not what the
  saving or reading user may read. The other nodes rebuild
  their copies when they hear of it, after the commit too
  (`Brando.CacheSync`).

  A fill or rebuild that read the database before another rebuild began
  does not keep what it read: it may have read before that rebuild's write.
  It empties the cache instead, rather than leave what the cache held before
  that write, and the next read fills it again. Nothing waits for another.
  """
  @spec rebuild_after_commit(atom()) :: :ok
  def rebuild_after_commit(cache) when is_map_key(@site_caches, cache) do
    context = context()
    rebuild = Tenant.capture_context(fn -> rebuild_for_write(cache) end)
    Brando.Repo.after_commit({__MODULE__, cache, context}, rebuild)
    Brando.SSG.ContentChanges.touch()
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
      store(cache, generation)
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
  # `generation`. One that began first empties the cache instead: what it
  # held may be from before that rebuild's write, which a render job that
  # carries the write would read (`ensure_fresh/1`), and the rebuild may
  # still be reading. The next read fills it from the database.
  #
  # It reads unscoped, a fill as a rebuild: the cache is every visitor's, not
  # what the user whose request found it cold may read. Under that user's
  # groups a menu they may not read would leave every visitor's pages
  # without it until the next save.
  defp store(cache, generation) do
    values = Boundary.with_scope(nil, fn -> Map.fetch!(@site_caches, cache).load() end)
    if get(generation_key(cache)) == generation, do: keep(cache, values, generation), else: withdraw(values)
    values
  end

  defp keep(cache, values, generation) do
    Enum.each(values, fn {key, value} -> put(key, value, :infinite) end)
    if get(generation_key(cache)) != generation, do: withdraw(values)
  end

  defp withdraw(values), do: Enum.each(values, fn {key, _} -> del(key) end)

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
  renders read, a query cache source they list, or the site and environment
  registry (`Brando.Tenant.Cache`), which names the hosts their URLs start with. The job may run on a
  node that has not heard of the write that queued it yet, and would render
  from what its caches held before. The job carries a token for each write
  the queuing node had refreshed for (`Brando.Content.RenderQueue.enqueue/2`),
  and this node refreshes for any token it does not know.
  """
  @spec ensure_fresh(map()) :: :ok
  def ensure_fresh(args) do
    # One refresh per input, however many tokens a coalesced job carries for it
    for {input, unknown} <- Enum.group_by(Freshness.unknown(args), &elem(&1, 0), &elem(&1, 1)) do
      refresh(input)
      Enum.each(unknown, &Freshness.known(input, &1))
    end

    :ok
  end

  @doc """
  Refreshes this node's render inputs for the caller's site and environment,
  whatever it has heard, as a render job does for a write it has not heard
  of (`ensure_fresh/1`): rebuilds the site caches entries render with and
  evicts the cached lists of modules, containers, palettes and fragments.
  With `registry: true`, warms the site and environment registry too. For a
  run that renders many entries after writes no node may have heard of.
  """
  @spec refresh_render_inputs(keyword()) :: :ok
  def refresh_render_inputs(opts \\ []) do
    args = Freshness.attach_any(%{})
    ensure_fresh(if opts[:registry], do: args, else: Map.delete(args, "registry"))
  end

  defp refresh({:site_cache, cache}), do: rebuild(cache)
  defp refresh(:registry), do: Tenant.Cache.warm()
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
