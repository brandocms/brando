# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

config :brando, ecto_repos: [BrandoIntegration.Repo]
config :phoenix, :json_library, Jason

# These are defaults for internals, mostly overridden for testing
# purposes. We put them here to not pollute the brando.exs file.
config :brando,
  auth_sleep_duration: 2_000,
  otp_app: :brando

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
