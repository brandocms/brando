defmodule Brando.Worker.VideoUploadReaper do
  @moduledoc """
  Marks `Video` rows stuck in `:uploading` as `:errored`.

  External providers (Mux/Bunny/Cloudflare) require the row to exist before any bytes
  move — their webhooks correlate on a provider identifier in `meta` — so an
  abandoned browser upload (closed tab, network loss, cancel) leaves an
  `:uploading` row that can never complete: provider direct-upload URLs
  expire within the hour. Rows still `:uploading` after 24 hours flip to
  `:errored`, matching the provider webhook failure paths.

  Deliberately NOT a soft delete: `Videos.get_video_by_meta/2` filters out
  soft-deleted rows, so deleting here would silently drop a completion
  webhook that arrives after the reap — a real provider asset lost with no
  retry path. `:errored` rows stay webhook-reachable (lookup doesn't filter
  on status) and admin-visible/actionable.
  """
  use Oban.Worker, queue: :default, max_attempts: 2

  import Ecto.Query

  require Logger

  alias Brando.Tenant.Job, as: TenantJob

  @stale_after_hours 24

  @impl Oban.Worker
  def perform(_) do
    count =
      TenantJob.each_active_environment(:all, &reap_current_environment/0)
      |> Enum.sum()

    if count > 0 do
      Logger.info("==> [CRON] Marked #{count} abandoned video upload(s) as errored")
    end

    :ok
  end

  defp reap_current_environment do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    cutoff = NaiveDateTime.add(now, -@stale_after_hours * 3600, :second)

    query =
      from v in Brando.Videos.Video,
        where: v.status == :uploading and v.inserted_at < ^cutoff and is_nil(v.deleted_at)

    {count, _} = Brando.Repo.update_all(query, set: [status: :errored, updated_at: now])
    count
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
