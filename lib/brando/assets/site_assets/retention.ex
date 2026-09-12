defmodule Brando.Assets.SiteAssets.Retention do
  @moduledoc """
  Decides which registered asset sets may be deleted, and deletes them.

  A set is protected while any of these hold:

    * it is the scope's active set;
    * an unexpired shared preview references it. `sites_previews.expires_at`
      is compared directly, so expired rows the purge worker has not removed
      yet never prolong protection;
    * a queued or running static build still needs it as its asset source.

  Deletion runs under the scope's asset lock, the same lock
  `Brando.Assets.SiteAssets.with_preview_set/2` holds while a preview is
  captured, rendered, and saved, so a set cannot disappear underneath a preview
  that is acquiring it. Deployment tooling such as Florist must call
  `prune_sets/2` or `delete_set/1` instead of removing directories by age or
  count; protected sets may temporarily exceed the configured `:keep` count.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Assets.SiteAssets
  alias Brando.Assets.SiteAssets.Capture
  alias Brando.Assets.SiteAssetSet
  alias Brando.Repo
  alias Brando.Sites.Preview
  alias Brando.SSG.Build
  alias Brando.Tenant.Lock
  alias Brando.Tenant.Registry

  require Logger

  @public_opts [prefix: "public"]
  @busy_build_statuses [:queued, :building]
  @default_keep 5

  @doc "Sets in the scope that an unexpired shared preview still references."
  @spec preview_pinned_sets(SiteAssets.scope()) :: [SiteAssetSet.t()]
  def preview_pinned_sets(site \\ nil) do
    referenced = preview_referenced_ids()

    site
    |> SiteAssets.list_sets()
    |> Enum.filter(&MapSet.member?(referenced, &1.id))
  end

  @doc "IDs of every set in the scope that must not be deleted right now."
  @spec protected_set_ids(SiteAssets.scope()) :: MapSet.t(pos_integer())
  def protected_set_ids(site \\ nil) do
    referenced = MapSet.union(preview_referenced_ids(), build_referenced_ids())

    site
    |> SiteAssets.list_sets()
    |> Enum.filter(&(&1.active or MapSet.member?(referenced, &1.id)))
    |> MapSet.new(& &1.id)
  end

  @doc "Returns true when the set is active or still referenced by a preview or build."
  @spec protected?(SiteAssetSet.t()) :: boolean()
  def protected?(%SiteAssetSet{id: id} = asset_set) do
    asset_set
    |> scope()
    |> protected_set_ids()
    |> MapSet.member?(id)
  end

  @doc """
  Sets ordinary retention would delete: uploaded sets beyond the newest
  `:keep` (default #{@default_keep}) plus every captured set, minus protected
  sets. Captured sets exist only for previews and never count against `:keep`.
  """
  @spec prunable_sets(SiteAssets.scope() | keyword(), keyword()) :: [SiteAssetSet.t()]
  def prunable_sets(site \\ nil, opts \\ [])
  def prunable_sets(opts, []) when is_list(opts), do: prunable_sets(nil, opts)

  def prunable_sets(site, opts) do
    keep = Keyword.get(opts, :keep, @default_keep)
    protected = protected_set_ids(site)

    {uploaded, captured} =
      site
      |> SiteAssets.list_sets()
      |> Enum.split_with(&(not Capture.captured?(&1)))

    (Enum.drop(uploaded, keep) ++ captured)
    |> Enum.reject(&MapSet.member?(protected, &1.id))
  end

  @doc "Deletes every prunable set in the scope under the asset lock and returns the deleted sets."
  @spec prune_sets(SiteAssets.scope() | keyword(), keyword()) :: {:ok, [SiteAssetSet.t()]}
  def prune_sets(site \\ nil, opts \\ [])
  def prune_sets(opts, []) when is_list(opts), do: prune_sets(nil, opts)

  def prune_sets(site, opts) do
    Lock.with(SiteAssets.lock_key(site), fn ->
      {:ok, site |> prunable_sets(opts) |> Enum.flat_map(&delete_now/1)}
    end)
  end

  @doc "Deletes captured sets no preview or build needs any more. Uploaded sets are left to `prune_sets/2`."
  @spec prune_captured_sets(SiteAssets.scope()) :: {:ok, [SiteAssetSet.t()]}
  def prune_captured_sets(site \\ nil) do
    Lock.with(SiteAssets.lock_key(site), fn ->
      protected = protected_set_ids(site)

      deleted =
        site
        |> SiteAssets.list_sets()
        |> Enum.filter(&(Capture.captured?(&1) and not MapSet.member?(protected, &1.id)))
        |> Enum.flat_map(&delete_now/1)

      {:ok, deleted}
    end)
  end

  @doc "Deletes one set unless it is protected."
  @spec delete_set(SiteAssetSet.t() | pos_integer()) :: {:ok, SiteAssetSet.t()} | {:error, term()}
  def delete_set(set_id) when is_integer(set_id) do
    case Repo.get(SiteAssetSet, set_id, @public_opts) do
      nil -> {:error, :asset_set_not_found}
      asset_set -> delete_set(asset_set)
    end
  end

  def delete_set(%SiteAssetSet{id: id} = asset_set) do
    Lock.with(SiteAssets.lock_key(asset_set), fn ->
      cond do
        is_nil(Repo.get(SiteAssetSet, id, @public_opts)) -> {:error, :asset_set_not_found}
        protected?(asset_set) -> {:error, :asset_set_protected}
        true -> delete(asset_set)
      end
    end)
  end

  defp delete_now(asset_set) do
    case delete(asset_set) do
      {:ok, deleted} -> [deleted]
      {:error, _reason} -> []
    end
  end

  defp delete(asset_set) do
    with {:ok, deleted} <- Repo.delete(asset_set, @public_opts) do
      SiteAssets.forget_set(deleted)
      remove_directory(deleted)
      {:ok, deleted}
    end
  end

  # The registry row is gone, so the set can no longer be activated or pinned.
  # A directory that cannot be removed is logged rather than failing the prune.
  defp remove_directory(%SiteAssetSet{path: path} = asset_set) do
    with {:ok, site} <- scope_site(asset_set),
         true <- Path.dirname(Path.expand(path)) == site |> SiteAssets.sets_root() |> Path.expand(),
         {:ok, _removed} <- File.rm_rf(path) do
      :ok
    else
      _problem -> Logger.warning("Could not remove asset set directory #{inspect(path)}")
    end
  end

  defp preview_referenced_ids do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(preview in Preview,
      where: preview.expires_at > ^now and not is_nil(preview.asset_set_id),
      select: preview.asset_set_id,
      distinct: true
    )
    |> Repo.all(@public_opts)
    |> MapSet.new()
  end

  defp build_referenced_ids do
    from(build in Build,
      where: build.status in ^@busy_build_statuses and not is_nil(build.asset_set_id),
      select: build.asset_set_id,
      distinct: true
    )
    |> Repo.all(@public_opts)
    |> MapSet.new()
  end

  defp scope(%SiteAssetSet{site_id: nil}), do: nil
  defp scope(%SiteAssetSet{site_id: site_id}), do: %Brando.Sites.Site{id: site_id}

  defp scope_site(%SiteAssetSet{site_id: nil}), do: {:ok, nil}

  defp scope_site(%SiteAssetSet{site_id: site_id}) do
    case Registry.get_site(site_id) do
      nil -> {:error, :site_not_found}
      site -> {:ok, site}
    end
  end
end
