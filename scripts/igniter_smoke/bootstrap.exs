[framework, database, mode, port] = System.argv()
true = mode in ["none", "single", "multi"]
true = String.starts_with?(database, "brando_igniter_smoke_")

mix = File.read!("mix.exs")
marker = "defp deps do\n    ["
true = String.contains?(mix, marker)
deps = "#{marker}\n      {:brando, path: #{inspect(framework)}},\n      {:igniter, \"~> 0.8.0\", only: [:dev, :test]},"
File.write!("mix.exs", String.replace(mix, marker, deps, global: false))

# A new database name is allocated for every run. No existing application
# configuration or database is read or reused by this consumer.
config = """

config :igniter_smoke, IgniterSmoke.Repo,
  hostname: #{inspect(System.get_env("BRANDO_SMOKE_PGHOST", "127.0.0.1"))},
  port: #{String.to_integer(System.fetch_env!("BRANDO_SMOKE_PGPORT"))},
  username: #{inspect(System.get_env("BRANDO_SMOKE_PGUSER", "postgres"))},
  password: #{inspect(System.get_env("BRANDO_SMOKE_PGPASSWORD", "postgres"))},
  database: #{inspect(database)},
  template: "template0",
  pool_size: 10

config :igniter_smoke, IgniterSmokeWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: #{String.to_integer(port)}],
  check_origin: false

config :logger, level: :warning
"""

File.write!("config/dev.exs", File.read!("config/dev.exs") <> config)
File.write!(".igniter-smoke-mode", mode)
