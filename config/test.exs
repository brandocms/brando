import Config

config :bcrypt_elixir, log_rounds: 1

config :brando, Brando.Files, cdn: [enabled: false]

# `head_object` and `delete_object` go through `Brando.CDN.Client`; in test that
# is a Mox mock, so an un-stubbed call fails loudly instead of reaching a bucket.
# Those two are what the direct-upload path (presign → verify → finalize → reap)
# needs, which is why they are the ones behind the seam.
#
# It is NOT every S3 call. `cdn.ex:311,354,362` — `s3_upload/7`,
# `ensure_bucket_exists/1` — still reach `ExAws.request` directly, deliberately:
# they move real bytes and create real buckets, so a stub proves nothing about
# them and would hide exactly the integration failures worth catching
# (`client.ex:11-22`). Presigning is outside the seam for a different reason —
# it is an HMAC over local credentials, not a network call at all.
config :brando, :cdn_client, Brando.CDN.Client.Mock

config :brando, Brando.Images,
  cdn: %{enabled: false},
  processor_module: Brando.Images.Processor.Dummy,
  default_config: %{
    allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
    upload_path: Path.join(["images", "site", "default"]),
    default_size: :xlarge,
    random_filename: true,
    size_limit: 10_240_000,
    # micro, thumb, small, medium, large and xlarge; see `Brando.Images.Size`
    sizes: :standard,
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

config :brando, Brando.EditSession, grace_period: 0
config :brando, Brando.Static, cdn: [enabled: false]
config :brando, Brando.Type.Role, roles: %{staff: 1, admin: 2, superuser: 4}
config :brando, Brando.Villain, extra_blocks: []
config :brando, Brando.Villain, parser: Brando.Villain.ParserTest.Parser

# A linked Git worktree (its `.git` is a file) gets its own database, named
# after its directory, so worktrees on different branches never share a schema.
# The main checkout, which is what CI runs, keeps `brando_test`.
# `BRANDO_TEST_DATABASE_URL` overrides both. scripts/worktree-setup derives the
# same name when it creates, migrates and seeds the database.
test_database =
  if File.regular?(Path.expand("../.git", __DIR__)) do
    slug =
      Path.expand("..", __DIR__)
      |> Path.basename()
      |> String.downcase(:ascii)
      |> String.replace(~r/[^a-z0-9_]/, "_")

    String.slice("brando_test_" <> slug, 0, 63)
  else
    "brando_test"
  end

config :brando, BrandoIntegration.Repo,
  url: System.get_env("BRANDO_TEST_DATABASE_URL", "ecto://postgres:postgres@localhost/#{test_database}"),
  pool: Ecto.Adapters.SQL.Sandbox,
  ownership_pool: DBConnection.Poolboy,
  # We don't run a server during test. If one is required,
  # you can enable the server option below.
  pool_overflow: 0

config :brando, BrandoIntegrationWeb.Endpoint,
  http: [port: 80],
  debug_errors: true,
  server: false,
  # Must be >= 64 bytes: the cookie session store rejects anything shorter, and
  # `Brando.LiveCase` dispatches real requests through this endpoint.
  secret_key_base: String.duplicate("verysecret", 8),
  live_view: [signing_salt: "testsigningsalt"],
  pubsub_server: BrandoIntegration.PubSub

config :brando, Oban,
  crontab: false,
  queues: false,
  plugins: false,
  repo: BrandoIntegration.Repo,
  testing: :inline

# Webhook URLs are looked up in a stub, not real DNS (test/support).
config :brando, Brando.Webhooks, resolver: {Brando.WebhookTestResolver, :resolve}

# IndexNow submissions go to a stub.
config :brando, Brando.IndexNow, req_options: [plug: {Req.Test, Brando.IndexNow}]

# 404 counts stay in the buffer until a test flushes them: a periodic flush
# would write from a process outside the test's sandbox.
config :brando, Brando.Sites.FourOhFour, flush_interval: false

# Videos added in tests are not looked up at their source unless a test asks
# for it, and lookups go to a stub.
config :brando, Brando.Videos.Metadata,
  fetch_on_create: false,
  req_options: [plug: {Req.Test, Brando.Videos.Metadata}]

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

# Email is delivered to Swoosh's test adapter; see `Swoosh.TestAssertions`
config :brando, mailer: BrandoIntegration.Mailer
config :brando, BrandoIntegration.Mailer, adapter: Swoosh.Adapters.Test
config :brando, Brando.Mailer, from: {"Brando", "noreply@example.com"}
config :swoosh, :api_client, false

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
