# Default generated Brando configuration

use Mix.Config

config :brando,
  app_name: "<%= application_module %>",
  endpoint: <%= application_module %>.Endpoint,
  login_url: "/login",
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
                    sizes: %{small:  %{size: "300", quality: 100},
                             medium: %{size: "500", quality: 100},
                             large:  %{size: "700", quality: 100},
                             xlarge: %{size: "900", quality: 100},
                             thumb:  %{size: "150x150^ -gravity center -extent 150x150", quality: 100, crop: true}}
  }

config :brando, Brando.Instagram,
  client_id: "",
  interval: 1_000 * 60 * 60

config :brando, Brando.Type.Role,
  roles: %{staff: 1, admin: 2, superuser: 4}

config :brando, Brando.Menu,
  colors: ["#FBA026;", "#F87117;", "#CF3510;", "#890606;", "#FF1B79;",
           "#520E24;", "#8F2041;", "#DC554F;", "#FF905E;", "#FAC51C;",
           "#D6145F;", "#AA0D43;", "#7A0623;", "#430202;", "#500422;",
           "#870B46;", "#D0201A;", "#FF641A;"],
  modules: [Admin, Users, News, Images]

config :brando, Villain,
  parser: <%= application_module %>.Villain.Parser