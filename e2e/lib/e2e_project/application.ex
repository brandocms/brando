defmodule E2eProject.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
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
        Ecto.Adapters.SQL.Sandbox.mode(E2eProject.Repo, :auto)
        Brando.System.initialize()
      end
    else
      # Normal mode (dev/prod): always initialize
      Brando.System.initialize()
    end

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    E2eProjectWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
