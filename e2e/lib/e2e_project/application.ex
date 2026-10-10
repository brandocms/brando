defmodule E2eProject.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)
    Brando.Tracing.LiveView.setup()
    E2eProject.O11y.OpenTelemetryEcto.setup(E2eProject.Repo.config()[:telemetry_prefix], db_statement: :enabled)
    # No OpentelemetryOban: e2e runs Oban's inline engine, whose jobs have no
    # scheduled_at, and its job_start handler crashes on that and is detached.
    maybe_start_coverage()

    # List all child processes to be supervised
    children = [
      # Start the Ecto repository
      E2eProject.Repo,
      # Start the Telemetry supervisor
      E2eProjectWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: E2eProject.PubSub},
      # Start the Endpoint (http/https)
      E2eProjectWeb.Endpoint,
      # Start the Presence system
      E2eProject.Presence,
      # Start the Brando supervisor
      Brando,
      # Start rate limiters for API endpoints
      BrandoJsonApi.RateLimit,
      BrandoGraphql.RateLimit
      # Start a worker by calling: E2eProject.Worker.start_link(arg)
      # {E2eProject.Worker, arg},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: E2eProject.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Handle sandbox mode for e2e tests
    # See: https://tilcodes.fly.dev/flaky-playwright-tests-and-phoenix-a-distributed-systems-problem/
    #
    # There are TWO separate app instances in e2e testing:
    # 1. Seeding instance: `mix run priv/repo/e2e_seeds.exs` - needs DB access to seed
    # 2. Test serving instance: `mix phx.server` started by Playwright - uses /sandbox plug
    #
    # CRITICAL: For seeding, we use `sandbox: false` to get a REAL connection that commits.
    # Using {:shared, self()} would wrap in a transaction that rolls back when the process exits!
    if Application.get_env(:e2e_project, :sql_sandbox) do
      if System.get_env("BRANDO_SEEDING") do
        # Seeding mode: checkout a REAL connection (not transactional) so data persists
        # The sandbox: false option means changes are committed immediately, not rolled back
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(E2eProject.Repo, sandbox: false)
        Ecto.Adapters.SQL.Sandbox.mode(E2eProject.Repo, {:shared, self()})
        Brando.System.initialize()
      else
        # Test serving mode: Set sandbox to auto mode so initialization queries
        # can run without explicit checkout. The per-test sandbox sessions will
        # override this with their own connections.
        #
        # CAVEAT: in :auto mode, processes spawned mid-request (e.g. Ecto's
        # parallel preload Tasks) get fresh connections OUTSIDE the test's
        # sandbox transaction and silently read stale data. Brando's repo
        # facade therefore forces `in_parallel: false` on preloads when
        # `config :brando, :sql_sandbox_serial_preloads` is set (e2e.exs).
        Ecto.Adapters.SQL.Sandbox.mode(E2eProject.Repo, :auto)
        Brando.System.initialize()
      end
    else
      # Normal mode (dev/prod): always initialize
      Brando.System.initialize()
    end

    announce_server()
    result
  end

  # The E2E logger runs at :warning, which hides Phoenix's "Running ... at"
  # line, so say when the server is up at any level. test_e2e.sh polls the
  # port and prints the same line itself, and sets BRANDO_E2E_QUIET_READY=1.
  # The seeding instance also listens (e2e.exs sets `server: true`) but is not
  # the server anyone waits for.
  defp announce_server do
    with true <- Phoenix.Endpoint.server?(:e2e_project, E2eProjectWeb.Endpoint),
         nil <- System.get_env("BRANDO_SEEDING"),
         false <- System.get_env("BRANDO_E2E_QUIET_READY") == "1",
         {:ok, {_ip, port}} <- E2eProjectWeb.Endpoint.server_info(:http) do
      IO.puts("E2E server ready on :#{port}")
    end
  end

  def stop(_state) do
    if coverage_enabled?() do
      path = coverage_export_path()
      File.mkdir_p!(Path.dirname(path))
      :ok = :cover.export(String.to_charlist(path))
    end

    :ok
  end

  # Measures which Brando code the E2E suite reaches. Opt in with
  # BRANDO_E2E_COVER=1; the data is exported to BRANDO_E2E_COVER_EXPORT
  # (default ../cover/e2e.coverdata) when the server shuts down, where
  # `mix test.coverage` in the Brando root merges it with unit-test data.
  # The seeding instance is skipped: only the server the tests drive counts.
  #
  # On OTP 27+ the JIT counts lines natively. Measured on the block-editor
  # bench (2026-10-02): mount, edit, insert and save times were unchanged;
  # boot went from 3s to 16s (cover-compiling ~1200 modules) and shutdown
  # from 1s to 8s (writing the export).
  defp maybe_start_coverage do
    if coverage_enabled?() do
      {:ok, _} = :cover.start()

      Application.app_dir(:brando, "ebin")
      |> String.to_charlist()
      |> :cover.compile_beam_directory()
    end
  end

  defp coverage_enabled? do
    System.get_env("BRANDO_E2E_COVER") in ["1", "true"] and
      is_nil(System.get_env("BRANDO_SEEDING"))
  end

  defp coverage_export_path do
    System.get_env("BRANDO_E2E_COVER_EXPORT") ||
      Path.expand("../cover/e2e.coverdata", File.cwd!())
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    E2eProjectWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
