defmodule Brando.Media.OrphanCleanup do
  @moduledoc """
  Conservatively removes local media files that no environment references.

  An asset row is local to an environment schema while the underlying file is
  shared by every environment for the site. Cleanup therefore builds one union
  of image and file paths across all current environment schemas before it
  considers deleting anything. If any environment can't be inspected, the run
  fails without deleting files.

  Only regular files below the managed `images`, `videos`, and `files`
  directories are candidates. Symlinks, SVG files, and files newer than the
  grace period are never removed. Pass `dry_run: true` to inspect the result.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Environments.Environment
  alias Brando.Files.File, as: MediaFile
  alias Brando.Images.Image
  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Tenant.Registry

  @managed_directories ~w(images videos files)
  @default_grace_seconds :timer.hours(24) |> div(1_000)

  @type report :: %{
          root: String.t(),
          referenced_count: non_neg_integer(),
          candidate_count: non_neg_integer(),
          deleted: [String.t()],
          dry_run: boolean()
        }

  @doc """
  Removes files not referenced by any environment schema for `site`.

  Options:

    * `:dry_run` — report orphan paths without deleting them (default `false`)
    * `:older_than_seconds` — minimum file age (default 24 hours)
    * `:media_root` — override the site media root, primarily for operations
      tooling and tests
  """
  @spec run(Site.t(), keyword()) :: {:ok, report()} | {:error, term()}
  def run(site, opts \\ [])

  def run(%Site{} = site, opts) do
    dry_run? = Keyword.get(opts, :dry_run, false)
    grace_seconds = Keyword.get(opts, :older_than_seconds, @default_grace_seconds)
    root = Keyword.get_lazy(opts, :media_root, fn -> media_root(site) end) |> Path.expand()

    with :ok <- validate_grace_period(grace_seconds),
         {:ok, references} <- referenced_paths(site),
         {:ok, candidates} <- candidate_files(root),
         orphans <- orphan_paths(candidates, root, references, grace_seconds),
         {:ok, deleted} <- maybe_delete(orphans, root, dry_run?) do
      {:ok,
       %{
         root: root,
         referenced_count: MapSet.size(references),
         candidate_count: length(candidates),
         deleted: deleted,
         dry_run: dry_run?
       }}
    end
  end

  @doc "Returns the local media root reserved for a site."
  @spec media_root(Site.t()) :: String.t()
  def media_root(%Site{} = site) do
    case Tenant.mode() do
      :multi -> Path.join(Brando.config(:media_path), site.key)
      _single_or_none -> Brando.config(:media_path)
    end
  end

  defp referenced_paths(site) do
    case Registry.list_environments(site) do
      [] ->
        {:error, :no_environments}

      environments ->
        Enum.reduce_while(environments, {:ok, MapSet.new()}, fn environment, {:ok, paths} ->
          case environment_paths(site, environment) do
            {:ok, environment_paths} ->
              {:cont, {:ok, MapSet.union(paths, environment_paths)}}

            {:error, reason} ->
              {:halt, {:error, {:environment_scan_failed, environment.key, reason}}}
          end
        end)
    end
  end

  defp environment_paths(site, %Environment{} = environment) do
    prefix = Tenant.prefix(site, environment)

    try do
      image_paths =
        from(image in Image, select: {image.path, image.sizes, image.formats})
        |> Brando.Repo.all(prefix: prefix)
        |> Enum.flat_map(&image_paths/1)

      file_paths =
        from(file in MediaFile, select: {file.filename, file.config_target})
        |> Brando.Repo.all(prefix: prefix)
        |> Enum.map(&file_path/1)

      paths =
        (image_paths ++ file_paths)
        |> Enum.map(&normalize_reference(&1, site))
        |> MapSet.new()

      {:ok, paths}
    rescue
      error -> {:error, error}
    end
  end

  defp image_paths({path, sizes, formats}) do
    sized_paths = sizes |> Kernel.||(%{}) |> Map.values()

    formatted_paths =
      for format <- formats || [],
          format not in [:original, "original"],
          sized_path <- sized_paths do
        Brando.Utils.change_extension(sized_path, to_string(format))
      end

    [path | sized_paths] ++ formatted_paths
  end

  defp file_path({filename, config_target}) do
    {:ok, config} = Brando.Files.get_config_for(config_target)
    Path.join(config.upload_path, filename)
  end

  defp normalize_reference(path, site) when is_binary(path) do
    path = path |> String.trim_leading("/") |> Path.expand("/") |> Path.relative_to("/")
    site_prefix = site.key <> "/"

    if Tenant.mode() == :multi and String.starts_with?(path, site_prefix) do
      String.replace_prefix(path, site_prefix, "")
    else
      path
    end
  end

  defp normalize_reference(_path, _site), do: ""

  defp candidate_files(root) do
    @managed_directories
    |> Enum.map(&Path.join(root, &1))
    |> Enum.reduce_while({:ok, []}, fn directory, {:ok, files} ->
      case regular_files(directory) do
        {:ok, found} -> {:cont, {:ok, found ++ files}}
        {:error, reason} -> {:halt, {:error, {:media_scan_failed, directory, reason}}}
      end
    end)
  end

  defp regular_files(directory) do
    case File.ls(directory) do
      {:ok, entries} ->
        Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, files} ->
          path = Path.join(directory, entry)

          case File.lstat(path) do
            {:ok, %{type: :regular}} ->
              {:cont, {:ok, [path | files]}}

            {:ok, %{type: :directory}} ->
              case regular_files(path) do
                {:ok, nested} -> {:cont, {:ok, nested ++ files}}
                {:error, reason} -> {:halt, {:error, reason}}
              end

            {:ok, _symlink_or_special} ->
              {:cont, {:ok, files}}

            {:error, reason} ->
              {:halt, {:error, {path, reason}}}
          end
        end)

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp orphan_paths(candidates, root, references, grace_seconds) do
    candidates
    |> Enum.reject(&String.ends_with?(String.downcase(&1), ".svg"))
    |> Enum.filter(&old_enough?(&1, grace_seconds))
    |> Enum.reject(fn path -> MapSet.member?(references, Path.relative_to(path, root)) end)
    |> Enum.sort()
  end

  defp old_enough?(path, grace_seconds) do
    with {:ok, %{mtime: modified_at}} <- File.stat(path, time: :posix) do
      System.os_time(:second) - modified_at >= grace_seconds
    else
      _ -> false
    end
  end

  defp maybe_delete(paths, root, true), do: {:ok, Enum.map(paths, &Path.relative_to(&1, root))}

  defp maybe_delete(paths, root, false) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, deleted} ->
      case File.rm(path) do
        :ok -> {:cont, {:ok, [Path.relative_to(path, root) | deleted]}}
        {:error, reason} -> {:halt, {:error, {:delete_failed, path, reason}}}
      end
    end)
    |> case do
      {:ok, deleted} -> {:ok, Enum.reverse(deleted)}
      error -> error
    end
  end

  defp validate_grace_period(seconds) when is_integer(seconds) and seconds >= 0, do: :ok
  defp validate_grace_period(seconds), do: {:error, {:invalid_grace_period, seconds}}
end
