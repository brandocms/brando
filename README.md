![Brando logo](https://raw.githubusercontent.com/twined/brando/master/priv/static/brando/img/brando-big.png)

[![Build Status](https://travis-ci.org/twined/brando.png?branch=master)](https://travis-ci.org/twined/brando)
[![Coverage Status](https://coveralls.io/repos/twined/brando/badge.png?branch=master)](https://coveralls.io/r/twined/brando?branch=master)
[![Inline docs](http://inch-ci.org/github/twined/brando.png?branch=master)](http://inch-ci.org/github/twined/brando)

*EXPERIMENTAL, DO NOT USE*

Install:
--------
Add Brando and bcrypt to your `deps` and `applications`
in your project's `mix.exs`:

```elixir
def application do
  [mod: {MyApp, []},
   applications: [:phoenix, :cowboy, :logger, :postgrex,
                  :ecto, :bcrypt, :brando]]
end

defp deps do
  [{:bcrypt, github: "opscode/erlang-bcrypt"},
   {:brando, github: "twined/brando"]}
end
```

Add to your `config/config.exs` right before the env-specific import:

```elixir
# insert -- begin
import_config "brando.exs"
# insert -- end
import_config "#{Mix.env}.exs"
```

Install Brando:

    $ mix brando.install

Create the database:

    $ mix ecto.create

Now for the routes/pipelines/plugs in `web/router.ex`:

```elixir
import Brando.Routes.Admin.Users
alias Brando.Plug.Authenticate

pipeline :admin do
  plug :accepts, ~w(html json)
  plug :fetch_session
  plug :fetch_flash
  plug :put_layout, {Brando.Admin.LayoutView, "admin.html"}
  plug Authenticate, login_url: "/login"
end

scope "/admin", as: :admin do
  pipe_through :admin
  user_resources "/brukere"
  post_resources "/nyheter"
  image_resources "/bilder"
  get "/", Brando.Admin.DashboardController, :dashboard
end

scope "/" do
  pipe_through :browser
  get "/login", Brando.AuthController, :login,
    private: %{model: Brando.User}
  post "/login", Brando.AuthController, :login,
    private: %{model: Brando.User}
  get "/logout", Brando.AuthController, :logout,
    private: %{model: Brando.User}
end
```

Static config in `endpoint.ex`:

```elixir
plug Plug.Static,
  at: "/static", from: :brando

plug Plug.Static,
  at: "/media", from: "priv/media"
```

Configuration:
--------------

In your `config/config.exs`:

```elixir
config :brando,
  app_name: "MyApp",
  router: MyApp.Router,
  endpoint: MyApp.Endpoint,
  repo: MyApp.Repo,
  media_url: "/media",
  static_url: "/static",
  templates_path: "path/to/brando/templates",

config :brando, Brando.Menu,
  colors: ["#FBA026;", "#F87117;", "#CF3510;", "#890606;", "#FF1B79;",
           "#520E24;", "#8F2041;", "#DC554F;", "#FF905E;", "#FAC51C;",
           "#D6145F;", "#AA0D43;", "#7A0623;", "#430202;", "#500422;",
           "#870B46;", "#D0201A;", "#FF641A;"],
  modules: [Admin, Users, News, Images]

# configures the repo
config :my_app, MyApp.Repo,
  database: "my_app",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"
  adapter: Ecto.Adapters.Postgres,
  extensions: [{Brando.Postgrex.Extension.JSON, library: Poison}]
```

Optimizing images: (not implemented yet)

```elixir
config :brando, :images, :optimize
  png: [enabled: true,
        bin: "/usr/local/bin/pngquant",
        params: "--speed 1 --force --output \"#{new_filename}\" -- \"#{filename}\""],
  jpeg: [enabled: true,
         bin: "/usr/local/bin/jpegoptim",
         params: "#{filename}"]
```