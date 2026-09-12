defmodule Brando.Assets.SiteAssets do
  @moduledoc """
  Registry and runtime cache for persistent, uploadable frontend asset sets.

  Standalone installations use `site_assets/sets/{set}`. Multi-site
  installations use `sites/{site_key}/assets/sets/{set}`. Activation caches
  the complete regular-file listing as a `MapSet` and the optional Vite
  manifest in `:persistent_term`, making non-matching request rejection a
  memory lookup with no filesystem access.

  Shared previews pin the set they were rendered against (see
  `with_preview_set/2` and `Brando.Assets.SiteAssets.Capture`). A pinned set
  keeps serving its content-addressed build output at the original URLs until
  the last preview that references it expires, so a later activation or release
  cannot break a link that has already been shared. `Brando.Assets.SiteAssets.Retention`
  owns the pruning rules that protect those sets.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Assets.SiteAssets.Capture
  alias Brando.Assets.SiteAssets.Retention
  alias Brando.Assets.SiteAssetSet
  alias Brando.Repo
  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Tenant.Lock
  alias Brando.Tenant.Registry
  alias Brando.Tenant.Storage

  @public_opts [prefix: "public"]
  @cache_keys_key {:brando, :site_assets, :cache_keys}
  @override_key {:brando, :site_assets, :override}

  @type scope :: Site.t() | nil
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
    with %SiteAssetSet{} = asset_set <- Repo.get(SiteAssetSet, set_id, @public_opts),
         {:ok, cached} <- build_cache(asset_set),
         {:ok, active_set} <- persist_activation(asset_set) do
      put_cache(scope_key(active_set), %{cached | set: active_set})
      invalidate_vite(active_set.site_id)
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
        put_cache(scope_key(site), :none)
        invalidate_vite(site_id(site))
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

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
  def set_cache(%SiteAssetSet{id: id} = asset_set) do
    key = set_cache_key(id)

    case :persistent_term.get(key, :not_cached) do
      :not_cached ->
        with {:ok, cached} <- build_cache(asset_set) do
          store(key, cached)
          {:ok, cached}
        end

      cached ->
        {:ok, cached}
    end
  end

  @doc "Drops the runtime caches for one set, including the pinned listing of its scope."
  @spec forget_set(SiteAssetSet.t()) :: :ok
  def forget_set(%SiteAssetSet{id: id} = asset_set) do
    :persistent_term.erase(set_cache_key(id))
    invalidate_pinned(asset_set)
  end

  @doc """
  Resolves the immutable set a shared preview must be pinned to and runs `fun`
  with that set installed as the process-local asset source.

  The scope's advisory lock is held for the whole call, so pruning cannot
  remove the set while the preview is being captured, rendered, or saved. The
  set is the active uploaded set when it is self-contained; otherwise the
  effective release build is captured into a registered set first. Templates
  rendered inside `fun` read the pinned manifest and critical CSS even if
  another set is activated concurrently.
  """
  @spec with_preview_set(scope(), (SiteAssetSet.t() -> result)) :: {:ok, result} | {:error, term()}
        when result: var
  def with_preview_set(site \\ nil, fun) when is_function(fun, 1) do
    Lock.with(lock_key(site), fn -> pin_and_run(site, fun) end)
  end

  defp pin_and_run(site, fun) do
    with {:ok, asset_set} <- Capture.ensure_set(site),
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
  Resolves a request path to a file in the active set or, failing that, in a
  set pinned by an unexpired shared preview for the same scope. Pinned lookups
  only cover the content-addressed files listed in a set's Vite manifest, so an
  old set never shadows un-hashed files such as favicons.
  """
  @spec serve_path(scope(), String.t()) :: String.t() | nil
  def serve_path(site, relative_path) when is_binary(relative_path) do
    active_file(site, relative_path) || pinned_file(site, relative_path)
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
    :persistent_term.erase(pinned_cache_key(scope_key(scope)))
    :ok
  end

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

    from(asset_set in SiteAssetSet, where: asset_set.active)
    |> Repo.all(@public_opts)
    |> Enum.each(fn asset_set ->
      case build_cache(asset_set) do
        {:ok, cached} -> put_cache(scope_key(asset_set), cached)
        {:error, _reason} -> put_cache(scope_key(asset_set), :none)
      end
    end)

    :ok
  rescue
    _migration_not_applied_yet -> :ok
  end

  @doc "Clears all active-set runtime caches."
  @spec invalidate_cache() :: :ok
  def invalidate_cache do
    @cache_keys_key
    |> :persistent_term.get([])
    |> Enum.each(&:persistent_term.erase/1)

    :persistent_term.erase(@cache_keys_key)
    :ok
  end

  @doc """
  Returns the Vite manifest of the process-local override set or, without one,
  of the current scope's active set.
  """
  @spec current_manifest() :: map() | nil
  def current_manifest do
    case override() do
      %{manifest: manifest} -> manifest
      nil -> current_scope() |> scope_cached() |> cached_value(:manifest)
    end
  end

  @doc "Resolves a regular file within the override set or the current active set."
  @spec current_file(String.t()) :: String.t() | nil
  def current_file(relative_path) when is_binary(relative_path) do
    with %{files: files, path: root} <- override() || scope_cached(current_scope()),
         normalized when is_binary(normalized) <- normalize_relative_path(relative_path),
         true <- MapSet.member?(files, normalized) do
      Path.join(root, normalized)
    else
      _ -> nil
    end
  end

  @doc "Returns the override or active set root for static export tooling."
  @spec current_root() :: String.t() | nil
  def current_root do
    case override() do
      %{path: path} -> path
      nil -> current_scope() |> scope_cached() |> cached_value(:path)
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
    Brando.config(:site_assets_path) ||
      Brando.config(:media_path) |> Path.expand() |> Path.dirname() |> Path.join("site_assets")
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

  defp active_file(site, relative_path) do
    case cached(site) do
      %{files: files, path: root} ->
        if MapSet.member?(files, relative_path), do: Path.join(root, relative_path)

      nil ->
        nil
    end
  end

  defp pinned_file(site, relative_path) do
    site
    |> pinned_sets()
    |> Enum.find_value(fn %{pinned: pinned, path: root} ->
      if MapSet.member?(pinned, relative_path), do: Path.join(root, relative_path)
    end)
  end

  defp warm_pinned(site) do
    pinned =
      site
      |> Retention.preview_pinned_sets()
      |> Enum.flat_map(fn asset_set ->
        case set_cache(asset_set) do
          {:ok, cached} -> [cached]
          {:error, _reason} -> []
        end
      end)

    store(pinned_cache_key(scope_key(site)), pinned)
    pinned
  rescue
    _migration_not_applied_yet ->
      store(pinned_cache_key(scope_key(site)), [])
      []
  end

  defp with_override(cached, fun) do
    previous = Process.get(@override_key)
    Process.put(@override_key, cached)

    try do
      {:ok, fun.()}
    after
      if previous, do: Process.put(@override_key, previous), else: Process.delete(@override_key)
    end
  end

  defp scope_cached({:ok, site}), do: cached(site)
  defp scope_cached(:error), do: nil

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
    case active_set(site) do
      nil ->
        put_cache(scope_key(site), :none)
        nil

      asset_set ->
        case build_cache(asset_set) do
          {:ok, cached} ->
            put_cache(scope_key(site), cached)
            cached

          {:error, _reason} ->
            put_cache(scope_key(site), :none)
            nil
        end
    end
  rescue
    _migration_not_applied_yet -> nil
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

  defp put_cache(scope_key, value), do: store(cache_key(scope_key), value)

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

  defp invalidate_vite(site_id) do
    vite_prefixes(site_id)
    |> Enum.each(fn prefix ->
      :persistent_term.erase(Tenant.cache_key({:vite, "cache_manifest"}, prefix))
      :persistent_term.erase(Tenant.cache_key({:vite, "critical_css"}, prefix))
    end)
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
