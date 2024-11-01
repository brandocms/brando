import Config

import_config "test.exs"

config :e2e_project, sql_sandbox: true

config :e2e_project, E2eProjectWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4444],
  server: true

config :brando, Oban,
  repo: E2eProject.Repo,
  queues: false,
  plugins: false,
  testing: :inline

  # Ensure no HMR in prod :)
config :e2e_project, hmr: false

# Show breakpoint debug in frontend
config :e2e_project, show_breakpoint_debug: false
