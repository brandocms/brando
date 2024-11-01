import Config

config :e2e_project, E2eProjectWeb.Endpoint,
  secret_key_base: System.get_env("BRANDO_SECRET_KEY_BASE"),
  http: [:inet6, port: System.get_env("PORT")],
  url: [
    scheme: System.get_env("BRANDO_URL_SCHEME"),
    host: System.get_env("BRANDO_URL_HOST"),
    port: System.get_env("BRANDO_URL_PORT")
  ]

if config_env() not in [:test, :e2e] do
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
