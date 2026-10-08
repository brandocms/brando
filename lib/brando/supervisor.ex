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

    # A misconfigured video provider used to be discovered by the first editor
    # who picked a file. It says so here instead. Logs by default and never
    # blocks boot — see the moduledoc for why, and for the opt-in strict mode.
    Brando.Videos.ProviderConfigCheck.run()

    # Runtime translation configs (Page's) aren't checked by the compiler.
    Brando.Trait.Translatable.check_runtime_config!()

    children = [
      Brando.MarkdownSources.RateLimiter,
      {Task.Supervisor, name: Brando.AI.Agent.Supervisor},
      # Archive restores the admin starts, so they finish (or are undone)
      # when the page that started them is closed
      {Task.Supervisor, name: Brando.Environments.TaskSupervisor},
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
                   args: {Brando.Sites.FourOhFour.buffer_limit(), [], []}
                 )
               ]
             ]
           ]}
      },
      {Oban, oban_config()}
    ]

    # Starts after the cache it reads from, so it stops (flushing once more)
    # before the cache does.
    children = children ++ Brando.Sites.FourOhFour.Flusher.children()

    # One process per entry being edited (see its moduledoc)
    children = children ++ Brando.EditSession.children()

    # Dev only, and only when configured: see its moduledoc
    children = children ++ Brando.Content.Definition.Watcher.children()

    Supervisor.init(children, strategy: :one_for_one)
  end

  # NOTE: an app-level `config :brando, Oban` REPLACES this entire default —
  # queues AND the cron jobs below are lost, not merged. Apps overriding it
  # must re-declare any default workers they still want scheduled.
  #
  # Public only so `Brando.SupervisorTest` can put it through
  # `Oban.Config.new/1`: every environment that runs a test — `config/test.exs`
  # and the e2e config alike — sets `config :brando, Oban`, so this default is
  # the one branch no suite ever reaches.
  @doc false
  def oban_config do
    Application.get_env(:brando, Oban) ||
      [
        repo: Brando.Repo.repo(),
        queues: [
          default: [limit: 1],
          # Copy and live-switch jobs take an advisory lock per site, while a
          # dedicated queue also prevents multiple expensive pg_dump restores
          # from saturating the database host.
          environment_operations: [limit: 1],
          # Static builds are CPU, disk, and network heavy. Serializing them
          # also keeps their versioned output and deploy transitions simple.
          ssg_builds: [limit: 1],
          image_processing: [limit: 1],
          # Its own queue on purpose. :default has limit: 1 and also carries the
          # interactive FileUploader/ImageUploader, so a reaper sweep doing one
          # network round trip per abandoned object would block user-facing
          # uploads for as long as it ran.
          upload_reaping: [limit: 1],
          # Content events go out one at a time, in order; each only queues
          # work for its subscribers (`Brando.ContentEvents`).
          content_events: [limit: 1],
          # Webhook deliveries wait on other servers for up to 10 seconds.
          # Each webhook is limited to `Brando.Webhooks.concurrency/0` of
          # these at a time, so one slow receiver cannot hold them all.
          webhooks: [limit: 5],
          # Slack, Teams and email notifications (`Brando.Notifications.Routing`),
          # apart from webhooks so a burst of them does not hold deliveries up.
          notifications: [limit: 2],
          # The admin search index: one job per changed entry, and rebuilds
          # from Utilities (`Brando.Search`). Two, so a rebuild does not hold
          # up the entries saved meanwhile.
          search_index: [limit: 2]
        ],
        cron: [
          crontab:
            [
              # Generate a Sitemap every night at 02:00 UTC
              {"0 2 * * *", Brando.Worker.SitemapGenerator},
              # Clean up soft deleted entries every night at 03:00 UTC
              {"0 3 * * *", Brando.Worker.SoftDeletePurger},
              # Purge inactive/unprotected revisions older than 30 days
              {"0 4 * * *", Brando.Worker.RevisionPurger},
              {"15 4 * * *", Brando.Worker.DraftPurger},
              # Remove activity events past their retention period
              {"20 4 * * *", Brando.Worker.ActivityPurger},
              # Mark video rows stuck in :uploading as errored (abandoned external uploads)
              {"30 4 * * *", Brando.Worker.VideoUploadReaper},
              # Delete bucket objects of client-direct uploads that never finalized
              {"45 4 * * *", Brando.Worker.UploadIntentReaper},
              # Delete local files no environment has referenced for at least 24 hours
              {"0 5 * * *", Brando.Worker.MediaOrphanCleanup},
              # Delete form submissions older than their form's retention
              {"15 5 * * *", Brando.Worker.FormSubmissionPurger},
              # Delete 404 log rows past their retention period
              {"25 5 * * *", Brando.Worker.NotFoundPurger},
              # Delete webhook deliveries past their retention period
              {"35 5 * * *", Brando.Worker.WebhookDeliveryPurger}
            ] ++ extra_oban_cron_jobs(),
          timezone: "Etc/UTC"
        ],
        pruner: [max_age: 300],
        lifeline: [rescue_after: :timer.minutes(60)]
      ]
  end

  defp extra_oban_cron_jobs do
    otp_app = Application.get_env(:brando, :otp_app)
    Application.get_env(otp_app, :cron_jobs) || []
  end
end
