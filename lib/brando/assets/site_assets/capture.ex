defmodule Brando.Assets.SiteAssets.Capture do
  @moduledoc """
  Materializes the frontend build a shared preview depends on into a
  persistent, registered asset set.

  Ordinary releases keep their compiled assets inside `priv/static`, which the
  next deploy replaces. A preview link must outlive that, so before rendering,
  the effective build is copied into `sets/capture-<identity>` beside uploaded
  sets and registered without activation. The identity is derived from the
  merged file listing and the Vite manifest, so repeated shares of one release
  reuse a single capture. Files are copied rather than symlinked, and a capture
  is published by an atomic rename out of a staging directory, so a concurrent
  reader never sees a partial set.

  When an uploaded set is active and self-contained (every file its manifest
  lists is present), it is reused directly. An uploaded set that relies on
  release fallback files is merged with the release, uploaded files taking
  precedence, so the pinned copy is complete.
  """

  alias Brando.Assets.SiteAssets
  alias Brando.Assets.SiteAssetSet
  alias Brando.Repo

  @source "release_capture"
  @excluded_top_level ~w(media)
  @public_opts [prefix: "public"]

  @doc "The metadata `source` value marking sets Brando captured itself."
  @spec source() :: String.t()
  def source, do: @source

  @doc "Returns true for sets Brando captured from a release rather than uploaded sets."
  @spec captured?(SiteAssetSet.t()) :: boolean()
  def captured?(%SiteAssetSet{metadata: metadata}), do: Map.get(metadata || %{}, "source") == @source

  @doc """
  Returns a registered set that fully covers the scope's effective frontend
  assets, capturing the release build when necessary.

  Call under the scope's asset lock; `Brando.Assets.SiteAssets.with_preview_set/2`
  does so.
  """
  @spec ensure_set(SiteAssets.scope()) :: {:ok, SiteAssetSet.t()} | {:error, term()}
  def ensure_set(site) do
    case SiteAssets.active_set(site) do
      nil -> capture(site, [release_root()])
      %SiteAssetSet{} = active -> ensure_from_active(site, active)
    end
  end

  defp ensure_from_active(site, active) do
    with {:ok, cached} <- SiteAssets.set_cache(active) do
      if self_contained?(cached),
        do: {:ok, active},
        else: capture(site, [release_root(), active.path])
    end
  end

  @doc """
  The release's compiled static directory. Override it with
  `config :brando, :release_static_path` when the assets are not under the
  endpoint application's `priv/static`.
  """
  @spec release_root() :: String.t()
  def release_root do
    Brando.config(:release_static_path) ||
      Application.app_dir(Brando.endpoint().config(:otp_app), "priv/static")
  end

  defp self_contained?(%{manifest: nil}), do: false

  defp self_contained?(%{manifest: manifest, files: files}) do
    manifest
    |> SiteAssets.manifest_files()
    |> Enum.all?(&MapSet.member?(files, &1))
  end

  defp capture(site, sources) do
    with {:ok, listing} <- merged_listing(sources),
         {:ok, identity} <- identity(listing) do
      name = "capture-" <> identity
      reuse_or_publish(site, name, existing(site, name), listing, identity)
    end
  end

  defp reuse_or_publish(site, name, %SiteAssetSet{path: path} = asset_set, listing, identity) do
    if File.dir?(path) do
      {:ok, asset_set}
    else
      # A stale row whose directory is gone must not be handed out; capture again.
      Repo.delete(asset_set, @public_opts)
      SiteAssets.forget_set(asset_set)
      publish(site, name, listing, identity)
    end
  end

  defp reuse_or_publish(site, name, nil, listing, identity), do: publish(site, name, listing, identity)

  defp existing(site, name) do
    site
    |> SiteAssets.list_sets()
    |> Enum.find(&(&1.name == name))
  end

  defp publish(site, name, listing, identity) do
    final_path = Path.join(SiteAssets.sets_root(site), name)
    staging = Path.join(staging_root(site), "#{name}-#{Brando.Utils.random_string(8)}")

    with :ok <- copy_listing(listing, staging),
         :ok <- move_into_place(staging, final_path),
         {:ok, asset_set} <- register(site, name, final_path, identity) do
      {:ok, asset_set}
    else
      {:error, reason} ->
        File.rm_rf(staging)
        {:error, {:asset_capture_failed, reason}}
    end
  end

  defp register(site, name, final_path, identity) do
    now = DateTime.utc_now()
    metadata = %{source: @source, revision: identity, uploaded_at: now, captured_at: now}

    case SiteAssets.register_set(site, final_path, metadata) do
      {:ok, asset_set} ->
        {:ok, asset_set}

      {:error, %Ecto.Changeset{errors: errors}} = error ->
        # Another process registered the same identity first.
        case {Keyword.has_key?(errors, :name), existing(site, name)} do
          {true, %SiteAssetSet{} = asset_set} -> {:ok, asset_set}
          _not_a_duplicate -> error
        end

      error ->
        error
    end
  end

  defp merged_listing(sources) do
    Enum.reduce_while(sources, {:ok, %{}}, fn root, {:ok, acc} ->
      case list_files(root) do
        {:ok, files} -> {:cont, {:ok, Map.merge(acc, files)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp list_files(root) do
    if File.dir?(root), do: walk(root, root, %{}), else: {:ok, %{}}
  end

  defp walk(root, directory, acc) do
    case File.ls(directory) do
      {:ok, entries} ->
        Enum.reduce_while(entries, {:ok, acc}, &walk_entry(root, directory, &1, &2))

      {:error, reason} ->
        {:error, {:asset_directory_scan_failed, directory, reason}}
    end
  end

  defp walk_entry(root, directory, entry, {:ok, acc}) do
    path = Path.join(directory, entry)

    if directory == root and entry in @excluded_top_level,
      do: {:cont, {:ok, acc}},
      else: path |> File.stat() |> walk_stat(root, path, acc)
  end

  # `File.stat/1` follows symlinks so linked files are captured by content.
  defp walk_stat({:ok, %{type: :directory}}, root, path, acc) do
    case walk(root, path, acc) do
      {:ok, nested} -> {:cont, {:ok, nested}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp walk_stat({:ok, %{type: :regular, size: size}}, root, path, acc),
    do: {:cont, {:ok, Map.put(acc, Path.relative_to(path, root), {path, size})}}

  defp walk_stat({:ok, _special}, _root, _path, acc), do: {:cont, {:ok, acc}}
  defp walk_stat({:error, :enoent}, _root, _path, acc), do: {:cont, {:ok, acc}}

  defp walk_stat({:error, reason}, _root, path, _acc),
    do: {:halt, {:error, {:asset_file_stat_failed, path, reason}}}

  defp identity(listing) when map_size(listing) == 0, do: {:error, :no_frontend_assets}

  defp identity(listing) do
    hash =
      listing
      |> Enum.sort()
      |> Enum.reduce(:crypto.hash_init(:sha256), fn {relative, {_path, size}}, acc ->
        :crypto.hash_update(acc, "#{relative}\t#{size}\n")
      end)

    with {:ok, hash} <- hash_manifest(hash, listing) do
      {:ok, hash |> :crypto.hash_final() |> Base.encode16(case: :lower) |> binary_part(0, 16)}
    end
  end

  defp hash_manifest(hash, listing) do
    case Map.fetch(listing, "manifest.json") do
      {:ok, {path, _size}} ->
        case File.read(path) do
          {:ok, json} -> {:ok, :crypto.hash_update(hash, json)}
          {:error, reason} -> {:error, {:asset_manifest_read_failed, path, reason}}
        end

      :error ->
        {:ok, hash}
    end
  end

  defp copy_listing(listing, staging) do
    Enum.reduce_while(listing, :ok, fn {relative, {source, _size}}, :ok ->
      destination = Path.join(staging, relative)

      with :ok <- File.mkdir_p(Path.dirname(destination)),
           {:ok, _bytes} <- File.copy(source, destination) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, {:asset_copy_failed, source, reason}}}
      end
    end)
  end

  defp move_into_place(staging, final_path) do
    with :ok <- File.mkdir_p(Path.dirname(final_path)) do
      case File.rename(staging, final_path) do
        :ok ->
          :ok

        {:error, reason} when reason in [:eexist, :enotempty, :eisdir] ->
          # Published by an earlier attempt that failed before registering.
          File.rm_rf(staging)
          :ok

        {:error, reason} ->
          {:error, {:asset_publish_failed, final_path, reason}}
      end
    end
  end

  defp staging_root(site), do: site |> SiteAssets.sets_root() |> Path.dirname() |> Path.join("staging")
end
