use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :brando, Brando.Integration.Endpoint,
  http: [port: 4001],
  server: false,
  secret_key_base: "verysecret"

config :brando, Brando.Integration.TestRepo,
  url: "ecto://postgres:postgres@localhost/brando_test",
  adapter: Ecto.Adapters.Postgres,
  extensions: [{Postgrex.Extensions.JSON, library: Poison}],
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 1,
  max_overflow: 0

config :brando, Brando.Menu, [
  modules: [Brando.Menu.Admin, Brando.Menu.Users,
            Brando.Menu.News, Brando.Menu.Images],
  colors: ["#FBA026;", "#F87117;", "#CF3510;", "#890606;", "#FF1B79;",
           "#520E24;", "#8F2041;", "#DC554F;", "#FF905E;", "#FAC51C;",
           "#D6145F;", "#AA0D43;", "#7A0623;", "#430202;", "#500422;",
           "#870B46;", "#D0201A;", "#FF641A;"]]

config :brando, Brando.Images, [
  default_config: %{allowed_mimetypes: ["image/jpeg", "image/png"],
                    default_size: :medium, size_limit: 10240000,
                    upload_path: Path.join("images", "default"),
                    sizes: %{
                      small:  %{size: "300", quality: 100},
                      medium: %{size: "500", quality: 100},
                      large:  %{size: "700", quality: 100},
                      xlarge: %{size: "900", quality: 100},
                      micro:  %{size: "25x25", quality: 100, crop: true},
                      thumb:  %{size: "150x150", quality: 100, crop: true}}},
  optimize: [
    png: [
      bin: "cp",
      args: "%{filename} %{new_filename}"]
    ]]

config :brando, :router, RouterHelper.TestRouter
config :brando, :endpoint, Brando.Integration.Endpoint
config :brando, :repo, Brando.Integration.TestRepo
config :brando, :helpers, RouterHelper.TestRouter.Helpers
config :brando, :media_url, "/media"
config :brando, :media_path, Path.join([Mix.Project.app_path, "tmp", "media"])
config :brando, Brando.Villain, parser: Brando.Villain.Parser.Default
config :brando, Brando.Villain, extra_blocks: []
config :brando, :logging, disable_logging: true
config :brando, :login_url, "/login"
config :brando, :default_language, "nb"
config :brando, :admin_default_language, "nb"
config :brando, :languages, [[value: "nb", text: "Norsk"],
                             [value: "en", text: "English"]]
config :brando, :admin_languages, [[value: "nb", text: "Norsk"],
                                   [value: "en", text: "English"]]
config :brando, :status_choices, [
          no: [[value: "0", text: "Kladd"],
               [value: "1", text: "Publisert"],
               [value: "2", text: "Venter"],
               [value: "3", text: "Slettet"]],
          en: [[value: "0", text: "Draft"],
               [value: "1", text: "Published"],
               [value: "2", text: "Pending"],
               [value: "3", text: "Deleted"]]]


config :brando, Brando.Instagram,
  client_id: "CLIENT_ID",
  interval: 1_000 * 60 * 60,
  upload_path: Path.join("images", "insta"),
  sleep: 0,
  auto_approve: true

# Print only warnings and errors during test
config :logger, level: :warn
