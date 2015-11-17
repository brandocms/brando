# Default generated Brando configuration

use Mix.Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :eightyfour,
  credentials: "priv/google_token/token.json",
  private_key: "priv/google_token/token.key.pem",
  # find your view_id in your analytics url:
  # https://www.google.com/analytics/web/#management/Settings/a000w000pVIEW_ID/
  google_view_id: "XXXXXX",
  start_date: "2010-01-01",
  token_lifetime: 3600,
  token_provider: Eightyfour.AccessToken

config :brando,
  app_name: "<%= application_module %>",
  endpoint: <%= application_module %>.Endpoint,
  log_dir: Path.Expand("./logs"),
  default_language: "en",
  languages: [[value: "nb", text: "Norsk"],
              [value: "en", text: "English"]],
  default_admin_language: "nb",
  admin_languages: [[value: "nb", text: "Norsk"],
                    [value: "en", text: "English"]],
  status_choices: [no: [[value: "0", text: "Kladd"],
                        [value: "1", text: "Publisert"],
                        [value: "2", text: "Venter"],
                        [value: "3", text: "Slettet"]],
                   en: [[value: "0", text: "Draft"],
                        [value: "1", text: "Published"],
                        [value: "2", text: "Pending"],
                        [value: "3", text: "Deleted"]]],
  lockdown: true,
  mailgun_domain: "https://api.mailgun.net/v3/mydomain.com",
  mailgun_key: "key-##############",
  media_path: "",
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
      "micro" =>  %{"size" => "25x25", "quality" => 100, "crop" => true}}
  },
  optimize: [
    png: [
      bin: "/usr/local/bin/pngquant",
      args: "--speed 1 --force --output %{new_filename} -- %{filename}"]]


config :brando, Brando.Instagram,
  client_id: "",
  auto_approve: true,
  http_lib: Brando.Instagram.API,
  interval: 1_000 * 60 * 60,
  sleep: 5000,
  sizes: %{"large" =>  %{"size" => "640", "quality" => 100},
           "thumb" =>  %{"size" => "150x150", "quality" => 100,
                         "crop" => true}},
  upload_path: Path.join("images", "instagram")

config :brando, Brando.Type.Role,
  roles: %{staff: 1, admin: 2, superuser: 4}

config :brando, Brando.Menu,
  colors: ["#FBA026;", "#F87117;", "#CF3510;", "#890606;", "#FF1B79;",
           "#520E24;", "#8F2041;", "#DC554F;", "#FF905E;", "#FAC51C;",
           "#D6145F;", "#AA0D43;", "#7A0623;", "#430202;", "#500422;",
           "#870B46;", "#D0201A;", "#FF641A;"],
  modules: [Brando.Menu.Admin, Brando.Menu.Users, Brando.Menu.News,
            Brando.Menu.Pages, Brando.Menu.Images]

config :brando, Brando.Villain,
  parser: <%= application_module %>.Villain.Parser,
  extra_blocks: []
