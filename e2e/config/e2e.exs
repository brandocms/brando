import Config

import_config "test.exs"

e2e_port =
  System.get_env("BRANDO_E2E_PORT", System.get_env("PORT", "4444"))
  |> String.to_integer()

default_pool_size = if System.get_env("CI"), do: "50", else: "20"
e2e_pool_size = String.to_integer(System.get_env("BRANDO_E2E_POOL_SIZE", default_pool_size))

# Use :warning to reduce log noise, change to :debug for troubleshooting
config :logger, level: :warning

# In the sandboxed e2e server, Ecto's parallel preload Tasks would escape the
# per-test sandbox transaction (see application.ex) — run preloads serially.
config :brando, :sql_sandbox_serial_preloads, true
config :e2e_project, sql_sandbox: true

# Each test runs in its own rolled-back sandbox, but entry ids repeat across
# tests (the seeded pages). An edit session that outlived its test would hand
# its unsaved state to the next test that opens the same entry, so sessions
# stop as soon as their last editor leaves.
config :brando, Brando.EditSession, grace_period: 0

# Recorded 404s wait in a buffer (the `:four_oh_four` cache) until they are
# written to `sites_not_found_hits`. The periodic flusher runs outside every
# test's sandbox, so a flush between a test's request and its read would
# take the hits into a transaction nobody sees. Without it, the reader
# flushes into its own test's sandbox (`Brando.Sites.FourOhFour.list/0`), and
# the endpoint empties the buffer when a test checks out its sandbox.
config :brando, Brando.Sites.FourOhFour, flush_interval: false

# Override pool settings for e2e tests - need more connections for
# browser tests with LiveView (HTTP + WebSocket + sandbox per test)
# CI keeps the historical pool size. Local runs default lower so multiple
# worktrees fit within PostgreSQL's usual 100-connection limit.
config :e2e_project, E2eProject.Repo,
  pool_size: e2e_pool_size,
  queue_target: 5000,
  queue_interval: 10000

config :e2e_project, E2eProjectWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: e2e_port],
  server: true

config :brando, Oban,
  repo: E2eProject.Repo,
  queues: false,
  plugins: false,
  testing: :inline

config :e2e_project, hmr: false

# Webhooks call the E2E server's own test receiver (`/e2e/webhook-receiver`)
# over http on localhost. Development and E2E only: never in production.
config :brando, Brando.Webhooks, allow_localhost: true

# IndexNow submits to the same receiver, under the `indexnow` inbox, instead
# of api.indexnow.org.
config :brando, Brando.IndexNow,
  endpoint: "http://localhost:#{e2e_port}/e2e/webhook-receiver/indexnow",
  req_options: []

# The E2E MCP client's metadata document comes from the test suite, not the
# internet (Brando.MCP.ClientMetadata).
config :brando, Brando.MCP, client_metadata_fetcher: {E2eProject.MCPClient, :fetch}

# Email sent while the tests run (form notifications, password reset links)
# is kept in Swoosh's in-memory mailbox, where `/e2e/password-reset/mailbox`
# reads it back for the browser.
config :e2e_project, E2eProject.Mailer, adapter: Swoosh.Adapters.Local

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

config :brando,
  authorization_mode: if(System.get_env("BRANDO_AUTHORIZATION_MODE") == "groups", do: :groups, else: :legacy)

config :brando,
  tenancy_mode:
    (case System.get_env("BRANDO_TENANCY_MODE") do
       "multi" -> :multi
       "single" -> :single
       _ -> :none
     end),
  site_key: "auth-alpha"

# Test-only public GitHub provider; requests still traverse the real signed endpoint.
# Every spec signs in from 127.0.0.1, so the per-address limits would add up
# over a run; the per-account limits and the lockout stay as in production.
config :brando, Brando.Users.Throttle, login_per_ip: 10_000, two_factor_per_ip: 10_000, reset_per_ip: 10_000

config :brando, :markdown_sources,
  connections: %{
    "e2e-docs" => %{
      repository: "brando-e2e/docs",
      repository_id: 2582,
      secret: "e2e-markdown-webhook-secret-do-not-use-in-production",
      destinations: [nil]
    }
  }

config :brando, :markdown_sources_provider, E2E.MarkdownProvider

