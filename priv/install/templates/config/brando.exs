# Default generated Brando configuration

use Mix.Config

config :logger,
  backends: [{LoggerFileBackend, :error_log}, :console]

config :logger, :error_log,
  path: "logs/app_error.log",
  level: :error

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :brando,
  app_name: "<%= application_module %>",
  endpoint: <%= application_module %>.Endpoint,
  default_language: "en",
  languages: [[value: "nb", text: "Norsk"],
              [value: "en", text: "English"]],
  default_admin_language: "no",
  admin_languages: [[value: "no", text: "Norsk"],
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
  media_path: Path.join([Mix.Project.app_path, "priv", "media"]),
  media_url: "/media",
  repo: <%= application_module %>.Repo,
  router: <%= application_module %>.Router,
  helpers: <%= application_module %>.Router.Helpers

config :brando, Brando.Images,
  default_config: %{allowed_mimetypes: ["image/jpeg", "image/png"],
                    default_size: :medium,
                    upload_path: Path.join("images", "default"),
                    random_filename: true,
                    size_limit: 10240000,
                    sizes: %{"small" =>  %{"size" => "300", "quality" => 100},
                             "medium" => %{"size" => "500", "quality" => 100},
                             "large" =>  %{"size" => "700", "quality" => 100},
                             "xlarge" => %{"size" => "900", "quality" => 100},
                             "thumb" =>  %{"size" => "150x150", "quality" => 100, "crop" => true},
                             "micro" =>  %{"size" => "25x25", "quality" => 100, "crop" => true}}
  }

config :brando, Brando.Instagram,
  server_name: :myapp_instagram,
  client_id: "",
  auto_approve: true,
  interval: 1_000 * 60 * 60,
  sleep: 5000,
  sizes: %{"large" =>  %{"size" => "640", "quality" => 100},
           "thumb" =>  %{"size" => "150x150", "quality" => 100, "crop" => true}},
  upload_path: Path.join("images", "instagram")

config :brando, Brando.Type.Role,
  roles: %{staff: 1, admin: 2, superuser: 4}

config :brando, Brando.Menu,
  colors: ["#FBA026;", "#F87117;", "#CF3510;", "#890606;", "#FF1B79;",
           "#520E24;", "#8F2041;", "#DC554F;", "#FF905E;", "#FAC51C;",
           "#D6145F;", "#AA0D43;", "#7A0623;", "#430202;", "#500422;",
           "#870B46;", "#D0201A;", "#FF641A;"],
  modules: [Admin, Users, News, Pages, Images]

config :brando, Brando.Villain,
  parser: <%= application_module %>.Villain.Parser