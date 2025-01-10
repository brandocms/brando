import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :e2e_project, E2eProject.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "e2e_project_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :e2e_project, E2eProjectWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ngv3Man7Y6Z2hZhsjWuEoVmZNnVIdoaHFtTzeKNCiIdvs/7vavFhxK1LnmRZ+Nko",
  server: false

# In test we don't send emails
config :e2e_project, E2eProject.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :debug

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

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
