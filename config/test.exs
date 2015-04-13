use Mix.Config
alias Brando.Integration.TestRepo

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :brando, Brando.Endpoint,
  http: [port: 4001],
  server: false

config :brando, TestRepo,
  url: "ecto://postgres:postgres@localhost/brando_test",
  adapter: Ecto.Adapters.Postgres,
  extensions: [{Brando.Postgrex.Extension.JSON, library: Poison}],
  size: 1,
  max_overflow: 0

config :brando, Brando.Menu, [
  modules: [Brando.Admin, Brando.Users],
  colors: ["#FBA026;", "#F87117;", "#CF3510;", "#890606;", "#FF1B79;",
           "#520E24;", "#8F2041;", "#DC554F;", "#FF905E;", "#FAC51C;",
           "#D6145F;", "#AA0D43;", "#7A0623;", "#430202;", "#500422;",
           "#870B46;", "#D0201A;", "#FF641A;"]]

config :brando, :router, RouterHelper.TestRouter
config :brando, :endpoint, Brando.Integration.Endpoint
config :brando, :repo, Brando.Integration.TestRepo
config :brando, :media_url, "/media"
config :brando, Villain, parser: Brando.Villain.Parser.Default

# Print only warnings and errors during test
config :logger, level: :warn