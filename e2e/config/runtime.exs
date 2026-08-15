import Config

runtime_port =
  System.get_env("BRANDO_E2E_PORT", System.get_env("PORT", "4444"))
  |> String.to_integer()

url_port =
  System.get_env("BRANDO_URL_PORT", Integer.to_string(runtime_port))
  |> String.to_integer()

config :e2e_project, E2eProjectWeb.Endpoint,
  secret_key_base: System.get_env("BRANDO_SECRET_KEY_BASE"),
  http: [:inet6, port: runtime_port],
  url: [
    scheme: System.get_env("BRANDO_URL_SCHEME", "http"),
    host: System.get_env("BRANDO_URL_HOST", "localhost"),
    port: url_port
  ]

if config_env() not in [:test, :e2e] do

  require Logger
  Logger.error "==> Starting E2E Project in #{config_env()} environment"

  config :e2e_project, E2eProject.Repo,
    url: System.get_env("BRANDO_DB_URL"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "15")
end

config :brando, default_language: System.get_env("BRANDO_DEFAULT_LANGUAGE", "no")
config :brando, default_admin_language: "no"

config :brando, Brando.Images, cdn: [
  enabled: false,
  bucket: "e2e_project"
]

config :brando, Brando.Files, cdn: [
  enabled: false,
  bucket: "e2e_project"
]

config :brando, Brando.Static, cdn: [
  enabled: false,
  bucket: "e2e_project"
]
