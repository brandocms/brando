import Config

import_config "test.exs"

config :<%= application_name %>, sql_sandbox: true
config :<%= application_name %>, <%= application_module %>Web.Endpoint,
  http: [port: 4444],
  server: true

config :brando, Oban,
  repo: <%= application_module %>.Repo,
  queues: false,
  plugins: false
