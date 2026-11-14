defmodule Brando.Assets.SiteAssets do
  @moduledoc """
  Registry and runtime cache for persistent, uploadable frontend asset sets.

  Standalone installations use `site_assets/sets/{set}`. Multi-site
  installations use `sites/{site_key}/assets/sets/{set}`. The first request
  after an activation caches the active set's complete regular-file listing as
  a `MapSet` and its optional Vite manifest in `:persistent_term`, making
  non-matching request rejection a memory lookup with no filesystem access.

  An environment may have a set of its own (`environments.asset_set_id`).
  Which set an environment uses resolves like its frontend module
  (`Brando.Site.Frontend.current/0`):

    1. the environment's own set, when it has one;
    2. else its site's active set (in `:single`, the standalone active set);
    3. else the release's `priv/static`.

  `activate_environment_set/2` and `clear_environment_set/1` set and clear an
  environment's own set. The `active` flag on a set keeps meaning the site's
  set.

  Shared previews pin the set they were rendered against (see
  `with_preview_set/2` and `Brando.Assets.SiteAssets.Capture`). A pinned set
  keeps serving its content-addressed build output at the original URLs until
  the last preview that references it expires, so a later activation or release
  cannot break a link that has already been shared. `Brando.Assets.SiteAssets.Retention`
  owns the pruning rules that protect those sets.

  A host that belongs to no site in `:multi` (the admin's, where live and
  shared previews are served) gets what each site's own host would send,
  for the paths the sites do not disagree on (`unscoped_path/1`). A host
  that resolves to an environment gets, for a path its own sets miss, the
  file of another environment's own set in the same site
  (`other_environment_path/3`), where previews of that environment are shown.

  The caches are per node: activating or deactivating a set, pinning or
  releasing one, and forgetting one refresh this node and tell the others
  through `Brando.CacheSync`. A request that filled a cache from what it read
  before such a change drops what it stored, so the change is not undone.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Assets.DevSite
  alias Brando.Assets.SiteAssets.Capture
  alias Brando.Assets.SiteAssets.Retention
  alias Brando.Assets.SiteAssetSet
  alias Brando.CacheSync
  alias Brando.Environments.Environment
  alias Brando.Repo
  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Tenant.Lock
  alias Brando.Tenant.Registry
  alias Brando.Tenant.Storage

  @public_opts [prefix: "public"]
  @cache_keys_key {:brando, :site_assets, :cache_keys}
  @override_key {:brando, :site_assets, :override}
  @change_fence_key {:brando, :site_assets, :change_fence}
  @fence_key {:brando, :site_assets, :fence}
  @unscoped_key {:brando, :site_assets, :unscoped}
  @environment_index_key {:brando, :site_assets, :environment_index}

  @type scope :: Site.t() | nil
  @type environment_ref :: Environment.t() | pos_integer() | {String.t(), String.t()}
  @type cached_set :: %{
          set: SiteAssetSet.t(),
          path: String.t(),
          files: MapSet.t(String.t()),
          pinned: MapSet.t(String.t()),
          manifest: map() | nil
        }

  @doc "Registers an uploaded standalone set without activating it."
  @spec register_set(String.t(), map()) :: {:ok, SiteAssetSet.t()} | {:error, term()}
  def register_set(path, metadata \\ %{}) when is_binary(path) and is_map(metadata) do
    register(nil, path, metadata)
  end

  @doc "Registers an uploaded set for one site without activating it."
  @spec register_set(Site.t() | String.t(), String.t(), map()) ::
          {:ok, SiteAssetSet.t()} | {:error, term()}
  def register_set(%Site{} = site, path, metadata) when is_binary(path) and is_map(metadata) do
    register(site, path, metadata)
  end

  def register_set(nil, path, metadata) when is_binary(path) and is_map(metadata) do
    register(nil, path, metadata)
  end

  def register_set(site_key, path, metadata)
      when is_binary(site_key) and is_binary(path) and is_map(metadata) do
    case Registry.get_site_by_key(site_key) do
      %Site{} = site -> register(site, path, metadata)
      nil -> {:error, :site_not_found}
    end
  end

  @doc "Lists registered sets newest first for a standalone or site scope."
  @spec list_sets(scope()) :: [SiteAssetSet.t()]
  def list_sets(site \\ nil) do
    site
    |> scope_query()
    |> then(&from(asset_set in &1, order_by: [desc: asset_set.uploaded_at, desc: asset_set.id]))
    |> Repo.all(@public_opts)
  end

  @doc "Returns the persisted active set for a scope."
  @spec active_set(scope()) :: SiteAssetSet.t() | nil
  def active_set(site \\ nil) do
    site
    |> scope_query()
    |> then(&from(asset_set in &1, where: asset_set.active))
    |> Repo.one(@public_opts)
  end

  @doc "Activates a registered set and atomically deactivates its predecessor."
  @spec activate_set(pos_integer()) :: {:ok, SiteAssetSet.t()} | {:error, term()}
  def activate_set(set_id) do
    # A set whose files cannot be read is not activated
    with %SiteAssetSet{} = asset_set <- Repo.get(SiteAssetSet, set_id, @public_opts),
         {:ok, _cached} <- build_cache(asset_set),
         {:ok, active_set} <- persist_activation(asset_set) do
      active_changed(scope_key(active_set))
      {:ok, active_set}
    else
      nil -> {:error, :asset_set_not_found}
      {:error, _reason} = error -> error
    end
  end

  @doc "Deactivates uploaded assets for a scope and restores release fallback."
  @spec deactivate(scope()) :: :ok | {:error, term()}
  def deactivate(site \\ nil) do
    case Repo.transaction(fn ->
           site
           |> scope_query()
           |> Repo.update_all([set: [active: false]], @public_opts)
         end) do
      {:ok, _updated} ->
        active_changed(scope_key(site))
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  The set an environment has of its own, or nil when it follows its site's
  active set.
  """
  @spec environment_set(Environment.t() | nil) :: SiteAssetSet.t() | nil
  def environment_set(nil), do: nil

  def environment_set(%Environment{id: environment_id}) do
    from(environment in Environment,
      join: asset_set in SiteAssetSet,
      on: asset_set.id == environment.asset_set_id,
      where: environment.id == ^environment_id,
      select: asset_set
    )
    |> Repo.one(@public_opts)
  end

  @doc """
  The persisted set an environment of `site` uses: its own set, else the
  scope's active set, else nil (the release's `priv/static`). Pass a nil
  environment for the scope's active set alone.
  """
  @spec effective_set(scope(), Environment.t() | nil) :: SiteAssetSet.t() | nil
  def effective_set(site, environment), do: environment_set(environment) || active_set(site)

  @doc """
  Makes a registered set the environment's own, in place of its site's
  active set. The set must belong to the environment's site (in `:single`,
  be a standalone set). Every node's cache follows (`refresh_node_cache/1`).

  `environment` is an environment, its id, or `{site_key, environment_key}`.
  """
  @spec activate_environment_set(pos_integer(), environment_ref()) ::
          {:ok, Environment.t()} | {:error, term()}
  def activate_environment_set(set_id, environment) do
    with {:ok, environment} <- fetch_environment(environment),
         {:ok, asset_set} <- fetch_set(set_id),
         :ok <- check_environment_scope(asset_set, environment),
         {:ok, _cached} <- build_cache(asset_set) do
      # Under the set's lock, so `Retention` cannot delete it meanwhile
      Lock.with(lock_key(asset_set), fn -> persist_registered_set(environment, set_id) end)
    end
  end

  defp persist_registered_set(environment, set_id) do
    with {:ok, _still_registered} <- fetch_set(set_id), do: persist_environment_set(environment, set_id)
  end

  @doc """
  Clears the environment's own set, so it follows its site's active set
  again. The set stays registered. Every node's cache follows.
  """
  @spec clear_environment_set(environment_ref()) :: {:ok, Environment.t()} | {:error, term()}
  def clear_environment_set(environment) do
    with {:ok, environment} <- fetch_environment(environment) do
      persist_environment_set(environment, nil)
    end
  end

  @doc """
  Drops every node's cached set for an environment whose own set went away
  without `clear_environment_set/1`: the environment was deleted.
  """
  @spec forget_environment(Environment.t()) :: :ok
  def forget_environment(%Environment{} = environment), do: environment_changed(environment)

  @doc "Returns the cached active-set information, warming it on first use."
  @spec cached(scope()) :: cached_set() | nil
  def cached(site \\ nil) do
    key = cache_key(scope_key(site))

    case :persistent_term.get(key, :not_cached) do
      :not_cached -> warm_scope(site)
      :none -> nil
      cached -> cached
    end
  end

  @doc """
  Returns cached file, pinned-file, and manifest information for any registered
  set, active or not. The listing is scanned once and kept in `:persistent_term`
  until `forget_set/1` or `invalidate_cache/0` runs.
  """
  @spec set_cache(SiteAssetSet.t()) :: {:ok, cached_set()} | {:error, term()}
  def set_cache(%SiteAssetSet{} = asset_set), do: set_cache_since(asset_set, change_fence())

  # `fence` is from before the caller read `asset_set` from the database: a
  # pinned listing passes its own, so a set forgotten since is not stored
  defp set_cache_since(%SiteAssetSet{id: id} = asset_set, fence) do
    key = set_cache_key(id)

    case :persistent_term.get(key, :not_cached) do
      :not_cached ->
        with {:ok, cached} <- build_cache(asset_set), do: {:ok, fill(key, cached, fence)}

      cached ->
        {:ok, cached}
    end
  end

  @doc "Drops the runtime caches for one set, including the pinned listing of its scope."
  @spec forget_set(SiteAssetSet.t()) :: :ok
  def forget_set(%SiteAssetSet{id: id} = asset_set) do
    drop_set(id)
    CacheSync.broadcast(__MODULE__, {:set, id})
    invalidate_pinned(asset_set)
  end

  @doc """
  Resolves the immutable set a shared preview must be pinned to and runs `fun`
  with that set installed as the process-local asset source.

  The scope's advisory lock is held for the whole call, so pruning cannot
  remove the set while the preview is being captured, rendered, or saved. The
  set is the one `environment` uses (`effective_set/2`) when it is
  self-contained; otherwise the
  effective release build is captured into a registered set first. Templates
  rendered inside `fun` read the pinned manifest and critical CSS even if
  another set is activated concurrently.
  """
  @spec with_preview_set(scope(), Environment.t() | nil, (SiteAssetSet.t() -> result)) ::
          {:ok, result} | {:error, term()}
        when result: var
  def with_preview_set(site \\ nil, environment \\ nil, fun) when is_function(fun, 1) do
    Lock.with(lock_key(site), fn -> pin_and_run(site, environment, fun) end)
  end

  defp pin_and_run(site, environment, fun) do
    with {:ok, asset_set} <- Capture.ensure_set(site, environment),
         {:ok, cached} <- set_cache(asset_set) do
      with_override(cached, fn -> fun.(asset_set) end)
    end
  end

  @doc "Runs `fun` with `asset_set` as the process-local manifest and file source."
  @spec with_set(SiteAssetSet.t(), (-> result)) :: {:ok, result} | {:error, term()} when result: var
  def with_set(%SiteAssetSet{} = asset_set, fun) when is_function(fun, 0) do
    with {:ok, cached} <- set_cache(asset_set), do: with_override(cached, fun)
  end

  @doc "Returns the process-local set installed by `with_set/2`, if any."
  @spec override() :: cached_set() | nil
  def override, do: Process.get(@override_key)

  @doc """
  Resolves a request path to a file in the set `environment` uses (its own,
  else the scope's active set) or, failing that, in a set pinned by an
  unexpired shared preview for the same scope. Pinned lookups
  only cover the content-addressed files listed in a set's Vite manifest, so an
  old set never shadows un-hashed files such as favicons.

  The development site (`Brando.Assets.DevSite`) skips its sets, its
  environments' own included, so the release's files answer as they do for
  the Vite dev server's page, and a pinned set answers it only for a path the
  release lacks.
  """
  @spec serve_path(scope(), Environment.t() | nil, String.t()) :: String.t() | nil
  def serve_path(site, environment \\ nil, relative_path) when is_binary(relative_path) do
    active_file(site, environment, relative_path) || pinned_file(site, relative_path)
  end

  @doc """
  Resolves a request path on a host that belongs to no site, in `:multi` the
  admin's host, which serves live previews and shared previews.

  Per site, the candidate is the file its own host would send: any file of
  its active set (the development site's excepted, as in `serve_path/3`),
  else a manifest file of a set an unexpired shared preview pins. Each
  environment with a set of its own holds a candidate of its own beside its
  site's: any file of that set. The path answers when one holder has it, or
  when every holder that has it holds the same content; when their contents
  differ it stays unanswered, as nothing tells which site's or environment's
  preview asked. A path the release's `priv/static` holds
  is left to it.

  Sites that are suspended or archived neither answer nor count towards
  that comparison, as the admin lets no one preview such a site. Their
  status is read per request, so it takes effect without a cache drop.

  The paths of every set are cached together, with the contents of the paths
  more than one site has compared when the cache is filled, so a miss is
  rejected without touching the filesystem. The cache is dropped with the
  active, pinned and set caches, on every node.
  """
  @spec unscoped_path(String.t()) :: String.t() | nil
  def unscoped_path(relative_path) when is_binary(relative_path) do
    with [_ | _] = candidates <- Map.get(unscoped_index(), relative_path, []),
         false <- File.regular?(Path.join(Capture.release_root(), relative_path)) do
      candidates
      |> Enum.filter(&previewable?/1)
      |> agreed_file()
    else
      _miss -> nil
    end
  end

  @doc """
  Resolves a request path that `serve_path/3` left unanswered on a host that
  resolves to `environment`, from the own sets of the other environments of
  its scope: in `:multi` its site's, in `:single` the installation's. Never
  another site's.

  A live preview of an environment with a set of its own, and a shared
  preview from one, are shown on a host that resolves to another
  environment of the site (the admin's host in `:single`, a site's own host
  in `:multi`), and their pages name that set's files host-relative.

  The path answers when one other environment's set holds it, or when every
  one that holds it holds the same content, compared as `unscoped_path/1`
  compares. A path the release's `priv/static` holds is left to it, and the
  development site (`Brando.Assets.DevSite`) gets nothing here, as its
  environments read no set.

  The paths of every environment's own set are cached together, so a miss is
  rejected without a query or a filesystem lookup. The cache is dropped with
  the active, environment, pinned and set caches, on every node.
  """
  @spec other_environment_path(scope(), Environment.t() | nil, String.t()) :: String.t() | nil
  def other_environment_path(_site, nil, _relative_path), do: nil

  def other_environment_path(site, %Environment{id: environment_id, site_id: site_id}, relative_path)
      when is_binary(relative_path) do
    with [_ | _] = candidates <- environment_index() |> Map.get(site_id, %{}) |> Map.get(relative_path, []),
         [_ | _] = others <- Enum.reject(candidates, &match?({^environment_id, _file, _content}, &1)),
         false <- DevSite.dev_site?(site),
         false <- File.regular?(Path.join(Capture.release_root(), relative_path)) do
      agreed_file(others)
    else
      _miss -> nil
    end
  end

  @doc "Returns cached information for every set still pinned by a preview in the scope."
  @spec pinned_sets(scope()) :: [cached_set()]
  def pinned_sets(site \\ nil) do
    key = pinned_cache_key(scope_key(site))

    case :persistent_term.get(key, :not_cached) do
      :not_cached -> warm_pinned(site)
      pinned -> pinned
    end
  end

  @doc "Clears the pinned-set listing for a scope so the next request rebuilds it."
  @spec invalidate_pinned(scope() | SiteAssetSet.t()) :: :ok
  def invalidate_pinned(scope \\ nil) do
    drop_pinned(scope_key(scope))
    CacheSync.broadcast(__MODULE__, {:pinned, scope_key(scope)})
  end

  @doc """
  Drops this node's copy of what another node changed (`Brando.CacheSync`):
  a scope's active set (and its Vite manifest and critical CSS), an
  environment's own set (and the Vite manifest and critical CSS of its
  prefix), a scope's pinned sets, or a removed set. Each is read again on its
  next use.
  """
  @spec refresh_node_cache(
          {:active | :pinned, :standalone | {:site_id, pos_integer()}}
          | {:set, pos_integer()}
          | {:environment, pos_integer(), String.t() | nil}
        ) :: :ok
  def refresh_node_cache({:active, scope_key}), do: drop_active(scope_key)
  def refresh_node_cache({:environment, environment_id, prefix}), do: drop_environment(environment_id, prefix)

  def refresh_node_cache({:pinned, scope_key}), do: drop_pinned(scope_key)
  def refresh_node_cache({:set, set_id}), do: drop_set(set_id)

  @doc "The advisory-lock key serializing capture, activation-sensitive pinning, and pruning."
  @spec lock_key(scope() | SiteAssetSet.t()) :: String.t()
  def lock_key(scope) do
    case scope_key(scope) do
      :standalone -> "site-assets:standalone"
      {:site_id, site_id} -> "site-assets:#{site_id}"
    end
  end

  @doc "Lists every output file a Vite manifest references: entries, chunks, CSS, and assets."
  @spec manifest_files(map() | nil) :: [String.t()]
  def manifest_files(nil), do: []

  def manifest_files(manifest) when is_map(manifest) do
    manifest
    |> Map.values()
    |> Enum.filter(&is_map/1)
    |> Enum.flat_map(fn entry ->
      [Map.get(entry, "file") | List.wrap(Map.get(entry, "css")) ++ List.wrap(Map.get(entry, "assets"))]
    end)
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  @doc "Warms every persisted active set. Safe to call during application boot."
  @spec warm() :: :ok
  def warm do
    invalidate_cache()
    # Filled like any read: CacheSync is already listening when this runs at
    # boot, and an activation it hears meanwhile must not be overwritten
    fence = change_fence()

    from(asset_set in SiteAssetSet, where: asset_set.active)
    |> Repo.all(@public_opts)
    |> Enum.each(fn asset_set ->
      case build_cache(asset_set) do
        {:ok, cached} -> fill(cache_key(scope_key(asset_set)), cached, fence)
        {:error, _reason} -> fill(cache_key(scope_key(asset_set)), :none, fence)
      end
    end)

    :ok
  rescue
    _migration_not_applied_yet -> :ok
  end

  @doc "Clears all active-set runtime caches."
  @spec invalidate_cache() :: :ok
  def invalidate_cache do
    move_change_fence()

    @cache_keys_key
    |> :persistent_term.get([])
    |> Enum.each(&:persistent_term.erase/1)

    :persistent_term.erase(@cache_keys_key)
    move_fence()
  end

  @doc """
  Returns the Vite manifest of the process-local override set or, without one,
  of the set the current environment uses (`serve_path/3`). The development site
  (`Brando.Assets.DevSite`) has no active set here, nor in `current_file/1`
  and `current_root/0`.
  """
  @spec current_manifest() :: map() | nil
  def current_manifest do
    case override() do
      %{manifest: manifest} -> manifest
      nil -> current_cached() |> cached_value(:manifest)
    end
  end

  @doc "Resolves a regular file within the override set or the set the current environment uses."
  @spec current_file(String.t()) :: String.t() | nil
  def current_file(relative_path) when is_binary(relative_path) do
    with %{files: files, path: root} <- override() || current_cached(),
         normalized when is_binary(normalized) <- normalize_relative_path(relative_path),
         true <- MapSet.member?(files, normalized) do
      Path.join(root, normalized)
    else
      _ -> nil
    end
  end

  @doc "Returns the root of the override set or the set the current environment uses, for static export tooling."
  @spec current_root() :: String.t() | nil
  def current_root do
    case override() do
      %{path: path} -> path
      nil -> current_cached() |> cached_value(:path)
    end
  end

  @doc """
  The environment of the current process's tenant prefix, in `:multi` and
  `:single`; nil without one, and in `:none`.
  """
  @spec current_environment() :: Environment.t() | nil
  def current_environment do
    with true <- Tenant.enabled?(),
         site_key when is_binary(site_key) <- Tenant.current_site_key(),
         environment_key when is_binary(environment_key) <- Tenant.current_environment_key() do
      Brando.Tenant.Cache.get_env(site_key, environment_key)
    else
      _no_environment -> nil
    end
  end

  @doc """
  Resolves the scope of the current process: the tenant site in multi-site
  mode, `nil` for standalone installations, and `:error` without site context.
  """
  @spec current_scope() :: {:ok, scope()} | :error
  def current_scope do
    case Tenant.mode() do
      :multi ->
        with site_key when is_binary(site_key) <- Tenant.current_site_key(),
             site when not is_nil(site) <- Brando.Tenant.Cache.get_site(site_key) do
          {:ok, site}
        else
          _missing_context -> :error
        end

      _standalone ->
        {:ok, nil}
    end
  end

  @doc "Returns the configured standalone asset-set storage root."
  def standalone_root do
    Brando.config(:site_assets_path) || Path.join(Storage.media_parent(), "site_assets")
  end

  @doc "Returns the asset-set storage root for a standalone or site scope."
  def sets_root(nil), do: Path.join(standalone_root(), "sets")
  def sets_root(%Site{} = site), do: Path.join(Storage.assets_root(site), "sets")

  defp register(site, path, metadata) do
    with {:ok, normalized_path} <- validate_set_path(site, path),
         {:ok, files, size} <- scan_files(normalized_path) do
      attrs = %{
        site_id: site_id(site),
        name: Path.basename(normalized_path),
        path: normalized_path,
        active: false,
        uploaded_at: uploaded_at(metadata),
        size: size,
        file_count: MapSet.size(files),
        metadata: stringify_metadata(metadata)
      }

      %SiteAssetSet{}
      |> SiteAssetSet.changeset(attrs)
      |> Repo.insert(@public_opts)
    end
  end

  defp validate_set_path(site, path) do
    expanded_path = Path.expand(path)
    expected_parent = site |> sets_root() |> Path.expand()

    cond do
      Path.dirname(expanded_path) != expected_parent ->
        {:error, {:invalid_asset_set_path, expanded_path, expected_parent}}

      not File.dir?(expanded_path) ->
        {:error, {:asset_set_directory_not_found, expanded_path}}

      true ->
        {:ok, expanded_path}
    end
  end

  defp scan_files(root), do: scan_directory(root, root, MapSet.new(), 0)

  defp scan_directory(root, directory, files, size) do
    case File.ls(directory) do
      {:ok, entries} ->
        Enum.reduce_while(entries, {:ok, files, size}, &scan_entry(root, directory, &1, &2))

      {:error, reason} ->
        {:error, {:asset_directory_scan_failed, directory, reason}}
    end
  end

  defp scan_entry(root, directory, entry, {:ok, files, size}) do
    path = Path.join(directory, entry)

    case File.lstat(path) do
      {:ok, %{type: :directory}} ->
        continue_scan(scan_directory(root, path, files, size))

      {:ok, %{type: :regular, size: file_size}} ->
        relative_path = Path.relative_to(path, root)
        {:cont, {:ok, MapSet.put(files, relative_path), size + file_size}}

      {:ok, _symlink_or_special} ->
        {:halt, {:error, {:unsupported_asset_file, path}}}

      {:error, reason} ->
        {:halt, {:error, {:asset_file_stat_failed, path, reason}}}
    end
  end

  defp continue_scan({:ok, files, size}), do: {:cont, {:ok, files, size}}
  defp continue_scan({:error, reason}), do: {:halt, {:error, reason}}

  defp build_cache(%SiteAssetSet{} = asset_set) do
    with {:ok, files, _size} <- scan_files(asset_set.path),
         {:ok, manifest} <- read_manifest(asset_set.path) do
      {:ok,
       %{
         set: asset_set,
         path: asset_set.path,
         files: files,
         pinned: pinned_files(files, manifest),
         manifest: manifest
       }}
    end
  end

  # Only content-addressed build output may be served from a pinned set. Source
  # maps sit beside their hashed owners, so they are pinned when present.
  defp pinned_files(files, manifest) do
    manifest
    |> manifest_files()
    |> Enum.flat_map(&[&1, &1 <> ".map"])
    |> MapSet.new()
    |> MapSet.intersection(files)
  end

  defp active_file(site, environment, relative_path) do
    case effective_cached(site, environment) do
      %{files: files, path: root} ->
        if MapSet.member?(files, relative_path), do: Path.join(root, relative_path)

      nil ->
        nil
    end
  end

  # A build may name a manifest file without a hash: for the development
  # site, a pinned set (perhaps its active one) must not shadow the release
  # file its pages get
  defp pinned_file(site, relative_path) do
    if DevSite.dev_site?(site) and File.regular?(Path.join(Capture.release_root(), relative_path)),
      do: nil,
      else: find_pinned_file(site, relative_path)
  end

  defp find_pinned_file(site, relative_path) do
    site
    |> pinned_sets()
    |> Enum.find_value(fn %{pinned: pinned, path: root} ->
      if MapSet.member?(pinned, relative_path), do: Path.join(root, relative_path)
    end)
  end

  defp warm_pinned(site) do
    fence = change_fence()
    fill(pinned_cache_key(scope_key(site)), load_pinned(site, fence), fence)
  end

  defp load_pinned(site, fence) do
    site
    |> Retention.preview_pinned_sets()
    |> Enum.flat_map(fn asset_set ->
      case set_cache_since(asset_set, fence) do
        {:ok, cached} -> [cached]
        {:error, _reason} -> []
      end
    end)
  rescue
    _migration_not_applied_yet -> []
  end

  defp unscoped_index do
    case :persistent_term.get(@unscoped_key, :not_cached) do
      :not_cached -> warm_unscoped()
      index -> index
    end
  end

  # Not stored when it fails to load (a pool timeout, the migration not run
  # yet): the next request loads it again
  defp warm_unscoped do
    fence = change_fence()

    case load_unscoped(fence) do
      {:ok, index} -> fill(@unscoped_key, index, fence)
      :error -> %{}
    end
  end

  # Path => [{holder, file, content}], one candidate per holder: a site
  # (`{site_key, nil}`) or an environment with a set of its own
  # (`{site_key, environment_id}`), from every site's active, preview-pinned
  # and environment sets. `content` is nil for a path one holder has, else
  # what tells two candidates' contents apart.
  defp load_unscoped(fence) do
    pinned_ids = Retention.preview_pinned_set_ids()
    environment_sets = environment_set_rows()
    environment_set_ids = Enum.map(environment_sets, &elem(&1, 2))

    index =
      from(asset_set in SiteAssetSet,
        join: site in Site,
        on: site.id == asset_set.site_id,
        where:
          asset_set.active or asset_set.id in ^MapSet.to_list(pinned_ids) or
            asset_set.id in ^environment_set_ids,
        order_by: [desc: asset_set.uploaded_at, desc: asset_set.id],
        select: {site.key, asset_set}
      )
      |> Repo.all(@public_opts)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.flat_map(fn {site_key, sets} ->
        cached = cache_sets(sets, fence)
        site_holder = {{site_key, nil}, site_files(site_key, cached, pinned_ids)}

        environment_holders =
          for {^site_key, environment_id, set_id} <- environment_sets,
              not DevSite.dev_site?(site_key),
              %{files: paths, path: root} <- [cached_by_id(cached, set_id)],
              do: {{site_key, environment_id}, Map.new(paths, &{&1, Path.join(root, &1)})}

        [site_holder | environment_holders]
      end)
      |> Enum.reduce(%{}, fn {holder, files}, index ->
        Enum.reduce(files, index, fn {path, file}, index ->
          Map.update(index, path, [{holder, file}], &[{holder, file} | &1])
        end)
      end)
      |> Map.new(fn {path, candidates} -> {path, with_content(candidates)} end)

    {:ok, index}
  rescue
    _unavailable -> :error
  end

  # {site_key, environment_id, set_id} for every environment with a set of its own
  defp environment_set_rows do
    from(environment in Environment,
      join: site in Site,
      on: site.id == environment.site_id,
      where: not is_nil(environment.asset_set_id),
      select: {site.key, environment.id, environment.asset_set_id}
    )
    |> Repo.all(@public_opts)
  end

  defp environment_index do
    case :persistent_term.get(@environment_index_key, :not_cached) do
      :not_cached -> warm_environment_index()
      index -> index
    end
  end

  # Not stored when it fails to load, as `warm_unscoped/0`
  defp warm_environment_index do
    fence = change_fence()

    case load_environment_index(fence) do
      {:ok, index} -> fill(@environment_index_key, index, fence)
      :error -> %{}
    end
  end

  # Site id => path => [{environment_id, file, content}], from the own set of
  # every environment that has one; `content` as in `load_unscoped/1`. Read
  # from the database as that is, so a lookup that fails stores nothing
  defp load_environment_index(fence) do
    rows =
      Repo.all(
        from(environment in Environment,
          where: not is_nil(environment.asset_set_id),
          select: {environment.site_id, environment.id, environment.asset_set_id}
        ),
        @public_opts
      )

    cached =
      from(asset_set in SiteAssetSet, where: asset_set.id in ^Enum.map(rows, &elem(&1, 2)))
      |> Repo.all(@public_opts)
      |> cache_sets(fence)

    holders =
      for {site_id, environment_id, set_id} <- rows,
          %{files: paths, path: root} <- [cached_by_id(cached, set_id)],
          path <- paths,
          do: {{site_id, path}, {environment_id, Path.join(root, path)}}

    index =
      holders
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.reduce(%{}, fn {{site_id, path}, candidates}, index ->
        candidates = with_content(candidates)
        Map.update(index, site_id, %{path => candidates}, &Map.put(&1, path, candidates))
      end)

    {:ok, index}
  rescue
    _unavailable -> :error
  end

  defp cache_sets(sets, fence) do
    Enum.flat_map(sets, fn asset_set ->
      case set_cache_since(asset_set, fence) do
        {:ok, cached} -> [{asset_set, cached}]
        {:error, _reason} -> []
      end
    end)
  end

  defp cached_by_id(cached, set_id) do
    Enum.find_value(cached, fn {asset_set, set_cached} -> if asset_set.id == set_id, do: set_cached end)
  end

  # Path => file, as `serve_path/3` resolves it for the site's own host when
  # the environment has no set of its own: its active set first, then its
  # pinned sets in `pinned_sets/1` order
  defp site_files(site_key, cached, pinned_ids) do
    pinned =
      for {asset_set, %{pinned: paths, path: root}} <- Enum.reverse(cached),
          MapSet.member?(pinned_ids, asset_set.id),
          path <- paths,
          into: %{},
          do: {path, Path.join(root, path)}

    active =
      for {%SiteAssetSet{active: true}, %{files: paths, path: root}} <- cached,
          not DevSite.dev_site?(site_key),
          path <- paths,
          into: %{},
          do: {path, Path.join(root, path)}

    Map.merge(pinned, active)
  end

  defp with_content([{holder, file}]), do: [{holder, file, nil}]

  # The size, and a digest only where another candidate has the same size
  defp with_content(candidates) do
    sized = Enum.map(candidates, fn {holder, file} -> {holder, file, file_size(file)} end)
    sizes = Enum.frequencies_by(sized, &elem(&1, 2))

    Enum.map(sized, fn {holder, file, size} ->
      if is_integer(size) and sizes[size] > 1,
        do: {holder, file, {size, digest(file)}},
        else: {holder, file, {size, nil}}
    end)
  end

  defp file_size(file) do
    case File.stat(file) do
      {:ok, %File.Stat{size: size}} -> size
      {:error, _reason} -> {:unreadable, file}
    end
  end

  defp digest(file) do
    file
    |> File.stream!(65_536)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
  rescue
    File.Error -> {:unreadable, file}
  end

  defp previewable?({{site_key, _environment_id}, _file, _content}),
    do: match?(%Site{status: :active}, Brando.Tenant.Cache.get_site(site_key))

  defp agreed_file([{_holder, file, content} | others]) do
    if Enum.all?(others, &(elem(&1, 2) == content)), do: file
  end

  defp agreed_file([]), do: nil

  defp with_override(cached, fun) do
    previous = Process.get(@override_key)
    Process.put(@override_key, cached)

    try do
      {:ok, fun.()}
    after
      if previous, do: Process.put(@override_key, previous), else: Process.delete(@override_key)
    end
  end

  defp current_cached do
    case current_scope() do
      {:ok, site} -> effective_cached(site, current_environment())
      :error -> nil
    end
  end

  # The environment's own set, else the scope's active set. The development
  # site has neither: every environment of it loads from the Vite dev server.
  defp effective_cached(site, environment) do
    cond do
      DevSite.dev_site?(site) -> nil
      cached = environment_cached(environment) -> cached
      true -> cached(site)
    end
  end

  # The cached own set of the environment, or nil when it has none or its
  # files cannot be read: it then follows its site's set
  defp environment_cached(nil), do: nil

  defp environment_cached(%Environment{id: environment_id}) do
    case :persistent_term.get(environment_cache_key(environment_id), :not_cached) do
      :not_cached -> warm_environment(environment_id)
      :none -> nil
      cached -> cached
    end
  end

  defp warm_environment(environment_id) do
    fence = change_fence()

    case fill(environment_cache_key(environment_id), load_environment(environment_id), fence) do
      :none -> nil
      cached -> cached
    end
  rescue
    _migration_not_applied_yet -> nil
  end

  defp load_environment(environment_id) do
    with %SiteAssetSet{} = asset_set <- environment_set(%Environment{id: environment_id}),
         {:ok, cached} <- build_cache(asset_set) do
      cached
    else
      _none_or_unreadable -> :none
    end
  end

  defp fetch_set(set_id) do
    case Repo.get(SiteAssetSet, set_id, @public_opts) do
      %SiteAssetSet{} = asset_set -> {:ok, asset_set}
      nil -> {:error, :asset_set_not_found}
    end
  end

  defp fetch_environment(%Environment{id: environment_id}), do: fetch_environment(environment_id)

  defp fetch_environment({site_key, environment_key}) when is_binary(site_key) and is_binary(environment_key) do
    with %Site{} = site <- Registry.get_site_by_key(site_key),
         %Environment{} = environment <- Registry.get_environment_by_key(site, environment_key) do
      {:ok, environment}
    else
      nil -> {:error, :environment_not_found}
    end
  end

  defp fetch_environment(environment_id) when is_integer(environment_id) do
    case Registry.get_environment(environment_id) do
      %Environment{} = environment -> {:ok, environment}
      nil -> {:error, :environment_not_found}
    end
  end

  defp fetch_environment(_unknown), do: {:error, :environment_not_found}

  # An environment uses a set of its own site; in `:single`, a standalone set
  defp check_environment_scope(%SiteAssetSet{site_id: set_site_id}, %Environment{site_id: site_id}) do
    expected_site_id =
      case Tenant.mode() do
        :multi -> site_id
        :single -> nil
        :none -> :no_environments
      end

    if set_site_id == expected_site_id, do: :ok, else: {:error, :asset_set_belongs_to_another_site}
  end

  defp persist_environment_set(%Environment{id: environment_id} = environment, set_id) do
    Repo.transaction(fn ->
      from(row in Environment, where: row.id == ^environment_id, select: row)
      |> Repo.update_all([set: [asset_set_id: set_id, updated_at: DateTime.utc_now()]], @public_opts)
      |> case do
        {1, [updated]} ->
          environment_changed(environment)
          Tenant.Cache.invalidate()
          updated

        {0, []} ->
          Repo.rollback(:environment_not_found)
      end
    end)
  end

  defp read_manifest(root) do
    path = Path.join(root, "manifest.json")

    case File.read(path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, manifest} -> {:ok, manifest}
          {:error, reason} -> {:error, {:invalid_asset_manifest, path, reason}}
        end

      {:error, :enoent} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, {:asset_manifest_read_failed, path, reason}}
    end
  end

  defp persist_activation(asset_set) do
    Repo.transaction(fn ->
      asset_set
      |> scope_query_for_set()
      |> Repo.update_all([set: [active: false]], @public_opts)

      asset_set
      |> SiteAssetSet.changeset(%{active: true})
      |> Repo.update(@public_opts)
      |> case do
        {:ok, active_set} -> active_set
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp warm_scope(site) do
    fence = change_fence()

    case fill(cache_key(scope_key(site)), load_active(site), fence) do
      :none -> nil
      cached -> cached
    end
  rescue
    _migration_not_applied_yet -> nil
  end

  defp load_active(site) do
    with %SiteAssetSet{} = asset_set <- active_set(site),
         {:ok, cached} <- build_cache(asset_set) do
      cached
    else
      _none_or_unreadable -> :none
    end
  end

  defp scope_query(nil), do: from(asset_set in SiteAssetSet, where: is_nil(asset_set.site_id))

  defp scope_query(%Site{id: site_id}),
    do: from(asset_set in SiteAssetSet, where: asset_set.site_id == ^site_id)

  defp scope_query_for_set(%SiteAssetSet{site_id: nil}), do: scope_query(nil)

  defp scope_query_for_set(%SiteAssetSet{site_id: site_id}),
    do: from(asset_set in SiteAssetSet, where: asset_set.site_id == ^site_id)

  defp scope_key(%SiteAssetSet{site_id: nil}), do: :standalone
  defp scope_key(%SiteAssetSet{site_id: site_id}), do: {:site_id, site_id}
  defp scope_key(nil), do: :standalone
  defp scope_key(%Site{id: site_id}), do: {:site_id, site_id}

  defp cache_key(scope_key), do: {:brando, :site_assets, :active, scope_key}
  defp pinned_cache_key(scope_key), do: {:brando, :site_assets, :pinned, scope_key}
  defp set_cache_key(set_id), do: {:brando, :site_assets, :set, set_id}
  defp environment_cache_key(environment_id), do: {:brando, :site_assets, :environment, environment_id}

  # Dropped rather than replaced after a write, as two writes here may finish
  # in either order: the next read loads the one committed last. Inside a
  # transaction, once it commits: a fill here before then would read the set
  # it replaces and keep it.
  defp active_changed(scope_key) do
    Repo.after_commit({__MODULE__, :active, scope_key}, fn -> drop_active(scope_key) end)
    CacheSync.broadcast(__MODULE__, {:active, scope_key})
  end

  defp drop_active(scope_key) do
    drop(cache_key(scope_key))
    erase_indexes()
    invalidate_vite(scope_site_id(scope_key))
  end

  defp environment_changed(%Environment{id: environment_id} = environment) do
    prefix = environment_prefix(environment)

    Repo.after_commit({__MODULE__, :environment, environment_id}, fn ->
      drop_environment(environment_id, prefix)
    end)

    CacheSync.broadcast(__MODULE__, {:environment, environment_id, prefix})
  end

  defp drop_environment(environment_id, prefix) do
    drop(environment_cache_key(environment_id))
    erase_indexes()
    invalidate_vite_prefix(prefix)
  end

  defp environment_prefix(%Environment{site_id: site_id, key: environment_key}) do
    case Registry.get_site(site_id) do
      %Site{} = site -> Tenant.prefix(site.key, environment_key)
      nil -> nil
    end
  end

  defp drop_pinned(scope_key) do
    drop(pinned_cache_key(scope_key))
    erase_indexes()
  end

  defp drop_set(set_id) do
    drop(set_cache_key(set_id))
    erase_indexes()
  end

  # The listings built from the other caches: `unscoped_path/1`'s and
  # `other_environment_path/3`'s
  defp erase_indexes do
    erase(@unscoped_key)
    erase(@environment_index_key)
  end

  # A fill reads the database and the files, then stores `value`. Every change
  # moves the change fence before it erases, and a fill that finds it moved
  # since `fence`, taken before the read, withdraws what it stored: it may
  # have read before the change. Cached reads never look at a fence.
  defp fill(key, value, fence) do
    store(key, value)
    if change_fence() != fence, do: withdraw(key)
    value
  end

  # Not a change: moving the change fence would make the fills running now
  # withdraw theirs in turn, and under steady load none would ever stay. The
  # critical CSS read from the withdrawn set goes with it, as on a change.
  defp withdraw({:brando, :site_assets, :active, scope_key} = key) do
    erase(key)
    invalidate_vite(scope_site_id(scope_key))
  end

  defp withdraw({:brando, :site_assets, :environment, environment_id} = key) do
    erase(key)

    for site <- Tenant.Cache.list_sites(),
        %Environment{id: ^environment_id} = environment <- site.environments,
        do: invalidate_vite_prefix(Tenant.prefix(site, environment))

    :ok
  end

  defp withdraw(key), do: erase(key)

  defp drop(key) do
    move_change_fence()
    erase(key)
  end

  # The fence moves after the erase, so a cache filled from the erased value
  # either finds it moved or is erased itself by what follows
  defp erase(key) do
    :persistent_term.erase(key)
    move_fence()
  end

  @doc """
  A value that changes whenever a value in these caches is dropped. A cache
  filled from them, such as the critical CSS in `Brando.Assets.Vite.Manifest`,
  reads it before and after the fill, and drops what it stored when it moved.
  """
  @spec fence() :: integer() | nil
  def fence, do: :persistent_term.get(@fence_key, nil)

  defp change_fence, do: :persistent_term.get(@change_fence_key, nil)

  # Both unique on this node, so a fence never comes back to a value a fill holds
  defp move_change_fence, do: :persistent_term.put(@change_fence_key, System.unique_integer([:positive]))

  defp move_fence do
    :persistent_term.put(@fence_key, System.unique_integer([:positive]))
    :ok
  end

  defp store(key, value) do
    :persistent_term.put(key, value)

    keys = :persistent_term.get(@cache_keys_key, [])
    :persistent_term.put(@cache_keys_key, Enum.uniq([key | keys]))
  end

  defp cached_value(nil, _key), do: nil
  defp cached_value(cached, key), do: Map.get(cached, key)

  defp normalize_relative_path(path) do
    normalized = path |> String.trim_leading("/") |> Path.expand("/") |> Path.relative_to("/")

    if normalized in ["", "."] or String.starts_with?(normalized, "../"),
      do: nil,
      else: normalized
  end

  defp uploaded_at(metadata) do
    case Map.get(metadata, :uploaded_at, Map.get(metadata, "uploaded_at")) do
      %DateTime{} = uploaded_at -> uploaded_at
      uploaded_at when is_binary(uploaded_at) -> parse_uploaded_at(uploaded_at)
      _missing -> DateTime.utc_now()
    end
  end

  defp parse_uploaded_at(uploaded_at) do
    case DateTime.from_iso8601(uploaded_at) do
      {:ok, parsed, _offset} -> parsed
      _invalid -> DateTime.utc_now()
    end
  end

  defp stringify_metadata(metadata) do
    Map.new(metadata, fn {key, value} -> {to_string(key), json_value(value)} end)
  end

  defp json_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_value(value), do: value

  defp site_id(nil), do: nil
  defp site_id(%Site{id: site_id}), do: site_id

  defp scope_site_id(:standalone), do: nil
  defp scope_site_id({:site_id, site_id}), do: site_id

  defp invalidate_vite(site_id) do
    site_id |> vite_prefixes() |> Enum.each(&invalidate_vite_prefix/1)
  end

  defp invalidate_vite_prefix(prefix) do
    :persistent_term.erase(Tenant.cache_key({:vite, "cache_manifest"}, prefix))
    :persistent_term.erase(Tenant.cache_key({:vite, "critical_css"}, prefix))
  end

  defp vite_prefixes(nil) do
    case Tenant.mode() do
      :single ->
        case Registry.get_site_by_key(Brando.config(:site_key)) do
          nil -> [nil]
          site -> [nil | Enum.map(site.environments, &Tenant.prefix(site, &1))]
        end

      _none_or_multi ->
        [nil]
    end
  end

  defp vite_prefixes(site_id) do
    case Registry.get_site(site_id) do
      nil -> []
      site -> Enum.map(site.environments, &Tenant.prefix(site, &1))
    end
  end
end
