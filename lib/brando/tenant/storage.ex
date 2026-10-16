defmodule Brando.Tenant.Storage do
  @moduledoc "Filesystem locations owned by one site."

  alias Brando.Sites.Site

  @spec create(Site.t()) :: :ok | {:error, term()}
  def create(%Site{} = site) do
    roots = [media_root(site), site_root(site)]

    case Enum.find(roots, &File.exists?/1) do
      nil -> create_new_directories(roots ++ [assets_root(site)])
      path -> {:error, {:site_storage_already_exists, path}}
    end
  end

  @spec delete(Site.t()) :: :ok | {:error, term()}
  def delete(%Site{} = site) do
    [media_root(site), site_root(site)]
    |> Enum.reduce_while(:ok, fn path, :ok ->
      case File.rm_rf(path) do
        {:ok, _removed} -> {:cont, :ok}
        {:error, reason, failed_path} -> {:halt, {:error, {:delete_directory_failed, failed_path, reason}}}
      end
    end)
  end

  @spec media_root(Site.t()) :: String.t()
  def media_root(%Site{key: site_key}), do: Path.join(Brando.config(:media_path), site_key)

  @doc "Returns the filesystem media root for the current tenant context."
  @spec current_media_root() :: String.t()
  def current_media_root do
    case Brando.Tenant.mode() do
      :multi ->
        case Brando.Tenant.current_site_key() do
          nil -> raise "multi-tenant media access requires a current tenant prefix"
          site_key -> Path.join(Brando.config(:media_path), site_key)
        end

      _single_or_none ->
        Brando.config(:media_path)
    end
  end

  @spec sites_root() :: String.t()
  def sites_root do
    Brando.config(:sites_path) || Path.join(media_parent(), "sites")
  end

  @doc """
  The directory holding the media directory, where `sites/` and `site_assets/`
  are kept unless `:sites_path` or `:site_assets_path` is configured.

  A media directory that is a symlink is followed. Florist links each
  release's `media` to the deploy's shared one, so this is the deploy's base
  directory, which outlives releases, rather than the release directory the
  relative `media_path: "./media"` sits in. A missing media directory, or one
  that is not a link, gives the directory `media_path` names it in.
  """
  @spec media_parent() :: String.t()
  def media_parent do
    Brando.config(:media_path) |> Path.expand() |> follow_links(0) |> Path.dirname()
  end

  # Bounded, so a link cycle ends where it was found.
  defp follow_links(path, 40), do: path

  defp follow_links(path, hops) do
    case File.read_link(path) do
      {:ok, target} -> target |> Path.expand(Path.dirname(path)) |> follow_links(hops + 1)
      {:error, _not_a_link} -> path
    end
  end

  @spec site_root(Site.t()) :: String.t()
  def site_root(%Site{key: site_key}), do: Path.join(sites_root(), site_key)

  @spec assets_root(Site.t()) :: String.t()
  def assets_root(%Site{} = site), do: Path.join(site_root(site), "assets")

  defp create_new_directories(paths) do
    paths
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, created} ->
      case File.mkdir_p(path) do
        :ok -> {:cont, {:ok, [path | created]}}
        {:error, reason} -> {:halt, {:error, {:create_directory_failed, path, reason}, created}}
      end
    end)
    |> case do
      {:ok, _created} ->
        :ok

      {:error, reason, created} ->
        Enum.each(created, &File.rm_rf/1)
        {:error, reason}
    end
  end
end
