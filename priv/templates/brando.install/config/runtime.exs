import Config

config :<%= application_name %>, <%= application_module %>Web.Endpoint,
  secret_key_base: System.get_env("BRANDO_SECRET_KEY_BASE"),
  http: [:inet6, port: System.get_env("PORT")],
  url: [
    scheme: System.get_env("BRANDO_URL_SCHEME"),
    host: System.get_env("BRANDO_URL_HOST"),
    port: System.get_env("BRANDO_URL_PORT")
  ]

config :<%= application_name %>, <%= application_module %>.Repo,
  url: System.get_env("BRANDO_DB_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "15")

config :brando, default_language: System.get_env("BRANDO_DEFAULT_LANGUAGE", "no")
config :brando, default_admin_language: "no"

config :brando, Brando.Images, cdn: [
  enabled: false,
  bucket: "<%= application_name %>"
]

config :brando, Brando.Files, cdn: [
  enabled: false,
  bucket: "<%= application_name %>"
]

config :brando, Brando.Static, cdn: [
  enabled: false,
  bucket: "<%= application_name %>"
]
