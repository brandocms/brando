defmodule Brando.Worker.PreviewPurger do
  @moduledoc """
  A Worker for purging previews
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  alias Brando.Assets.SiteAssets
  alias Brando.Assets.SiteAssets.Retention
  alias Brando.Assets.SiteAssetSet
  alias Brando.Sites
  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Tenant.Registry

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: TenantJob.run(job, fn -> perform_tenant(job) end)

  defp perform_tenant(%Oban.Job{args: %{"id" => id}}) do
    case Brando.Repo.get(Sites.Preview, id) do
      nil ->
        :ok

      preview ->
        now = DateTime.utc_now()
        remaining = DateTime.diff(preview.expires_at, now, :second)

        if DateTime.compare(preview.expires_at, now) == :gt do
          {:snooze, max(remaining, 1)}
        else
          case Sites.delete_preview(id, :system) do
            {:ok, _} -> release_asset_set(preview.asset_set_id)
            {:error, _} -> :ok
          end
        end
    end
  end

  # The preview no longer pins its asset set. Drop the scope's pinned listing
  # and remove captured release sets nothing references any more.
  defp release_asset_set(nil), do: :ok

  defp release_asset_set(asset_set_id) do
    case Brando.Repo.get(SiteAssetSet, asset_set_id, prefix: "public") do
      nil ->
        :ok

      asset_set ->
        SiteAssets.invalidate_pinned(asset_set)

        with {:ok, scope} <- asset_scope(asset_set) do
          Retention.prune_captured_sets(scope)
        end

        :ok
    end
  rescue
    exception ->
      Logger.warning("Preview purge could not prune asset sets: #{Exception.message(exception)}")
      :ok
  end

  defp asset_scope(%SiteAssetSet{site_id: nil}), do: {:ok, nil}

  defp asset_scope(%SiteAssetSet{site_id: site_id}) do
    case Registry.get_site(site_id) do
      nil -> {:error, :site_not_found}
      site -> {:ok, site}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(5)
end
