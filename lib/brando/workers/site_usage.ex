defmodule Brando.Worker.SiteUsage do
  @moduledoc """
  Measures what sites store and keeps the snapshot on the day's row
  (`Brando.Sites.Usage`): every site from the daily cron entry, with
  `%{"all" => true}`, then prunes the rows past the retention period; one
  site for a superuser's "Measure now", with `%{"site_id" => id}`.

  A site whose measuring fails keeps its last snapshot, and the next site is
  measured all the same. Outside `tenancy_mode: :multi` it does nothing, also
  when it was queued before the mode changed.

  With `tenancy_mode: :multi`, Brando's default Oban configuration schedules
  it and runs its `site_usage` queue. An application with its own
  `config :brando, Oban` adds both on a `:multi` installation:

      queues: [site_usage: [limit: 1], ...],
      cron: [crontab: [{"30 5 * * *", Brando.Worker.SiteUsage, args: %{"all" => true}}, ...]]
  """
  use Oban.Worker,
    queue: :site_usage,
    max_attempts: 3,
    # One a day across nodes
    unique: [period: 23 * 60 * 60]

  require Logger

  alias Brando.Sites.Site
  alias Brando.Sites.Usage
  alias Brando.Sites.Usage.Measure
  alias Brando.Tenant.Registry

  # Another while one is waiting is the same measuring
  @site_unique [period: :infinity, keys: [:site_id], states: [:available, :scheduled, :retryable]]

  @doc "Queues measuring `site` now, unless one is already waiting."
  @spec measure_now(Site.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def measure_now(%Site{id: site_id}), do: %{"site_id" => site_id} |> new(unique: @site_unique) |> Oban.insert()

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    if Usage.enabled?(), do: run(args), else: :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.hours(1)

  defp run(%{"site_id" => site_id}) do
    case Registry.get_site(site_id) do
      %Site{} = site -> measure(site, Date.utc_today())
      # Deleted since it was queued
      nil -> :ok
    end

    :ok
  end

  defp run(%{"all" => true}) do
    today = Date.utc_today()
    Enum.each(Registry.list_sites(), &measure(&1, today))
    pruned = Usage.prune(today)
    Logger.info("==> [CRON] Measured site usage; deleted #{pruned} rows older than #{Usage.retention_months()} months")
    :ok
  end

  defp measure(site, today) do
    :ok = Usage.put_measurement(site.id, today, Measure.site(site))
    Usage.broadcast_measured(site.id)
  rescue
    error ->
      Logger.error("[Brando.Sites.Usage] Could not measure #{site.key}: #{Exception.message(error)}")
  end
end
