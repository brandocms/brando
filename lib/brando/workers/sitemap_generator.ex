defmodule Brando.Worker.SitemapGenerator do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 2

  require Logger

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(_) do
    Logger.info("==> [CRON] Generating sitemap...")
    TenantJob.each_active_environment(:live, &Brando.Sitemap.generate_sitemap/0)
    Logger.info("==> [CRON] Generating sitemap... done")
    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(180)
end
