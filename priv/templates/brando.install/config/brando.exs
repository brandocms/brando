# Default generated Brando configuration

use Mix.Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :eightyfour,
  credentials: "priv/tokens/google/token.json",
  private_key: "priv/tokens/google/token.key.pem",
  # find your view_id in your analytics url:
  # https://www.google.com/analytics/web/#management/Settings/a000w000pVIEW_ID/
  google_view_id: "XXXXXX",
  start_date: "2010-01-01",
  token_lifetime: 3600,
  token_provider: Eightyfour.AccessToken

config :brando,
  app_name: "<%= application_module %>",
  endpoint: <%= application_module %>.Endpoint,
  otp_app: :<%= application_name %>,
  log_dir: Path.expand("./logs"),
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
  router: <%= application_module %>.Router,
  helpers: <%= application_module %>.Router.Helpers

config :brando, Brando.Images,
  default_config: %{
    allowed_mimetypes: ["image/jpeg", "image/png"],
    default_size: :medium,
    upload_path: Path.join("images", "default"),
    random_filename: true,
    size_limit: 10240000,
    sizes: %{
      "small" =>  %{"size" => "300", "quality" => 100},
      "medium" => %{"size" => "500", "quality" => 100},
      "large" =>  %{"size" => "700", "quality" => 100},
      "xlarge" => %{"size" => "900", "quality" => 100},
      "thumb" =>  %{"size" => "150x150", "quality" => 100, "crop" => true},
      "micro" =>  %{"size" => "25x25", "quality" => 100, "crop" => true}
    }
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
