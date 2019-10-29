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

config :brando,
  agency_brand: """
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 800">
    <path fill="#312783" d="M587.2 133.8v310.1c0 26.1-4.9 50.5-14.7 73.2-9.8 22.6-23.2 42.3-40.2 59.1s-37 30.1-59.8 39.9c-22.9 9.8-47.1 14.7-72.8 14.7-26.1 0-50.5-4.9-73.1-14.7-22.6-9.8-42.3-23.1-59.2-39.9-16.8-16.8-30.1-36.5-39.9-59.1-9.8-22.6-14.7-47-14.7-73.2V133.8h140v310.1c0 13.5 4.4 24.7 13.3 33.6 8.9 8.9 20.1 13.3 33.6 13.3s24.8-4.4 34-13.3c9.1-8.9 13.6-20.1 13.6-33.6V133.8h139.9zm-352 364c5.6 16.8 13.3 32.2 23.1 46.2l43.4-39.2c-12.6-19.1-18.9-40.6-18.9-64.4V203.8l56-56h-112v296.1c0 19.2 2.8 37.1 8.4 53.9zM343.3 543c16.6 9.6 35.3 14.4 56.3 14.4 16.3 0 31.6-3 45.8-9.1s26.7-14.3 37.5-24.8 19.1-22.9 25.2-37.1c6.1-14.2 9.1-29.5 9.1-45.9V203.8l56-56h-112v296.1c0 17.3-6 31.7-17.8 43.4-11.9 11.7-26.5 17.5-43.8 17.5-13.1 0-24.6-3.4-34.6-10.2s-17.4-15.5-22-26.2l-40.6 36.4c10.7 15.9 24.3 28.6 40.9 38.2z"/>
  </svg>
  """

config :brando, Brando.Images,
  processor_module: Brando.Images.Processor.Sharp,
  default_config: %{
    allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
    default_size: :medium,
    upload_path: Path.join(["images", "site", "default"]),
    random_filename: true,
    size_limit: 10_240_000,
    sizes: %{
      "large" => %{"quality" => 85, "size" => "1400"},
      "medium" => %{"quality" => 85, "size" => "1000"},
      "micro" => %{"crop" => false, "quality" => 25, "size" => "25"},
      "small" => %{"quality" => 85, "size" => "700"},
      "thumb" => %{"crop" => true, "quality" => 85, "size" => "150x150"},
      "xlarge" => %{"quality" => 85, "size" => "1900"}
    },
  }

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
