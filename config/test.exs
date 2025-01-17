import Config

config :bcrypt_elixir, log_rounds: 1

config :brando, Brando.Files, cdn: [enabled: false]

config :brando, Brando.Images,
  cdn: %{enabled: false},
  processor_module: Brando.Images.Processor.Dummy,
  default_config: %{
    allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
    upload_path: Path.join(["images", "site", "default"]),
    default_size: :xlarge,
    random_filename: true,
    size_limit: 10_240_000,
    sizes: %{
      "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
      "thumb" => %{"size" => "400x400>", "quality" => 75, "crop" => true},
      "small" => %{"size" => "700", "quality" => 75},
      "medium" => %{"size" => "1100", "quality" => 75},
      "large" => %{"size" => "1700", "quality" => 75},
      "xlarge" => %{"size" => "2100", "quality" => 75}
    },
    srcset: %{
      default: [
        {"small", "700w"},
        {"medium", "1100w"},
        {"large", "1700w"},
        {"xlarge", "2100w"}
      ]
    }
  },
  default_srcset: %{
    default: [
      {"small", "700w"},
      {"medium", "1100w"},
      {"large", "1700w"},
      {"xlarge", "2100w"}
    ]
  }

config :brando, Brando.Static, cdn: [enabled: false]
config :brando, Brando.Type.Role, roles: %{staff: 1, admin: 2, superuser: 4}
config :brando, Brando.Villain, extra_blocks: []
config :brando, Brando.Villain, parser: Brando.Villain.ParserTest.Parser

config :brando, BrandoIntegration.Repo,
  url: "ecto://postgres:postgres@localhost/brando_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  ownership_pool: DBConnection.Poolboy,
  # We don't run a server during test. If one is required,
  # you can enable the server option below.
  pool_overflow: 0

config :brando, BrandoIntegrationWeb.Endpoint,
  http: [port: 80],
  debug_errors: true,
  server: false,
  secret_key_base: "verysecret",
  pubsub_server: BrandoIntegration.PubSub

config :brando, Oban,
  crontab: false,
  queues: false,
  plugins: false,
  repo: BrandoIntegration.Repo,
  testing: :inline

config :brando, :admin_languages, [
  [value: "no", text: "Norsk"],
  [value: "en", text: "English"]
]

config :brando, :admin_module, BrandoIntegrationAdmin
config :brando, :app_module, BrandoIntegration
config :brando, :app_name, "MyApp"
config :brando, :auth_sleep_duration, 0
config :brando, :default_admin_language, "en"
config :brando, :default_language, "en"
config :brando, :ecto_repos, [BrandoIntegration.Repo]
config :brando, :env, :test

config :brando, :languages, [
  [value: "no", text: "Norsk"],
  [value: "en", text: "English"]
]

config :brando, :log_dir, Path.expand("./tmp/logs")
config :brando, :logging, disable_logging: true
config :brando, :login_url, "/login"
config :brando, :media_path, Path.join([Mix.Project.app_path(), "tmp", "media"])
config :brando, :media_url, "/media"
config :brando, :otp_app, :brando
config :brando, :repo_module, BrandoIntegration.Repo
config :brando, :warn_on_http_auth, true
config :brando, :web_module, BrandoIntegrationWeb
config :brando, scope_default_language_routes: true

# Print only warnings and errors during test
config :logger, level: :error

config :phoenix, :stacktrace_depth, 30
