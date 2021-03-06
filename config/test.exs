use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :brando, BrandoIntegrationWeb.Endpoint,
  http: [port: 80],
  server: false,
  secret_key_base: "verysecret",
  pubsub_server: BrandoIntegration.PubSub

config :brando, BrandoIntegration.Repo,
  url: "ecto://postgres:postgres@localhost/brando_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  ownership_pool: DBConnection.Poolboy,
  pool_overflow: 0

config :brando, Brando.Images,
  commands_module: BrandoIntegration.Processor.Commands,
  default_config: %{
    allowed_mimetypes: ["image/jpeg", "image/png"],
    default_size: "medium",
    size_limit: 10_240_000,
    upload_path: Path.join("images", "default"),
    sizes: %{
      "small" => %{"size" => "300", "quality" => 70},
      "medium" => %{"size" => "500", "quality" => 70},
      "large" => %{"size" => "700", "quality" => 70},
      "xlarge" => %{"size" => "900", "quality" => 70},
      "thumb" => %{"size" => "150x150", "quality" => 70, "crop" => true},
      "micro" => %{"size" => "25x25", "quality" => 70, "crop" => true}
    }
  }

config :brando, :env, :test
config :brando, :app_name, "MyApp"
config :brando, :auth_sleep_duration, 0
config :brando, :app_module, BrandoIntegration
config :brando, :web_module, BrandoIntegrationWeb
config :brando, :media_url, "/media"
config :brando, :media_path, Path.join([Mix.Project.app_path(), "tmp", "media"])
config :brando, :log_dir, Path.expand("./tmp/logs")
config :brando, :logging, disable_logging: true
config :brando, :login_url, "/login"
config :brando, :otp_app, :brando
config :brando, :warn_on_http_auth, true
config :brando, :default_language, "no"
config :brando, :default_admin_language, "no"

config :brando, Oban,
  crontab: false,
  queues: false,
  plugins: false,
  repo: BrandoIntegration.DummyRepo

config :brando, :languages, [
  [value: "no", text: "Norsk"],
  [value: "en", text: "English"]
]

config :brando, :admin_languages, [
  [value: "no", text: "Norsk"],
  [value: "en", text: "English"]
]

config :brando, Brando.Villain, parser: Brando.Villain.ParserTest.Parser
config :brando, Brando.Villain, extra_blocks: []

config :brando, Brando.Type.Role, roles: %{staff: 1, admin: 2, superuser: 4}

config :bcrypt_elixir, log_rounds: 1

# Print only warnings and errors during test
config :logger, level: :warn
