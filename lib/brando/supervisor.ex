defmodule Brando.Supervisor do
  @moduledoc """
  Main Brando supervisor.

  Looks after our cache.
  """
  use Supervisor

  import Cachex.Spec

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    Brando.Telemetry.attach()
    Calendar.put_time_zone_database(Tz.TimeZoneDatabase)
    Brando.Villain.HeexRenderer.init_cache()
    Brando.Villain.init_parse_cache()

    children = [
      %{id: :main_cache, start: {Cachex, :start_link, [:cache, []]}},
      %{id: :query_cache, start: {Cachex, :start_link, [:query, []]}},
      %{
        id: :four_oh_four_cache,
        start:
          {Cachex, :start_link,
           [
             :four_oh_four,
             [
               hooks: [
                 hook(
                   module: Cachex.Limit.Scheduled,
                   args: {500, [], []}
                 )
               ]
             ]
           ]}
      },
      {Oban, oban_config()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # NOTE: an app-level `config :brando, Oban` REPLACES this entire default —
  # queues AND the cron jobs below are lost, not merged. Apps overriding it
  # must re-declare any default workers they still want scheduled.
  defp oban_config do
    Application.get_env(:brando, Oban) ||
      [
        repo: Brando.Repo.repo(),
        queues: [
          default: [limit: 1],
          image_processing: [limit: 1],
          # Its own queue on purpose. :default has limit: 1 and also carries the
          # interactive FileUploader/ImageUploader, so a reaper sweep doing one
          # network round trip per abandoned object would block user-facing
          # uploads for as long as it ran.
          upload_reaping: [limit: 1]
        ],
        plugins: [
          {Oban.Plugins.Cron,
           crontab:
             [
               # Generate a Sitemap every night at 02:00 UTC
               {"0 2 * * *", Brando.Worker.SitemapGenerator},
               # Clean up soft deleted entries every night at 03:00 UTC
               {"0 3 * * *", Brando.Worker.SoftDeletePurger},
               # Purge inactive/unprotected revisions older than 14 days
               {"0 4 * * *", Brando.Worker.RevisionPurger},
               # Mark video rows stuck in :uploading as errored (abandoned external uploads)
               {"30 4 * * *", Brando.Worker.VideoUploadReaper},
               # Delete bucket objects of client-direct uploads that never finalized
               {"45 4 * * *", Brando.Worker.UploadIntentReaper}
             ] ++ extra_oban_cron_jobs(),
           timezone: "Etc/UTC"},
          {Oban.Plugins.Pruner, max_age: 300},
          {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(60)}
        ]
      ]
  end

  defp extra_oban_cron_jobs do
    otp_app = Application.get_env(:brando, :otp_app)
    Application.get_env(otp_app, :cron_jobs) || []
  end
end
