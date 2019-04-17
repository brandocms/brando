# Default generated Brando configuration

use Mix.Config

config :<%= application_name %>, ecto_repos: [<%= application_module %>.Repo]
config :<%= application_name %>, hmr: true

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :brando,
  app_name: "<%= application_module %>",
  title_prefix: "<%= application_module %> | ",
  endpoint: <%= application_module %>Web.Endpoint,
  otp_app: :<%= application_name %>,
  log_dir: Path.expand("./log"),
  default_language: "en",
  languages: [
    [value: "nb", text: "Norsk"],
    [value: "en", text: "English"]
  ],
  default_admin_language: "nb",
  admin_languages: [
    [value: "nb", text: "Norsk"],
    [value: "en", text: "English"]
  ],
  lockdown: true,
  lockdown_password: "<%= :os.timestamp |> :erlang.phash2 |> Integer.to_string(32) |> String.downcase %>",
  mailgun_domain: "https://api.mailgun.net/v3/mydomain.com",
  mailgun_key: "key-##############",
  media_path: Path.expand("./media"),
  media_url: "/media",
  repo: <%= application_module %>.Repo,
  factory: <%= application_module %>.Factory,
  router: <%= application_module %>Web.Router,
  helpers: <%= application_module %>Web.Router.Helpers,
  warn_on_http_auth: false,
  stats_polling_interval: 5000

config :brando, Brando.Images,
  default_config: %{
    allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
    default_size: :medium,
    upload_path: Path.join(["images", "site", "default"]),
    random_filename: true,
    size_limit: 10_240_000,
    sizes: %{
      "large" => %{"quality" => 85, "size" => "1400"},
      "medium" => %{"quality" => 85, "size" => "1000"},
      "micro" => %{"crop" => true, "quality" => 85, "size" => "25x25"},
      "small" => %{"quality" => 85, "size" => "700"},
      "thumb" => %{"crop" => true, "quality" => 85, "size" => "150x150"},
      "xlarge" => %{"quality" => 85, "size" => "1900"}
    },
  },
  optimize: [
    png: [
      bin: "/usr/local/bin/pngquant",
      args: "--speed 1 --force --output %{new_filename} -- %{filename}"
    ]
  ]

config :brando, Brando.Type.Role,
  roles: %{staff: 1, admin: 2, superuser: 4}

config :brando, Brando.Villain,
  extra_blocks: [],
  parser: <%= application_module %>.Villain.Parser

# Configure Guardian for auth.
config :<%= application_name %>, <%= application_module %>Web.Guardian,
  issuer: "<%= application_module %>",
  ttl: {30, :days},
  secret_key: "<%= :crypto.strong_rand_bytes(64) |> Base.encode64 |> binary_part(0, 64) %>"

# Configure Eightyfour for interfacing with Google Analytics
# config :eightyfour,
#   credentials: "priv/tokens/google/token.json",
#   private_key: "priv/tokens/google/token.key.pem",
#   # find your view_id in your analytics url:
#   # https://www.google.com/analytics/web/#management/Settings/a000w000pVIEW_ID/
#   google_view_id: "XXXXXX",
#   start_date: "2010-01-01",
#   token_lifetime: 3600,
#   token_provider: Eightyfour.AccessToken
