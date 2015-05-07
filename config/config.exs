# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

config :brando,
  app_name: "MyApp",
  endpoint: Brando.Endpoint,
  repo: Brando.Repo,
  router: Brando.Router,
  helpers: Brando.Router.Helpers,
  media_url: "/media",
  media_path: Path.join([Mix.Project.app_path, "priv", "media"])

config :brando, Brando.Images,
  default_config: %{allowed_mimetypes: ["image/jpeg", "image/png"],
                    default_size: :medium, random_filename: true,
                    upload_path: Path.join("images", "default"),
                    size_limit: 10240000,
                    sizes: %{small:  %{size: "300", quality: 100},
                             medium: %{size: "500", quality: 100},
                             large:  %{size: "700", quality: 100},
                             xlarge: %{size: "900", quality: 100},
                             thumb:  %{size: "150x150", quality: 100, crop: true}}}

config :brando, Brando.Type.Role,
  roles: %{staff: 1, admin: 2, superuser: 4}

config :brando, Brando.Instagram,
  client_id: "",
  auto_approve: true,
  interval: 1_000 * 60 * 60

config :brando, Brando.Menu,
  colors: ["#FBA026;", "#F87117;", "#CF3510;", "#890606;", "#FF1B79;",
           "#520E24;", "#8F2041;", "#DC554F;", "#FF905E;", "#FAC51C;",
           "#D6145F;", "#AA0D43;", "#7A0623;", "#430202;", "#500422;",
           "#870B46;", "#D0201A;", "#FF641A;"],
  modules: [Admin, Users, News, Images]

config :brando, Brando.Villain,
  parser: Brando.Villain.Parser.Default

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"