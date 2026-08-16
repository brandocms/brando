defmodule Brando.Tenant.PublicMediaMigrator do
  @moduledoc """
  Copies classic local media into a new multi-tenant site's media root.

  The legacy tree is left untouched for rollback. Existing per-site roots are
  excluded, and symlinks or special files abort the migration rather than
  crossing an isolation boundary.
  """

  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Tenant.Registry
  alias Brando.Tenant.Storage

  @callback migrate(Site.t()) :: :ok | {:error, term()}

  @behaviour __MODULE__

  @impl true
  def migrate(%Site{} = site) do
    if Tenant.mode() == :multi do
      source_root = Brando.config(:media_path) |> Path.expand()
      target_root = site |> Storage.media_root() |> Path.expand()

      excluded_names =
        Registry.list_sites()
        |> Enum.map(& &1.key)
        |> MapSet.new()

      with {:ok, entries} <- File.ls(source_root),
           entries <- Enum.reject(entries, &MapSet.member?(excluded_names, &1)),
           :ok <- validate_entries(source_root, entries),
           :ok <- copy_entries(source_root, target_root, entries) do
        :ok
      else
        {:error, reason} -> {:error, {:media_migration_failed, reason}}
      end
    else
      :ok
    end
  end

  defp validate_entries(root, entries) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      case validate_path(Path.join(root, entry)) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_path(path) do
    case File.lstat(path) do
      {:ok, %{type: :regular}} ->
        :ok

      {:ok, %{type: :directory}} ->
        case File.ls(path) do
          {:ok, entries} -> validate_entries(path, entries)
          {:error, reason} -> {:error, {:media_directory_read_failed, path, reason}}
        end

      {:ok, _symlink_or_special} ->
        {:error, {:unsupported_media_file, path}}

      {:error, reason} ->
        {:error, {:media_file_stat_failed, path, reason}}
    end
  end

  defp copy_entries(source_root, target_root, entries) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      source = Path.join(source_root, entry)
      target = Path.join(target_root, entry)

      case File.cp_r(source, target) do
        {:ok, _copied} -> {:cont, :ok}
        {:error, reason, path} -> {:halt, {:error, {:media_copy_failed, path, reason}}}
      end
    end)
  end
end
