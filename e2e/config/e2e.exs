import Config

import_config "test.exs"
# Use :warning to reduce log noise, change to :debug for troubleshooting
config :logger, level: :warning
config :e2e_project, sql_sandbox: true

# Override pool settings for e2e tests - need more connections for
# browser tests with LiveView (HTTP + WebSocket + sandbox per test)
# Using a large pool to diagnose connection leaks
config :e2e_project, E2eProject.Repo,
  pool_size: 50,
  queue_target: 5000,
  queue_interval: 10000

config :e2e_project, E2eProjectWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4444],
  server: true

config :brando, Oban,
  repo: E2eProject.Repo,
  queues: false,
  plugins: false,
  testing: :inline

config :e2e_project, hmr: false
config :phoenix, :stacktrace_depth, 60

# Show breakpoint debug in frontend
config :e2e_project, show_breakpoint_debug: false
