# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :<%= application_name %>, ecto_repos: [<%= application_module %>.Repo]

# Configures the endpoint
config :<%= application_name %>, <%= application_module %>Web.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: <%= application_module %>Web.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: <%= application_module %>.PubSub,
  live_view: [signing_salt: "<%= lv_signing_salt %>"]

# Additional cron jobs to run
# - Format is `[{"* * * * *", MyApp.Worker.ModuleName}]`
# https://hexdocs.pm/oban/Oban.Plugins.Cron.html
config :<%= application_name %>,
  cron_jobs: []

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason
# config :phoenix, :static_compressors, [Phoenix.Digester.Gzip, Brando.Digester.Brotli]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "brando.exs"
import_config "#{config_env()}.exs"
