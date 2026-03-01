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

# Minimal image sizes for faster uploads in e2e tests.
# Core code now uses :largest (resolved dynamically) so we can safely
# drop medium/large/xlarge. 3 sizes × 1 format vs the default 6 × 2.
config :brando, Brando.Images,
  processor_module: Brando.Images.Processor.Vix,
  default_config: %{
    allowed_mimetypes: [
      "image/jpeg",
      "image/png",
      "image/gif",
      "image/avif",
      "image/webp",
      "image/svg+xml"
    ],
    upload_path: Path.join(["images", "site", "default"]),
    default_size: :largest,
    random_filename: true,
    size_limit: 10_240_000,
    sizes: %{
      "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
      "thumb" => %{"size" => "400x400>", "quality" => 75, "crop" => true},
      "small" => %{"size" => "700", "quality" => 75}
    },
    srcset: %{
      default: [
        {"small", "700w"}
      ]
    }
  },
  default_srcset: %{
    default: [
      {"small", "700w"}
    ]
  }
config :phoenix, :stacktrace_depth, 60

# Show breakpoint debug in frontend
config :e2e_project, show_breakpoint_debug: false
