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
    Brando.Content.Definitions.ReleaseStatus.init_cache()
    Brando.Content.Definitions.Release.Verify.init_table()

    # A misconfigured video provider says so here, at boot, rather than to the
    # first editor who picks a file. Logs by default and never blocks boot —
    # see the moduledoc for why, and for the opt-in strict mode.
    Brando.Videos.ProviderConfigCheck.run()

    # Runtime translation configs (Page's) aren't checked by the compiler.
    Brando.Trait.Translatable.check_runtime_config!()

    load_native_code!()

    Supervisor.init(children(), strategy: :one_for_one)
  end

  @doc "The supervisor's children, in the order they start."
  def children do
    children = [
      Brando.MarkdownSources.RateLimiter,
      Brando.MarkdownSources.SignatureCheck,
      Brando.MarkdownSources.ReadSlots,
      Brando.MarkdownSources.GitHubAddresses,
      {Task.Supervisor, name: Brando.AI.Agent.Supervisor},
      # Archive restores the admin starts, so they finish (or are undone)
      # when the page that started them is closed
      {Task.Supervisor, name: Brando.Environments.TaskSupervisor},
      # Release Verify's dry runs, which outlive the page that started them
      Brando.Content.Definitions.Release.Verify,
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
      # Before Oban, so it hears the first job that reports (BrandoAdmin.Work)
      BrandoAdmin.Work.Registry,
      # Refreshes this node's site and environment caches when another node
      # writes them
      Brando.CacheSync,
      # Tells who follows a static site's builds that its content changed,
      # and records a change made in a transaction begun on the repo itself
      # once that has ended
      Brando.SSG.ContentChanges,
      {Task.Supervisor, name: Brando.SSG.ContentChanges.TaskSupervisor},
      # Keeps the file of hosts the reverse proxy serves; idle without a file
      # configured (`Brando.Tenant.ServedHosts`), and its DNS lookups
      {Task.Supervisor, name: Brando.Tenant.ServedHosts.TaskSupervisor},
      Brando.Tenant.ServedHosts
    ]

    # Starts after the cache it reads from, so it stops (flushing once more)
    # before the cache does.
    children = children ++ Brando.Sites.FourOhFour.Flusher.children()

    # Each site's request counters on this node, with `tenancy_mode: :multi`,
    # written on an interval and once more as the node stops
    children = children ++ Brando.Sites.Usage.Traffic.children()

    # One process per entry being edited (see its moduledoc)
    children = children ++ Brando.EditSession.children()

    # Dev only, and only when configured: see its moduledoc
    children = children ++ Brando.Content.Definition.Watcher.children()

    # Plans the release's module definitions when `release_path` is
    # configured: after boot where this node serves, and after a change made
    # on this node
    children = children ++ Brando.Content.Definitions.ReleaseStatus.children()

    # Last, so it stops first: the node serves with the rest while Oban lets
    # the jobs it is running finish (its `shutdown_grace_period`)
    children ++ [{Oban, oban_config()}]
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
        queues:
          [
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
          ] ++ site_usage_queue(),
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
              {"35 5 * * *", Brando.Worker.WebhookDeliveryPurger},
              # Publish and expire entries whose dates passed with no job (clones, restores)
              {"*/10 * * * *", Brando.Worker.ScheduledPublishingSweep}
            ] ++ site_usage_cron() ++ extra_oban_cron_jobs(),
          timezone: "Etc/UTC"
        ],
        pruner: [max_age: 300],
        lifeline: [rescue_after: :timer.minutes(60)]
      ]
  end

  # Measures what each site stores and prunes old usage rows
  # (`Brando.Worker.SiteUsage`), with `tenancy_mode: :multi` only: in a queue
  # of its own, so a long walk of the folders holds nothing else up
  defp site_usage_queue, do: if(Brando.Sites.Usage.enabled?(), do: [site_usage: [limit: 1]], else: [])

  defp site_usage_cron,
    do: if(Brando.Sites.Usage.enabled?(), do: [{"45 5 * * *", Brando.Worker.SiteUsage, args: %{"all" => true}}], else: [])

  defp extra_oban_cron_jobs do
    otp_app = Application.get_env(:brando, :otp_app)
    Application.get_env(otp_app, :cron_jobs) || []
  end

  # Modules with native code load it when the module loads. An interactive
  # release loads a module on first use, so a library this server cannot load
  # (a missing or mismatched system library) would first fail an editor's
  # login, upload or Markdown preview, after a blue/green switch has already
  # stopped the old colour. Loading them here fails the boot instead, as an
  # embedded release does.
  @native_modules [Bcrypt.Base, Vix.Nif, MDExNative.Native]

  @doc "The modules with native code that boot loads."
  def native_modules, do: @native_modules

  # A module a dependency update renamed is skipped rather than stopping
  # every site's boot; Brando's tests check the list. An embedded release has
  # loaded every module it has, and answers :embedded for one it lacks.
  defp load_native_code! do
    Enum.each(@native_modules, fn module ->
      case Code.ensure_loaded(module) do
        {:module, ^module} -> :ok
        {:error, reason} when reason in [:nofile, :embedded] -> :ok
        {:error, reason} -> raise "#{inspect(module)} could not load its native code: #{inspect(reason)}"
      end
    end)
  end
end
