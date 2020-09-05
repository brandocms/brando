defmodule Brando.Worker.SitemapWorker do
  use Oban.Worker
  require Logger

  @impl Oban.Worker
  def perform(_) do
    Logger.info("==> Generating sitemap...")
    Brando.Sitemap.generate_sitemap()
    Logger.info("==> Generating sitemap... done")
    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(120)
end
